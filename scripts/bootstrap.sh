#!/usr/bin/env bash
# Idempotent: starts GitLab, configures it (root PAT + password, local-webhook setting,
# bot user + PAT, project, membership, webhook), writes tokens into .env, starts and
# verifies PR-Agent. Safe to re-run.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="$ROOT_DIR/.env"
STATE_DIR="$ROOT_DIR/.state"
ROOT_PAT_FILE="$STATE_DIR/root-pat"
GITLAB_URL="http://localhost:8929"
API="$GITLAB_URL/api/v4"
BOT_USERNAME="pr-agent-bot"
BOT_NAME="DEIM AI Reviewer"   # display name; username stays pr-agent-bot (scripts and scoring match on it)
PROJECT_PATH="root/payments-demo"
PROJECT_PATH_ENC="root%2Fpayments-demo"
HOOK_URL="http://127.0.0.1:3333/webhook"   # not localhost: inside GitLab it resolves to ::1, PR-Agent listens on IPv4 only
READY_TIMEOUT=900

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()  { printf '\033[1;32m ok\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- preflight ----------
for bin in docker curl python3 openssl git; do
  command -v "$bin" >/dev/null 2>&1 || die "'$bin' not found in PATH"
done
docker info >/dev/null 2>&1 || die "Docker daemon not reachable. Start Docker Desktop: systemctl --user start docker-desktop"
docker compose version >/dev/null 2>&1 || die "'docker compose' plugin not available"
[[ -f "$ENV_FILE" ]] || die ".env missing. Run: cp .env.example .env  and fill it in"
chmod 600 "$ENV_FILE"

set -a; # shellcheck disable=SC1090
. "$ENV_FILE"; set +a
for v in OPENCODE_GO_API_KEY PR_AGENT_MODEL GITLAB_ROOT_PASSWORD; do
  [[ -n "${!v:-}" ]] || die "$v is empty in .env"
done
curl -fsS -H "Authorization: Bearer $OPENCODE_GO_API_KEY" https://opencode.ai/inference/go/v1/models >/dev/null \
  || die "OpenCode Go unreachable or key invalid"
ok "OpenCode Go key accepted"
mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"

# ---------- helpers (python3 for JSON; no jq dependency) ----------
jbody() {  # jbody key=string key:=json ...
  python3 -c 'import json,sys
d={}
for a in sys.argv[1:]:
    k,v=a.split("=",1)
    if k.endswith(":"):
        d[k[:-1]]=json.loads(v)
    else:
        d[k]=v
print(json.dumps(d))' "$@"
}
jget() {   # echo JSON | jget path.to.0.field
  python3 -c 'import json,sys
d=json.load(sys.stdin)
for p in [x for x in sys.argv[1].split(".") if x]:
    if d is None: break
    d=(d[int(p)] if int(p)<len(d) else None) if isinstance(d,list) else d.get(p)
print("" if d is None else d)' "$1"
}
set_env() { # set_env KEY VALUE  (in-place, preserves other lines)
  python3 - "$ENV_FILE" "$1" "$2" <<'PY'
import re, sys
path, key, val = sys.argv[1:]
lines = open(path).read().splitlines()
out, found = [], False
for l in lines:
    if re.match(r'^\s*' + re.escape(key) + r'=', l):
        if not found:
            out.append(f"{key}={val}")
        found = True
    else:
        out.append(l)
if not found:
    out.append(f"{key}={val}")
open(path, "w").write("\n".join(out) + "\n")
PY
}

API_STATUS=""; API_BODY=""
api() {  # api METHOD PATH [JSON_BODY]
  local method=$1 path=$2 body=${3:-} tmp
  tmp=$(mktemp)
  local args=(-sS -o "$tmp" -w '%{http_code}' -X "$method" -H "PRIVATE-TOKEN: $ROOT_PAT" -H 'Content-Type: application/json')
  [[ -n "$body" ]] && args+=(--data "$body")
  API_STATUS=$(curl "${args[@]}" "$API$path" || true)
  API_BODY=$(cat "$tmp"); rm -f "$tmp"
}
expect() { # expect STATUS...
  local s; for s in "$@"; do [[ "$API_STATUS" == "$s" ]] && return 0; done
  die "GitLab API returned $API_STATUS (expected $*): $API_BODY"
}
token_user() { # prints username for a token, or empty
  local t=$1 code body
  body=$(curl -sS -H "PRIVATE-TOKEN: $t" -w '\n%{http_code}' "$API/user" 2>/dev/null || true)
  code=${body##*$'\n'}; body=${body%$'\n'*}
  if [[ "$code" == "200" ]]; then printf '%s' "$body" | jget username; fi
}

# ---------- 1. start GitLab + wait ----------
log "Starting GitLab container (first run pulls the image; no-op if running)"
docker compose up -d gitlab

log "Waiting for GitLab at $GITLAB_URL (timeout ${READY_TIMEOUT}s; first boot takes 5-10 min)"
start=$(date +%s)
while :; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$GITLAB_URL/users/sign_in" || true)
  elapsed=$(( $(date +%s) - start ))
  if [[ "$code" == "200" ]] && docker compose exec -T gitlab wget -q -O /dev/null http://localhost:8929/-/readiness >/dev/null 2>&1; then
    ok "GitLab ready after ${elapsed}s"; break
  fi
  (( elapsed >= READY_TIMEOUT )) && die "GitLab not ready after ${READY_TIMEOUT}s (last HTTP $code). Check: docker compose logs --tail=100 gitlab"
  printf '    ... %4ss elapsed, /users/sign_in -> HTTP %s\n' "$elapsed" "$code"
  sleep 15
done

# ---------- 2. root PAT ----------
ROOT_PAT=""
if [[ -s "$ROOT_PAT_FILE" ]]; then
  candidate=$(cat "$ROOT_PAT_FILE")
  [[ "$(token_user "$candidate")" == "root" ]] && ROOT_PAT=$candidate
fi
if [[ -z "$ROOT_PAT" ]]; then
  log "Creating root PAT via gitlab-rails runner (takes ~1 min)"
  ROOT_PAT=$(openssl rand -hex 10)   # 20 chars, as required by set_token
  docker compose exec -T gitlab gitlab-rails runner \
    "t = User.find_by_username('root').personal_access_tokens.create(scopes: ['api'], name: 'pr-agent-demo-bootstrap', expires_at: 30.days.from_now); t.set_token('$ROOT_PAT'); t.save!" \
    || die "gitlab-rails runner failed"
  for _ in $(seq 1 12); do
    [[ "$(token_user "$ROOT_PAT")" == "root" ]] && break
    sleep 5
  done
  [[ "$(token_user "$ROOT_PAT")" == "root" ]] || die "Root PAT created but GET /user does not accept it"
  ( umask 077; printf '%s' "$ROOT_PAT" > "$ROOT_PAT_FILE" )
  ok "root PAT stored in .state/root-pat"
else
  ok "reusing root PAT from .state/root-pat"
fi

# ---------- 3. root password ----------
log "Setting root password from .env"
api GET "/user"; expect 200
ROOT_ID=$(printf '%s' "$API_BODY" | jget id)
api PUT "/users/$ROOT_ID" "$(jbody "password=$GITLAB_ROOT_PASSWORD")"
expect 200
ok "root password set (login: root / GITLAB_ROOT_PASSWORD)"

# ---------- 4. allow webhooks to local network ----------
log "Allowing webhooks to local network"
api PUT "/application/settings" "$(jbody allow_local_requests_from_web_hooks_and_services:=true)"
expect 200
ok "allow_local_requests_from_web_hooks_and_services=true"

# ---------- 5. bot user ----------
log "Ensuring user $BOT_USERNAME"
api GET "/users?username=$BOT_USERNAME"; expect 200
BOT_ID=$(printf '%s' "$API_BODY" | jget 0.id)
if [[ -z "$BOT_ID" ]]; then
  api POST "/users" "$(jbody "username=$BOT_USERNAME" "name=$BOT_NAME" "email=$BOT_EMAIL" force_random_password:=true skip_confirmation:=true)"
  expect 201
  BOT_ID=$(printf '%s' "$API_BODY" | jget id)
  ok "created $BOT_USERNAME (id $BOT_ID)"
else
  api PUT "/users/$BOT_ID" "$(jbody "name=$BOT_NAME")"   # keep the display name in sync
  expect 200
  ok "$BOT_USERNAME exists (id $BOT_ID), display name: $BOT_NAME"
fi

# ---------- 6. bot PAT ----------
BOT_PAT="${PR_AGENT_GITLAB_TOKEN:-}"
if [[ -n "$BOT_PAT" && "$(token_user "$BOT_PAT")" == "$BOT_USERNAME" ]]; then
  ok "reusing bot PAT from .env"
else
  log "Creating bot PAT (scope api, 30 days)"
  exp=$(python3 -c 'import datetime;print((datetime.date.today()+datetime.timedelta(days=30)).isoformat())')
  api POST "/users/$BOT_ID/personal_access_tokens" "$(jbody name=pr-agent-demo 'scopes:=["api"]' expires_at=$exp)"
  expect 201
  BOT_PAT=$(printf '%s' "$API_BODY" | jget token)
  [[ -n "$BOT_PAT" ]] || die "No token in response: $API_BODY"
  ok "bot PAT created"
fi

# ---------- 7. project ----------
log "Ensuring project $PROJECT_PATH"
api GET "/projects/$PROJECT_PATH_ENC"
if [[ "$API_STATUS" == "404" ]]; then
  api POST "/projects" "$(jbody name=payments-demo path=payments-demo visibility=private initialize_with_readme:=false)"
  expect 201
  ok "created $PROJECT_PATH"
else
  expect 200; ok "$PROJECT_PATH exists"
fi
PROJECT_ID=$(printf '%s' "$API_BODY" | jget id)

log "Checking git-over-HTTP auth with the root PAT"
git ls-remote "http://root:${ROOT_PAT}@localhost:8929/${PROJECT_PATH}.git" >/dev/null \
  || die "git ls-remote with root PAT failed (push auth would fail)"
ok "git auth works"

# ---------- 8. bot membership (Developer = 30) ----------
api GET "/projects/$PROJECT_ID/members/$BOT_ID"
if [[ "$API_STATUS" == "404" ]]; then
  api POST "/projects/$PROJECT_ID/members" "$(jbody user_id:=$BOT_ID access_level:=30)"
  expect 201
  ok "$BOT_USERNAME added as Developer"
else
  expect 200; ok "$BOT_USERNAME already a member"
fi

# ---------- 9. webhook secret + webhook ----------
SECRET="${PR_AGENT_WEBHOOK_SECRET:-}"
if [[ -z "$SECRET" ]]; then
  SECRET="whs_$(openssl rand -hex 20)"
  ok "generated webhook secret"
fi
HOOK_BODY=$(jbody url=$HOOK_URL token=$SECRET merge_requests_events:=true note_events:=true push_events:=false)
api GET "/projects/$PROJECT_ID/hooks"; expect 200
HOOK_ID=$(printf '%s' "$API_BODY" | python3 -c 'import json,sys; print(next((str(h["id"]) for h in json.load(sys.stdin) if h.get("url")==sys.argv[1]), ""))' "$HOOK_URL")
if [[ -z "$HOOK_ID" ]]; then
  api POST "/projects/$PROJECT_ID/hooks" "$HOOK_BODY"; expect 201
  ok "webhook created -> $HOOK_URL"
else
  api PUT "/projects/$PROJECT_ID/hooks/$HOOK_ID" "$HOOK_BODY"; expect 200
  ok "webhook $HOOK_ID exists; secret/events re-synced"
fi

# ---------- 10. persist into .env (and this shell, which compose reads first) ----------
set_env PR_AGENT_GITLAB_TOKEN "$BOT_PAT"
set_env PR_AGENT_WEBHOOK_SECRET "$SECRET"
chmod 600 "$ENV_FILE"
export PR_AGENT_GITLAB_TOKEN="$BOT_PAT" PR_AGENT_WEBHOOK_SECRET="$SECRET"
ok ".env updated (PR_AGENT_GITLAB_TOKEN, PR_AGENT_WEBHOOK_SECRET)"

# ---------- 11. start + verify PR-Agent ----------
log "Starting PR-Agent (recreated if env changed)"
docker compose up -d pr-agent
for i in $(seq 1 30); do
  curl -fsS http://localhost:3333/ >/dev/null 2>&1 && break
  (( i == 30 )) && die "PR-Agent not answering on :3333. Check: docker compose logs --tail=100 pr-agent"
  sleep 3
done
good=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
  -H "X-Gitlab-Token: $SECRET" --data '{}' http://localhost:3333/webhook)
bad=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
  -H "X-Gitlab-Token: wrong-secret" --data '{}' http://localhost:3333/webhook)
[[ "$good" == "200" ]] || die "Webhook with correct secret returned $good (expected 200). PR-Agent has a stale/empty secret?"
[[ "$bad" == "401" ]]  || die "Webhook with wrong secret returned $bad (expected 401)"
ok "PR-Agent webhook auth verified (correct secret -> 200, wrong -> 401)"

cat <<EOF

Done.
  GitLab:   $GITLAB_URL   (user: root / password: GITLAB_ROOT_PASSWORD from .env)
  Project:  $GITLAB_URL/$PROJECT_PATH
  Next:     ./scripts/seed-repo.sh
EOF
