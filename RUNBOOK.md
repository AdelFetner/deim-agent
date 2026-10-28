# PR-Agent × GitLab — local demo runbook

A local GitLab CE 19.5.1 and PR-Agent 0.48.0 run in Docker on this laptop. Both images are pinned by digest. When a merge request is opened in `root/payments-demo`, PR-Agent (GitLab user `pr-agent-bot`, shown as **DEIM AI Reviewer**) runs `/describe`, `/review` and `/improve`. The LLM is reached through OpenCode Go (OpenAI-compatible endpoint `https://opencode.ai/inference/go/openai/v1`). Both ports are bound to 127.0.0.1 only.

## Requirements
- **Docker Desktop** with memory ≥ **7 GiB** (Settings → Resources; this laptop is set to 7168 MiB because host apps use ~9 GB and a 10 GiB VM got the Docker service OOM-killed by the host). GitLab is capped at 5 GB.
- **Host tools:** `docker` (with compose), `git`, `curl`, `python3`, `openssl`, `tar`.
- **OpenCode Go:** a Go (USD 10/month) or Go Plus subscription and its API key (`oc_…`) from https://opencode.ai/console.
  - Go caps usage per model (5-hour 20%, weekly 50%, monthly 100% of the model's monthly limit); the demo uses a small fraction.
  - Go is meant for coding-agent traffic; PR-Agent is not one of its validated clients, so the compose file sends its own `User-Agent` and an `x-opencode-session` header (`LITELLM__EXTRA_HEADERS`).
  - Workspace **Settings → Privacy** must allow the models used (DeepSeek needs the **Global** region).
- Host ports 127.0.0.1:8929 and 127.0.0.1:3333 must be free.

## File tree
```
~/pr-agent-demo/
├── docker-compose.yml
├── .env.example
├── .env                      # created by you, git-ignored, chmod 600
├── .gitignore
├── RUNBOOK.md
├── scripts/
│   ├── bootstrap.sh
│   ├── seed-repo.sh
│   └── teardown.sh
├── docs/
│   ├── proposal.md
│   ├── demo-script.md
│   ├── results.md
│   ├── answer-key.md
│   └── screenshots/
└── demo-repo/
    ├── main/**                              # incl. AGENTS.md, README.md, pom.xml, src/**
    ├── branches/
    │   ├── feature/payment-search/**        # + .mr-title, .mr-description.md
    │   ├── feature/refund-batch/**          # + .mr-title, .mr-description.md
    │   ├── feature/payment-cache/**         # + .mr-title, .mr-description.md
    │   └── chore/rename-dto/**              # + .mr-title, .mr-description.md
    └── fixes/
        └── feature/payment-search/**        # live fix overlay + .commit-message
```

## 1. Start Docker Desktop
```bash
systemctl --user start docker-desktop
until docker info >/dev/null 2>&1; do echo "waiting for docker..."; sleep 3; done
docker compose version
```

## 2. Create the demo dir and save the files
```bash
mkdir -p ~/pr-agent-demo/{scripts,docs/screenshots,demo-repo} && cd ~/pr-agent-demo
# save every file of the tree above
chmod +x scripts/*.sh
```

## 3. Configure secrets
```bash
cp .env.example .env && chmod 600 .env
```
Edit `.env`:
- `OPENCODE_GO_API_KEY`: subscribe to Go at https://opencode.ai/console, copy the API key and paste the `oc_...` value.
- `PR_AGENT_MODEL`: leave it as `openai/glm-5.3` (Model A). The `openai/` prefix makes PR-Agent use the OpenAI-compatible route with `OPENAI__API_BASE`.
- `GITLAB_ROOT_PASSWORD`: use a strong password, for example `openssl rand -base64 18 | tr -d '/+='`. bootstrap sets it through the API.
- Leave `PR_AGENT_GITLAB_TOKEN` and `PR_AGENT_WEBHOOK_SECRET` empty.

## 4. Bootstrap (starts GitLab too)
```bash
./scripts/bootstrap.sh
```
The script:
1. Checks the OpenCode Go key (`GET /inference/go/v1/models`).
2. Starts GitLab and waits for it, for up to 15 minutes. First boot takes 5–10 minutes.
3. Creates a root PAT (`.state/root-pat`) and sets the root password.
4. Allows webhooks to reach the local network.
5. Creates the `pr-agent-bot` user and its PAT.
6. Creates the project `root/payments-demo` and checks git push auth.
7. Adds the bot as Developer.
8. Creates the webhook `http://127.0.0.1:3333/webhook` with a secret, for MR and comment events. (`localhost` would resolve to IPv6 `::1` inside GitLab, where PR-Agent does not listen.)
9. Writes the token and secret into `.env`.
10. Starts `pr-agent` and checks that the webhook returns 200 with the right secret and 401 with a wrong one.

It is safe to re-run.

## 5. Log in
Open http://localhost:8929 and sign in as `root` with `GITLAB_ROOT_PASSWORD`.

## 6. Seed the repo
```bash
./scripts/seed-repo.sh        # push main + 4 branches (no MRs yet)
```
`main` is protected after the first push. To change `demo-repo/main`, run `./scripts/teardown.sh` and start again from step 4.

## 7. Smoke test (always, before any rehearsal or demo)
1. Run `./scripts/seed-repo.sh --open-mrs chore/rename-dto` and open the printed URL.
2. Within a few minutes, confirm that:
   - the `/describe` output updated the MR description,
   - a `/review` summary comment appeared,
   - `/improve` inline suggestions appeared (if any),
   - **Settings → Webhooks → Edit → Recent events** shows 200s.
3. Comment on the MR:
   ```
   /review --config.model=openai/deepseek-v4.1-flash --pr_reviewer.persistent_comment=false --pr_reviewer.inline_key_issues=false
   ```
   Confirm a **second** review comment whose run-details footer names the DeepSeek model.
4. Clean up: `./scripts/seed-repo.sh --reset-mr chore/rename-dto`.

## 8. Open an MR and what you should see
```bash
./scripts/seed-repo.sh --no-push --open-mrs feature/payment-search
```
Output from `pr-agent-bot` usually appears within 1–4 minutes:
1. **`/describe`** updates the MR **description** (type, summary, file walkthrough).
2. **`/review`** posts a summary comment, the **PR Reviewer Guide**, covering effort, security concerns and tests. The **key issues** appear as **inline threads on the Changes tab**, not in the Guide.
3. **`/improve`** posts **inline committable suggestion threads** on the Changes tab. With committable suggestions on, there is **no** suggestions table comment.

The run-details footer shows the model, tokens and cost. The cost may read "unavailable"; if so, compute it from tokens × the Go price table (see `docs/results.md`) and cross-check in the OpenCode console usage page.

## 9. Model B on the same MR (review only)
Comment:
```
/review --config.model=openai/deepseek-v4.1-flash --pr_reviewer.persistent_comment=false --pr_reviewer.inline_key_issues=false
```
This posts a separate review comment, so Model A's review is not overwritten. Do not run `/improve` with Model B.

Fallback, if the flag is rejected:
```bash
sed -i 's|^PR_AGENT_MODEL=.*|PR_AGENT_MODEL=openai/deepseek-v4.1-flash|' .env
docker compose up -d pr-agent
```
1. Comment `/review` on the MR.
2. Restore `PR_AGENT_MODEL=openai/glm-5.3`.
3. Run `docker compose up -d pr-agent` again.

## 10. Push the fix live
```bash
./scripts/seed-repo.sh --push-fix
```
This adds the fix commit to `feature/payment-search`. PR-Agent re-runs `/review` and `/improve` (push trigger). The updated Guide lists SQL injection and resource leak under "✅ Resolved findings". The `/improve` run resolves bot threads whose flagged line was changed by the fix (the resource-leak threads, line 55). The SQL-injection threads stay open because they are anchored on lines 50–51, which the fix leaves unchanged. Resolution is line-based.

## 11. Logs
```bash
docker compose logs -f pr-agent            # webhook hits, model calls, errors (INFO level)
docker compose logs --tail=200 gitlab
```
Webhook deliveries are under **Project → Settings → Webhooks → Edit → Recent events**.

## 12. Troubleshooting
| Symptom | Cause | Fix |
|---|---|---|
| bootstrap: `OpenCode Go unreachable or key invalid` | Wrong key, or the network or proxy blocks opencode.ai | Check the key in the OpenCode console. Behind a proxy, see the proxy row. |
| Creating the webhook returns 422 ("Invalid url" / local requests not allowed) | The local-request setting is off | Re-run bootstrap. Check Admin → Settings → Network → Outbound requests → "Allow requests to the local network from webhooks and integrations". |
| Recent events show **401**; pr-agent log shows `Failed to validate secret` | The secret differs between the hook and pr-agent | Re-run `./scripts/bootstrap.sh`. It re-syncs both and verifies 200/401. |
| The webhook shows a **disabled** / failing badge | GitLab auto-disabled it after repeated failures (for example after laptop sleep) | Settings → Webhooks → enable it again, or re-run bootstrap. Then comment `/review` on the MR. |
| pr-agent log shows a max tokens / model not defined error | `CONFIG__CUSTOM_MODEL_MAX_TOKENS` is missing | Check with `docker compose config \| grep MAX_TOKENS`, then run `docker compose up -d pr-agent`. |
| OpenCode Go **429** / limit error in the pr-agent log | The model's 5-hour, weekly or monthly Go allowance is used up | Wait for the window to reset, switch `PR_AGENT_MODEL` to another Go model, or enable **Extra Usage** on the Go page (falls back to pay-as-you-go balance). Then comment `/review` again. |
| OpenCode Go 4xx "model not allowed" / region error | Workspace privacy settings block the model | Console → Settings → Privacy: allow the **Global** region (DeepSeek). |
| **502** "Waiting for GitLab to boot" | GitLab is still starting | Wait until `docker compose ps` shows `healthy`. |
| Slow UI, containers restart, exit code 137 | Memory pressure | Docker Desktop memory ≥ 7 GiB. Close other apps (the host OOM-kills Docker Desktop when swap is full). Check `docker stats --no-stream` and `free -m`. |
| `curl localhost:3333` fails after GitLab or Docker restarted | pr-agent lost GitLab's network namespace | `docker compose up -d --force-recreate pr-agent` |
| No bot output, and Recent events are empty | The MR was opened before the hook existed | Comment `/review`, or run `--reset-mr <branch>` and open it again. |
| Corporate proxy needed for egress | The container has no proxy settings | Add `- HTTPS_PROXY=http://<proxy>:<port>` and `- NO_PROXY=localhost,127.0.0.1` to the `pr-agent` environment in `docker-compose.yml`, then `docker compose up -d pr-agent`. |
| seed-repo push rejected | A branch diverged (fix pushed), or `demo-repo/main` changed | `--reset-mr <branch>`, or a teardown for `main` changes. |
| `git` 401/403 | The root PAT expired | `rm .state/root-pat && ./scripts/bootstrap.sh` |

## 13. Rehearsal (day before) and demo-day reset
1. Run the full flow from zero: steps 1–7. Note the first-boot time, the bootstrap time and the time from MR open to first bot output.
2. Open MR2–MR4 one at a time, waiting for the bot to finish each:
   ```bash
   ./scripts/seed-repo.sh --no-push --open-mrs feature/refund-batch
   ./scripts/seed-repo.sh --no-push --open-mrs feature/payment-cache
   ./scripts/seed-repo.sh --no-push --open-mrs chore/rename-dto
   ```
   **Keep** these MRs; they are shown in the demo.
   After the bot finishes each of the 4 MRs (MR1 included, opened in step 3 before its fix), comment the Model B command (§9), wait for the review, then comment the Model A comparable command `/review --pr_reviewer.persistent_comment=false --pr_reviewer.inline_key_issues=false` and wait. Do both on all four MRs before pushing the MR1 fix. Record the timings in `docs/results.md`.
3. Rehearse MR1 end to end (steps 8–10). Capture the screenshots listed in `docs/demo-script.md` into `docs/screenshots/`.
4. Record peak memory with `docker stats --no-stream` while the bot is running.
5. Reset only MR1: `./scripts/seed-repo.sh --reset-mr feature/payment-search`.
6. **Never run `teardown.sh` between rehearsal and demo.** At the end of the day, `./scripts/teardown.sh --keep-data` is fine. On demo day, run `./scripts/bootstrap.sh` and then `curl -fsS http://localhost:3333/`.

## 14. Teardown
```bash
./scripts/teardown.sh --keep-data   # stop, keep GitLab data
./scripts/teardown.sh               # stop + delete everything (asks 'yes')
systemctl --user stop docker-desktop
```

## 15. Produce the proposal (Markdown → DOCX → PDF)
1. Fill every `{{…}}` in `docs/proposal.md` from `docs/results.md`, using its "Before sending" list. Fill the `____` blanks (date, author, cap); leave the `___` success thresholds for the Team Leader. Delete the "Before sending" section.
2. Checks:
   ```bash
   grep -n '{{' docs/proposal.md                 # must print nothing
   pandoc docs/proposal.md -t plain | wc -w      # must be <= 1300
   ```
3. Convert:
   ```bash
   cd docs
   pandoc proposal.md -f markdown -t docx --reference-doc=reference.docx -o proposal.docx   # reference.docx = compact styles (10 pt body)
   libreoffice --headless --convert-to pdf --outdir . proposal.docx
   ```
4. Open `docs/proposal.pdf`; check that the tables render and the page count is about 3–4.

## 16. Everyday use for developers (user flow)

The reviewer works on its own most of the time; developers only need commands for on-demand runs.

**Automatic (nobody types anything):**

| Event | Reviewer action |
|---|---|
| MR opened (non-draft) | `/describe` (rewrites the MR description), `/review` (Guide comment + inline threads on the affected lines), `/improve` (inline one-click suggestions). |
| Draft MR | Nothing; drafts are skipped until marked ready. |
| New commit pushed to an open MR | Re-runs `/review` + `/improve`; threads whose flagged line changed are resolved. |

**Manual:** comment on the MR. The comment **must start with `/`** — a plain English comment is ignored (no model call). This works in the main comment box and as a reply inside a thread. Any project member can trigger it.

| Command | Effect |
|---|---|
| `/review` | Full review. By default it edits its previous review comment in place. |
| `/describe` | Regenerate the MR description. |
| `/improve` | Inline suggestion threads with GitLab's "Apply suggestion" button. |
| `/ask "question"` | Q&A about that MR (no AGENTS.md context is fed to this one). |

Flags can be appended, e.g. a second, separate review with Model B:
```
/review --config.model=openai/deepseek-v4.1-flash --pr_reviewer.persistent_comment=false --pr_reviewer.inline_key_issues=false
```
Unknown commands get a help reply. The reviewer never approves or merges anything.
