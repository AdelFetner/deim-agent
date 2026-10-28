# payments-demo

Synthetic payments back-office service used to demo automated merge-request review.
Not production code.

## Conventions

- Money is always `java.math.BigDecimal` with scale 2, never `double`.
- `PageRequest` is zero-based (`page = 0` is the first page).
- All SQL uses `PreparedStatement` inside try-with-resources.
- Credentials come from environment variables (see `DataSourceConfig`); nothing secret is committed.
- `PaymentService` is a singleton shared by all HTTP worker threads; it must be thread-safe.

## Build

    mvn -q package
