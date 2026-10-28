# Demo script — AI merge-request review with PR-Agent on GitLab

**Length:** 15 min talk + 5 min Q&A. **No slides:** the screen shows GitLab, a terminal, `docs/results.md` and `docs/proposal.md`. Talk in Spanish; the UI is in English.

GitLab: http://localhost:8929, project `root/payments-demo`, logged in as `root`. Working directory: `~/pr-agent-demo`.

## Rehearsal (day before)

1. Run the full flow from zero once (RUNBOOK) on the real laptop instance and **keep it**. Never run `teardown.sh` between rehearsal and demo.
2. Open the 4 MRs **one at a time**, waiting until the bot has finished each one. After the bot finishes each of the 4 MRs, comment the Model B command, wait for the review, then comment the Model A comparable command `/review --pr_reviewer.persistent_comment=false --pr_reviewer.inline_key_issues=false` and wait. Do both on all four MRs before pushing the MR1 fix. Record the timings in `docs/results.md`.
3. Push the MR1 fix with `./scripts/seed-repo.sh --push-fix`. Fill `docs/results.md`, then the proposal placeholders.
4. Capture these screenshots into `docs/screenshots/`:
   - `01-mr1-describe.png` — generated description
   - `02-mr1-review-guide.png` — PR Reviewer Guide comment
   - `03-mr1-inline-key-issues.png` — Changes tab with inline key-issue threads
   - `04-mr1-improve-suggestions.png` — an inline committable suggestion
   - `05-mr1-model-b-review.png` — Model B review comment
   - `06-mr1-rereview-after-fix.png` — re-review plus resolved threads
5. Then `./scripts/seed-repo.sh --reset-mr feature/payment-search`. This deletes MR1 and force-pushes the unfixed branch. MR2–MR4 and their bot comments stay.

## Pre-demo checklist (T–30 min)

- [ ] `docker compose ps`: `gitlab` healthy, `pr-agent` up. `docker stats --no-stream`: the GitLab container is well below its memory limit, and the host has ≥ 6 GB RAM free (close the IDE and spare tabs).
- [ ] `curl -s -o /dev/null -w '%{http_code}\n' http://localhost:3333/` returns `200`.
- [ ] Load the key first: `set -a; . ~/pr-agent-demo/.env; set +a   # loads OPENCODE_GO_API_KEY into this shell (do not echo it)`. Key works: `curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $OPENCODE_GO_API_KEY" https://opencode.ai/inference/go/v1/models` returns `200`. In the OpenCode console, the Go usage for GLM-5.3 and DeepSeek V4.1 Flash is well below the 5-hour limit; note the usage as the start value for the cost check.
- [ ] Settings → Webhooks: the hook `http://127.0.0.1:3333/webhook` is **not disabled** (no failure or disabled badge), and Recent events show `200` for the rehearsal MRs. Do **not** press "Test", because it replays a real MR event.
- [ ] `.env` has `PR_AGENT_MODEL=openai/glm-5.3`.
- [ ] `--reset-mr feature/payment-search` is done, and the MR list shows no open MR for that branch.
- [ ] MR2, MR3 and MR4 are open with bot output; `docs/results.md` and screenshots 01–06 are present.
- [ ] Open tabs: GitLab MR list; terminal running `docker compose logs -f --since 1m pr-agent`; `docs/results.md`; `docs/proposal.md`. Notifications off, laptop on power.

## Talk track (15:00)

| Time | On screen | Say / do |
|---|---|---|
| 00:00‐01:30 | `docker-compose.yml`, then the GitLab project | Setup recap: GitLab CE 19.5 and PR-Agent 0.48 (MIT) run in Docker on this laptop. A webhook goes to PR-Agent, PR-Agent calls the model through OpenCode Go (an OpenAI-compatible gateway; switching to another provider is one setting), and it comments back as a Developer bot user. The code is synthetic; nothing from git.santafe.gov.ar is involved. |
| 01:30‐02:30 | Terminal | `./scripts/seed-repo.sh --no-push --open-mrs feature/payment-search`, then open the printed URL. Say: "from now on nobody touches anything." |
| 02:30‐04:30 | MR1 Changes tab, logs terminal | While the bot works, show the diff and invite the audience to spot bugs. Point at the log line `New merge request: …`. Explain the 3 automatic commands (`/describe`, `/review`, `/improve`) and that AGENTS.md on `main` feeds the team's conventions to the model. |
| 04:30‐05:30 | MR1 Overview | `/describe`: the generated description (type, walkthrough, files). Note the time from creation to first comment. |
| 05:30‐07:00 | MR1 "PR Reviewer Guide", then the Changes tab | `/review`: the summary shows effort, security and tests. Key issues are **inline threads** on the exact lines: `PaymentRepository.java:53` (SQLi), `:55-57` (leak), `PaymentService.java:34/36` (pagination). |
| 07:00‐08:00 | MR1 Changes tab | `/improve`: inline **committable** suggestion threads with GitLab's "Apply suggestion" button. Show one, don't apply it. |
| 08:00‐09:30 | MR1 comment box | Model B on the same code: `/review --config.model=openai/deepseek-v4.1-flash --pr_reviewer.persistent_comment=false --pr_reviewer.inline_key_issues=false`. Explain: a cheaper open-weights model, the same family as a self-hosted option, but here served by OpenCode Go's providers. Compare its single comment with Model A's inline threads. |
| 09:30‐11:00 | Terminal, then MR1 | `./scripts/seed-repo.sh --push-fix` (PreparedStatement + try-with-resources). Show the "added 1 commit" note and `/review` re-running (~10 s): the updated Guide lists SQLi and leak under "✅ Resolved findings". Then the `/improve` run resolves the leak threads (line 55). Say: the SQLi thread stays open because it is pinned to the method signature, which the fix did not change; resolution is line-based. The pagination threads stay open, which is correct because those bugs were not fixed. |
| 11:00‐12:00 | MR4 `chore/rename-dto` | A clean refactor: show what the bot said. This is the false-positive check. |
| 12:00‐13:30 | `docs/results.md` | Per-defect table for A and B (the hard ones: D1.3, D1.4, D2.3, D3.2), false positives, latency, cost per MR. |
| 13:30‐15:00 | `docs/proposal.md` §5 and §8 | Data leaves the network today; options. Decision requested: pilot on 2 repos, VM, budget cap, owner, legal/security review. |
| 15:00‐20:00 | — | Q&A. |

**Optional, only if ahead of time** (during the Model B wait). This question is self-contained; `/ask` gets no repo context:

    /ask "searchByPayer's Javadoc says pageNumber is one-based but it is passed straight to new PageRequest(pageNumber, pageSize) whose offset() is used as SQL OFFSET. Assuming offset = page*size, which rows does page 1 return for size 20, and what does totalPages return for 45 matches?"

Expected answer: rows 21–40; 2 pages instead of 3.

## Fallback

If anything live fails or stalls more than 3 minutes (no bot comment, provider error, Model B rejected, GitLab unresponsive): say it was captured in rehearsal, show `docs/screenshots/01–06` in order, and continue the talk track. MR2–MR4 still carry real bot output.
