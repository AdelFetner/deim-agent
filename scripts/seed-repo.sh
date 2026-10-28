#!/usr/bin/env bash
# Builds payments-demo from demo-repo/ and pushes it to local GitLab.
#   demo-repo/main/                          -> branch main (protected after first push)
#   demo-repo/branches/<branch>/             -> <branch> = main + one overlay commit
#     .mr-title, .mr-description.md          -> MR title/description (never committed)
#   demo-repo/fixes/feature/payment-search/  -> live fix commit (--push-fix)
#     .commit-message (optional)             -> fix commit message (never committed)
# Usage:
#   seed-repo.sh                             push main + all branches (deterministic, no force)
#   seed-repo.sh --open-mrs <branch|all>     push, then open MR(s); 'all' opens one at a time
#                                            and waits until the bot's notes are stable
#   seed-repo.sh --no-push --open-mrs <branch|all>
#   seed-repo.sh --push-fix                  add fix commit on feature/payment-search, push
#   seed-repo.sh --reset-mr <branch>         delete the open MR for <branch>, force-push the
#                                            branch back to its base commit
# Changing demo-repo/main after the first push requires ./scripts/teardown.sh (main is protected).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BRANCHES=(feature/payment-search feature/refund-batch feature/payment-cache chore/rename-dto)
FIX_BRANCH="feature/payment-search"
SRC="$ROOT_DIR/demo-repo"
ROOT_PAT_FILE="$ROOT_DIR/.state/root-pat"
GITLAB_URL="http://localhost:8929"
API="$GITLAB_URL/api/v4"
PROJECT_PATH_ENC="root%2Fpayments-demo"
BOT_USERNAME="pr-agent-bot"
BASE_DATE="2026-10-20T10:00:00-03:00"
FIX_DATE="2026-10-21T10:00:00-03:00"
META_EXCLUDES=(--exclude=./.mr-title --exclude=./.mr-description.md --exclude=./.commit-message)

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()  { printf '\033[1;32m ok\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; exit "${1:-0}"; }

DO_PUSH=1; OPEN=""; PUSH_FIX=0; RESET=""
while (( $# )); do
  case "$1" in
    --open-mrs) [[ $# -ge 2 ]] || usage 1; OPEN=$2; shift 2 ;;
    --no-push)  DO_PUSH=0; shift ;;
    --push-fix) PUSH_FIX=1; shift ;;
    --reset-mr) [[ $# -ge 2 ]] || usage 1; RESET=$2; shift 2 ;;
    -h|--help)  usage 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage 1 ;;
  esac
done

for bin in git curl python3 tar awk; do
  command -v "$bin" >/dev/null 2>&1 || die "'$bin' not found"
done
[[ -s "$ROOT_PAT_FILE" ]] || die "No root PAT. Run ./scripts/bootstrap.sh first"
ROOT_PAT=$(cat "$ROOT_PAT_FILE")
REMOTE="http://root:${ROOT_PAT}@localhost:8929/root/payments-demo.git"
[[ -d "$SRC/main" ]] || die "Missing $SRC/main"
for b in "${BRANCHES[@]}"; do
  [[ -d "$SRC/branches/$b" ]]           || die "Missing $SRC/branches/$b"
  [[ -s "$SRC/branches/$b/.mr-title" ]] || die "Missing $SRC/branches/$b/.mr-title"
done
valid_branch() { local b; for b in "${BRANCHES[@]}"; do [[ "$b" == "$1" ]] && return 0; done; return 1; }
[[ -z "$OPEN" || "$OPEN" == "all" ]] || valid_branch "$OPEN" || die "Unknown branch '$OPEN'. Valid: all ${BRANCHES[*]}"
[[ -z "$RESET" ]] || valid_branch "$RESET" || die "Unknown branch '$RESET'. Valid: ${BRANCHES[*]}"

urlenc() { python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$1"; }
gl() { curl -fsS -H "PRIVATE-TOKEN: $ROOT_PAT" "$@"; }

# ---------- deterministic build ----------
WORK=""
cleanup() { [[ -n "$WORK" ]] && rm -rf "$WORK"; }
trap cleanup EXIT
build_repo() {
  WORK=$(mktemp -d)
  export GIT_AUTHOR_NAME="Administrator" GIT_AUTHOR_EMAIL="admin@example.com"
  export GIT_COMMITTER_NAME="Administrator" GIT_COMMITTER_EMAIL="admin@example.com"
  export GIT_AUTHOR_DATE="$BASE_DATE" GIT_COMMITTER_DATE="$BASE_DATE"
  git -C "$WORK" init -q -b main
  git -C "$WORK" config commit.gpgsign false
  (cd "$SRC/main" && tar cf - .) | (cd "$WORK" && tar xf -)
  git -C "$WORK" add -A
  git -C "$WORK" commit -q -m "Initial import of payments-demo"
  local b
  for b in "${BRANCHES[@]}"; do
    git -C "$WORK" checkout -q -B "$b" main
    (cd "$SRC/branches/$b" && tar cf - "${META_EXCLUDES[@]}" .) | (cd "$WORK" && tar xf -)
    git -C "$WORK" add -A
    git -C "$WORK" commit -q -m "$(head -n1 "$SRC/branches/$b/.mr-title")"
  done
  git -C "$WORK" checkout -q main
}

open_mr_iids() { # open_mr_iids <branch> -> "iid url" lines for open MRs
  gl "$API/projects/$PROJECT_PATH_ENC/merge_requests?state=opened&source_branch=$(urlenc "$1")" \
    | python3 -c 'import json,sys
for m in json.load(sys.stdin): print(m["iid"], m["web_url"])'
}

# ---------- --reset-mr ----------
if [[ -n "$RESET" ]]; then
  while read -r iid url; do
    [[ -n "$iid" ]] || continue
    gl -X DELETE "$API/projects/$PROJECT_PATH_ENC/merge_requests/$iid" >/dev/null
    ok "deleted MR !$iid ($url)"
  done < <(open_mr_iids "$RESET")
  build_repo
  git -C "$WORK" push -q --force "$REMOTE" "$RESET"
  ok "$RESET force-pushed back to base $(git -C "$WORK" rev-parse --short "$RESET")"
  exit 0
fi

# ---------- --push-fix ----------
if (( PUSH_FIX )); then
  FIX_DIR="$SRC/fixes/$FIX_BRANCH"
  [[ -d "$FIX_DIR" ]] || die "Missing $FIX_DIR"
  build_repo
  git -C "$WORK" checkout -q "$FIX_BRANCH"
  (cd "$FIX_DIR" && tar cf - "${META_EXCLUDES[@]}" .) | (cd "$WORK" && tar xf -)
  msg="Fix SQL injection and connection leak in payment search"
  [[ -s "$FIX_DIR/.commit-message" ]] && msg=$(cat "$FIX_DIR/.commit-message")
  git -C "$WORK" add -A
  GIT_AUTHOR_DATE="$FIX_DATE" GIT_COMMITTER_DATE="$FIX_DATE" git -C "$WORK" commit -q -m "$msg"
  git -C "$WORK" push -q "$REMOTE" "$FIX_BRANCH" \
    || die "Push rejected. Branch diverged? Reset with: ./scripts/seed-repo.sh --reset-mr $FIX_BRANCH"
  ok "fix pushed to $FIX_BRANCH ($(git -C "$WORK" rev-parse --short HEAD)); PR-Agent re-runs /review on the MR"
  exit 0
fi

# ---------- push (no force) ----------
if (( DO_PUSH )); then
  log "Building main + ${#BRANCHES[@]} branches from demo-repo/"
  build_repo
  log "Pushing to $GITLAB_URL/root/payments-demo"
  git -C "$WORK" push -q "$REMOTE" main "${BRANCHES[@]}" \
    || die "Push rejected. A branch diverged (fix pushed?) -> --reset-mr <branch>; main changed -> teardown"
  ok "pushed: main ${BRANCHES[*]}"
fi

# ---------- open MRs ----------
[[ -z "$OPEN" ]] && exit 0

wait_bot_stable() { # wait_bot_stable <iid>: bot notes unchanged for 60 s (poll 15 s, timeout 10 min)
  local iid=$1 deadline=$((SECONDS + 600)) last="" since=$SECONDS sig
  log "Waiting for $BOT_USERNAME to finish on !$iid (stable 60 s, timeout 10 min)"
  while (( SECONDS < deadline )); do
    sig=$(gl "$API/projects/$PROJECT_PATH_ENC/merge_requests/$iid/notes?per_page=100" \
      | python3 -c 'import json,sys
n=[x for x in json.load(sys.stdin) if x["author"]["username"]==sys.argv[1]]
print(f"{len(n)}|{max((x["updated_at"] for x in n), default="")}")' "$BOT_USERNAME")
    if [[ "${sig%%|*}" != "0" && "$sig" == "$last" ]]; then
      if (( SECONDS - since >= 60 )); then ok "!$iid: ${sig%%|*} bot notes, stable"; return 0; fi
    else
      last=$sig; since=$SECONDS
    fi
    printf '    ... bot notes: %s\n' "${sig%%|*}"
    sleep 15
  done
  die "Timeout waiting for bot on !$iid. Check: docker compose logs --tail=100 pr-agent"
}

open_one() { # open_one <branch> -> prints iid
  local b=$1 existing body resp
  existing=$(open_mr_iids "$b" | head -n1)
  if [[ -n "$existing" ]]; then
    ok "MR already open for $b: ${existing#* }" >&2; printf '%s' "${existing%% *}"; return 0
  fi
  body=$(python3 - "$b" "$SRC/branches/$b" <<'PY'
import json, os, sys
branch, d = sys.argv[1:]
title = open(os.path.join(d, ".mr-title")).read().strip().splitlines()[0]
dp = os.path.join(d, ".mr-description.md")
desc = open(dp).read() if os.path.exists(dp) else ""
print(json.dumps({"source_branch": branch, "target_branch": "main",
                  "title": title, "description": desc, "remove_source_branch": False}))
PY
)
  resp=$(curl -sS --fail-with-body -X POST -H "PRIVATE-TOKEN: $ROOT_PAT" -H 'Content-Type: application/json' \
    --data "$body" "$API/projects/$PROJECT_PATH_ENC/merge_requests") || die "MR create failed for $b: $resp"
  ok "MR opened for $b: $(printf '%s' "$resp" | python3 -c 'import json,sys;print(json.load(sys.stdin)["web_url"])')" >&2
  printf '%s' "$resp" | python3 -c 'import json,sys;print(json.load(sys.stdin)["iid"],end="")'
}

if [[ "$OPEN" == "all" ]]; then
  for b in "${BRANCHES[@]}"; do
    iid=$(open_one "$b")
    wait_bot_stable "$iid"
  done
else
  open_one "$OPEN" >/dev/null
  echo "PR-Agent output from @$BOT_USERNAME should appear within ~1-4 min. Follow: docker compose logs -f pr-agent"
fi
