# Results capture sheet

PR-Agent `0.48.0-gitlab_webhook`; GitLab CE `19.5.1-ce.0`. Date: 2026-10-26 (rehearsal 13:58–14:14 UTC) Operator: automated run (Claude Code) on the demo laptop

- Model A = `openai/glm-5.3` (GLM-5.3 via OpenCode Go)
- Model B = `openai/deepseek-v4.1-flash` (DeepSeek V4.1 Flash via OpenCode Go)

Fixed settings:
- `num_max_findings=6`
- `inline_key_issues=true`
- `committable_code_suggestions=true`
- `output_run_details=true`
- `output_run_cost=true`
- `add_user_to_requests=true`
- `log_level=INFO`
- `auto_resolve_fixed_inline_threads=true`
- `handle_push_trigger=true`
- `push_commands=["/review","/improve"]` (changed from `["/review"]` during the rehearsal, see Notes)
- `ai_timeout=600`, `reasoning_effort=medium`, `additional_reasoning_effort_models=["glm-5.3"]` (added during the smoke test, see Notes)
- `fallback_models=[]`

Answer key: `docs/answer-key.md`.

## Runs

- **A (auto run):** what the bot posts when the MR is opened: `/describe`, `/review` (Guide plus inline key-issue threads), `/improve` (inline committable threads).
- **B (review only):** comment `/review --config.model=openai/deepseek-v4.1-flash --pr_reviewer.persistent_comment=false --pr_reviewer.inline_key_issues=false` on the same MR, before any fix is pushed.
- **A (comparable review):** to compare `/review` latency on equal terms, comment `/review --pr_reviewer.persistent_comment=false --pr_reviewer.inline_key_issues=false` once per MR. Its findings are not scored.

## Summary (one row per MR × model)

| MR | Model | Seeded | Found by /review | Found by /review or /improve | Valid extras | False positives | L_open (s) | L_review (s) | Tokens in / out (/review) | Cost /review USD | Cost auto run USD |
|---|---|---|---|---|---|---|---|---|---|---|---|
| MR1 payment-search | A | 4 | 4 | 4 | 0 | 0 | 55.8 | 15.7 | 3,000 / 839 | 0.0079 | 0.0139 + /improve† |
| MR1 payment-search | B | 4 | 4 | n/a | 0 | 0 | n/a | 20.6 | 3,161 / 1,723 | 0.0015 | n/a |
| MR2 refund-batch | A | 3 | 3 | 3 | 1 | 0 | 55.5 | 15.3 | 3,274 / 975 | 0.0089 | 0.0151 + /improve† |
| MR2 refund-batch | B | 3 | 3 | n/a | 2 | 0 | n/a | 41.0 | 3,459 / 6,209 | 0.0042 | n/a |
| MR3 payment-cache | A | 2 | 2 | 2 | 1 | 0 | 40.5 | 11.2 | 2,535 / 609 | 0.0062 | 0.0104 + /improve† |
| MR3 payment-cache | B | 2 | 2 | n/a | 1 | 0 | n/a | 28.9 | 2,634 / 4,155 | 0.0029 | n/a |
| MR4 rename-dto (clean) | A | 0 | n/a | n/a | 0 | 0 | 20.2 | 4.7 | 2,438 / 83 | 0.0038 | 0.0071 + /improve† |
| MR4 rename-dto (clean) | B | 0 | n/a | n/a | 0 | 0 | n/a | 10.7 | 2,526 / 1,200 | 0.0011 | n/a |
| **Total / median** | A | 9 | 9 | 9 | 2 | 0 | 48.0 | 13.3 | | 0.0067 | 0.0116 + /improve† |
| **Total / median** | B | 9 | 9 | n/a | 3 | 0 | n/a | 24.8 | | 0.0024 | n/a |

† `/improve` posts no run-details footer, so its tokens were not metered; "Cost auto run" covers `/describe` + `/review` only. DeepSeek priced at off-peak rates (runs at 14:06–14:10 UTC, Monday).

## Per-defect results (Y / N, plus where the bot said it)

| Defect | Hard? | A /review | A /improve | B /review |
|---|---|---|---|---|
| D1.1 SQL injection `PaymentRepository.java:53` | | Y (inline :51 "SQL Injection" + Guide security section) | Y (:50) | Y (security section + focus area) |
| D1.2 Leak `PaymentRepository.java:55-57` | | Y (inline :55 "Resource Leak") | Y (:55) | Y (focus area "Resource Leak") |
| D1.3 1-based → 0-based page `PaymentService.java:34` | yes | Y (inline :33 "Off-by-one Pagination") | Y (:33) | Y (focus area "Off-by-one Pagination") |
| D1.4 totalPages floor `PaymentService.java:36` | yes | Y (inline :36 "Wrong totalPages") | N (no suggestion in the auto run) | Y (focus area "Wrong Total Pages") |
| D2.1 Hard-coded key `RefundGatewayClient.java:14` | | Y (inline :14 "Hardcoded Secret" + Guide security section) | Y (:13) | Y (security section + focus area) |
| D2.2 Money as double `RefundService.java:30-38` | | Y (inline :30 "Floating-Point Money") | Y (:30, same suggestion as D2.3) | Y (focus area "Floating-point money") |
| D2.3 Null refundedAmount `RefundService.java:30` | yes | Y (inline :30 "Possible Issue", NPE) | Y (:30) | Y (focus area "Possible NPE") |
| D3.1 Shared HashMap race `PaymentService.java:14` | | Y (inline :14 "Thread Safety") | Y (:13) | Y (focus area "Thread Safety") |
| D3.2 Stale cache after settle `PaymentService.java:44` | yes | Y* (inline :21 "Stale Cache") | Y (:39) | Y (focus area "Stale Cache") |
| **Hard defects found (of 4)** | | 4 | 3 | 4 |

\* Anchored on `getPayment` (line 21, the stale read), not on `settle` (line 44). The root cause matches the answer key: the bot wrote "`settle` ... mutate[s] payment state in the DB, but `getPayment` will keep returning the previously cached `Payment` ... A payment settled after being cached will still be reported as `PENDING`". It is counted as found. Under a strict ±5-line reading it would be N, which makes A /review 8/9 and 3/4 hard.

After `--push-fix` on MR1 (Model A, push-triggered `/review`):
- D1.1/D1.2 still reported? No. Both moved to "✅ Resolved findings" in the updated Guide (review state `RESOLVED`); 10 s from push to updated review.
- D1.1/D1.2 threads auto-resolved? Partly. With `push_commands=["/review"]` none were resolved, because v0.48.0 runs the sweep only inside `/improve`. After adding `/improve` and running it, the D1.2 threads (key issue + suggestion, line 55) were resolved. The D1.1 threads stayed open because they are anchored on lines 50–51 (Javadoc and method signature), which the fix did not change; resolution is line-based.
- D1.3/D1.4 still reported? Yes. Both stayed `ACTIVE` with open threads, and the re-run `/improve` added suggestions for both.

## Definitions

**Found.**
- A seeded defect is found when the stated bot output (for /review: the Guide comment or its inline threads; for /improve: its inline suggestion threads; /describe never counts) names the defect's root cause in the right file and in the same method, or within ±5 lines.
- The root cause is the reviewer statement in `docs/answer-key.md`. Right place with the wrong reason = not found.
- Scoring is binary, and each defect counts once per run.
- For D2.2 vs D2.3, apply the line-30 rule in the answer key.

**Valid extras.** Distinct correct findings that are not seeded. The answer key's "Acceptable extras" are pre-approved; anything else needs a one-line justification in Notes.

**False positive.** A distinct finding that asserts a bug, vulnerability or behaviour change that is not real in the diff, or that proposes a change which would introduce a bug. Duplicates count once. On MR4, apply the MR4 rule in the answer key.

**Latency.** Seconds, from GitLab timestamps.
- `L_open` (A only) = T1 − MR `created_at`.
- `L_review` = T1 − `created_at` of the triggering `/review` note.
- T1 = the latest `updated_at` among notes authored by `pr-agent-bot` for that run. Use `updated_at` because PR-Agent edits its progress and persistent comments. For the auto run, also include the MR `updated_at` if `/describe` rewrote the description last.

    export ROOT_TOKEN=$(cat ~/pr-agent-demo/.state/root-pat)
    IID=1   # MR number
    curl -s -H "PRIVATE-TOKEN: $ROOT_TOKEN" \
      "http://localhost:8929/api/v4/projects/root%2Fpayments-demo/merge_requests/$IID/notes?per_page=100&sort=asc&order_by=created_at" \
    | python3 -c 'import json,sys; [print(n["author"]["username"], n["system"], n["created_at"], n["updated_at"], n["body"][:70].replace("\n"," ")) for n in json.load(sys.stdin)]'
    curl -s -H "PRIVATE-TOKEN: $ROOT_TOKEN" \
      "http://localhost:8929/api/v4/projects/root%2Fpayments-demo/merge_requests/$IID" \
    | python3 -c 'import json,sys; m=json.load(sys.stdin); print("mr created", m["created_at"], "updated", m["updated_at"])'

**Tokens and cost.** All model calls go through OpenCode Go with the demo's API key.
- **Tokens:** the "⚙️ Agent run details" footer on the Guide and description comments (tokens in/out, time, AI calls). The inline /improve threads carry no footer; take /improve tokens from the OpenCode console usage view (https://opencode.ai/console) for the same time window.
  - **Tokens in / out (/review):** the footer of that run's review comment.
- **Cost** = tokens × Go list price (USD per 1M tokens, https://opencode.ai/docs/go):
  - GLM-5.3 (A): input 1.40, output 4.40.
  - DeepSeek V4.1 Flash (B): off-peak input 0.15, output 0.60; peak (01:00–04:00 and 06:00–10:00 UTC, Mon–Fri) input 0.30, output 1.20.
  - **Cost /review:** that run's review tokens × price. **Cost auto run (A):** describe + review + improve tokens × price.
  - Go is a flat subscription (USD 10/month); these list-price costs are the pay-as-you-go equivalent and what a direct API contract would cost, not the demo's out-of-pocket spend.
- **Session check:** OpenCode console Go usage before and after the session; the delta should match the sum of computed costs within rounding. Record both values below.
- The footer's own cost line may read "unavailable" (new model IDs, local cost map); ignore it.

Session: console usage before n/a, after n/a, delta n/a (the OpenCode console needs the account owner's login; check https://opencode.ai/console for 2026-10-26 13:58–14:14 UTC). Computed sum of metered rehearsal calls (4 × describe, 4 × A review, 4 × A comparable review, 4 × B review): USD 0.083 at list prices. Out-of-pocket: covered by the USD 10/month Go subscription.

## Notes / anomalies

1. **Provider and Model A changed from the plan.** The supplied key is OpenCode Go, not OpenRouter. PR-Agent uses Go's OpenAI-compatible endpoint (`OPENAI__API_BASE`). Claude Sonnet is not in Go, so Model A is GLM-5.3. Go is meant for coding-agent traffic, so requests carry `User-Agent: pr-agent-demo/0.48.0` and `x-opencode-session`.
2. **GLM-5.3 needs an explicit reasoning effort.** PR-Agent sends `reasoning_effort` only for models litellm recognises. Without it, GLM-5.3 reasoned for minutes: the smoke-test `/review` took 90 s with 6.6k output tokens, and `/improve` timed out after 362 s. A direct benchmark on the MR1 diff hit the 8k output cap with no answer for every Go model tried when no effort was set. Fixed with `additional_reasoning_effort_models=["glm-5.3"]` (effort `medium`) and `ai_timeout=600`. All scored runs used the fixed configuration; earlier smoke-test timings are excluded.
3. **Webhook URL.** `http://localhost:3333/webhook` failed ("internal error", `ECONNREFUSED ::1:3333`) because `localhost` resolves to IPv6 inside GitLab and PR-Agent listens on IPv4 only. Fixed with `http://127.0.0.1:3333/webhook`.
4. **Auto-resolve.** In v0.48.0 the fixed-thread sweep runs only inside `/improve`, so the planned `push_commands=["/review"]` never resolves threads. `/improve` was added to `push_commands`. The config changed after the fix was pushed, so the sweep on MR1 was run with a manual `/improve` comment, which is the same code path. On the demo, a push now runs `/review` and `/improve`.
5. **Resolution is line-based.** The D1.1 thread is anchored on the method signature (line 51), which the fix did not change, so it stays open even though the re-review marks the finding resolved. Say this in the demo: "resolved in the review, the thread stays open because its line did not change".
6. **Persistent comment target.** The push re-review updated the most recent review comment (the A comparable run) rather than the original auto-run Guide. This is cosmetic.
7. **Both models found 9/9 with 0 false positives.** The synthetic set does not discriminate between models; the differences seen are latency (A median 13.3 s vs B 24.8 s per review, B up to 6.2k output tokens on MR2), cost (B ≈ 0.36 × A per review) and valid extras (B 3, A 2).
8. **Cost metering.** The footer reports "unavailable"; costs are footer tokens × Go list price. `/improve` has no footer and was not metered. Whether the footer's "out" count includes reasoning tokens is unverified, so treat costs as a floor.
9. **Memory.** Docker Desktop VM lowered to 7 GiB (a 10 GiB VM got Docker OOM-killed by the host during the first image pull, which also left a corrupted GitLab image that had to be re-pulled). Sampled right after the runs: GitLab 3.23 GiB of its 5 GiB cap, PR-Agent 378 MiB (not a true peak during a review). The host was down to 0.8 GB available with swap full, so the stack was stopped immediately afterwards.
10. **Boot times.** GitLab first boot to ready in 136 s; full bootstrap in 175 s.
