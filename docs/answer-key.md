# Answer key — payments-demo seeded defects

Line numbers refer to the branch files as seeded (line 1 = `package …`).

Scoring rules live in `docs/results.md`. "Acceptable extras" are valid findings outside the seeded set; they count as neither found nor false positive.

Discriminating defects: D1.3, D1.4, D2.3, D3.2. These need reasoning beyond pattern matching, so report them separately.

## MR1 — `feature/payment-search`

| ID | File:line | Category | What a reviewer should say |
|---|---|---|---|
| D1.1 | `PaymentRepository.java:53` (built at 52-54, run at 57) | security | SQL injection: `payerFragment` is concatenated into the SQL, so input like `x' OR '1'='1` changes the query. Use a `PreparedStatement` with `LIKE ?` and bind `"%" + fragment + "%"`, as `countByPayer` already does. |
| D1.2 | `PaymentRepository.java:55-57` | resource | `Connection`, `Statement` and `ResultSet` are never closed. Every search leaks a pooled connection, and the pool runs out under load. Use try-with-resources like the other methods. |
| D1.3 | `PaymentService.java:34` (contract stated at 31) | correctness | Off-by-one: a 1-based `pageNumber` is passed to the 0-based `PageRequest` (`offset = page*size`). Page 1 returns rows 21-40 for size 20, the first page is unreachable, and the last page returns empty. Use `new PageRequest(pageNumber - 1, pageSize)` and reject `pageNumber < 1`. |
| D1.4 | `PaymentService.java:36` | correctness | `total / pageSize` floors, so a final partial page is not counted (45 rows at size 20 gives 2 pages, should be 3). Use `(int) ((total + pageSize - 1) / pageSize)`. |

Acceptable extras:
- A null `payerFragment` causes an NPE.
- LIKE wildcards `%`/`_` in user input are not escaped.
- `LOWER(payer_id)` prevents use of `idx_payment_payer`.
- No tests.
- The page and count queries are not consistent with each other.

After `--push-fix` (D1.1 and D1.2 fixed):
- The re-review should no longer report D1.1 or D1.2.
- The D1.1/D1.2 inline threads should be auto-resolved.
- D1.3 and D1.4 should still be reported, and their threads should stay open.

## MR2 — `feature/refund-batch`

| ID | File:line | Category | What a reviewer should say |
|---|---|---|---|
| D2.1 | `RefundGatewayClient.java:14` | security | A live gateway API key is hard-coded and committed. It is now in every clone and backup. Rotate it, and load it from the environment or a secret store, e.g. `DataSourceConfig.requireEnv("REFUND_GATEWAY_API_KEY")`. |
| D2.2 | `RefundService.java:30-32, 36-38` | correctness | Money is computed in `double`. Doubles cannot represent most decimal amounts exactly (e.g. `0.1 + 0.2 == 0.30000000000000004`). So `BigDecimal.valueOf(refund)` (36) can send more than 2 decimals to the gateway, and the `compareTo(...) == 0` at 38 can miss a full refund. Use `BigDecimal` end to end with `setScale(2, RoundingMode.HALF_EVEN)`. |
| D2.3 | `RefundService.java:30` | correctness | `refundedAmount` is `null` until the first refund (see `Payment` Javadoc, the nullable column and AGENTS.md). `.doubleValue()` throws an NPE on the first refund of every payment, so the feature fails in its main case. Default it with `Objects.requireNonNullElse(payment.refundedAmount(), BigDecimal.ZERO)`. |

D2.2 and D2.3 both touch line 30:
- D2.3 counts only if the bot says null/NPE on `refundedAmount`.
- D2.2 counts only if the bot says floating point/`double` for money.

Acceptable extras:
- The gateway call and the DB update are not atomic, and there is no idempotency key, so a retry can double-refund.
- `orElseThrow()` aborts the whole batch midway.
- `percentage` is not validated.
- No HTTP timeout.
- JSON is built by hand.
- The gateway error body is echoed into the exception.
- No tests.

## MR3 — `feature/payment-cache`

| ID | File:line | Category | What a reviewer should say |
|---|---|---|---|
| D3.1 | `PaymentService.java:14` (used at 21-25, 34) | concurrency | A shared, unsynchronized `HashMap` is mutated from many HTTP threads, and the class is a singleton. Concurrent `put`s can corrupt the map or lose entries, and `get`/`put` at 21-25 is a check-then-act race. Use `ConcurrentHashMap` (`computeIfAbsent`) or a real cache such as Caffeine. |
| D3.2 | `PaymentService.java:44` (stale read at 40-41) | correctness | Stale cache: `settle` updates the DB but never evicts or updates the cached entry. `getPayment` keeps returning `PENDING`, and a second `settle(id)` passes the guard at 41 and settles again. The "no behaviour change" claim is wrong. Evict or replace the entry after the update, or do not cache mutable state. |

Acceptable extras:
- The cache is unbounded, with no eviction or TTL.
- Each instance in a multi-instance deployment has its own incoherent cache.
- Writes from other processes are invisible.
- The `settle` check-then-act race already exists in `main`.
- No tests.

## MR4 — `chore/rename-dto` (clean)

There are no seeded defects.

**False positive** = any claim of a defect or changed behaviour *inside this repository*. Examples:
- "Breaks callers of `page()`": there are none in the repo.
- "Changes the error message": it is unchanged.
- "Offset overflow": the cast to `long` is unchanged.
- "Validation logic changed".

**Not a false positive (record as acceptable extra):** remarks about unseen external consumers of the public accessor `page()` or of serialized property names, suggestions to rename the `listPayments(int page, …)` parameter too, "add a unit test", and README.md / AGENTS.md still saying `page` after the rename (stale documentation).
