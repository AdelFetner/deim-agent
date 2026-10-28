# Guidance for reviewers and coding agents — payments-demo

## Conventions

- Money is always `java.math.BigDecimal` with scale 2, never `double`.
- `PageRequest` is zero-based (`page = 0` is the first page); `PageRequest.offset()` returns `page * size`
  and is used directly as the SQL `OFFSET`.
- All SQL uses `PreparedStatement` inside try-with-resources.
- Credentials come from environment variables (see `DataSourceConfig.requireEnv`); nothing secret is committed.
- `PaymentService` is a singleton shared by all HTTP worker threads; it must be thread-safe.

## Data model facts

- `Payment.refundedAmount` (column `payment.refunded_amount`) is `null` until the first refund.
- Payment status lifecycle: `PENDING -> SETTLED -> REFUNDED`; `FAILED` is terminal.
