CREATE TABLE payment (
    id              BIGINT AUTO_INCREMENT PRIMARY KEY,
    payer_id        VARCHAR(64)    NOT NULL,
    amount          DECIMAL(19, 2) NOT NULL,
    currency        CHAR(3)        NOT NULL,
    status          VARCHAR(16)    NOT NULL,
    refunded_amount DECIMAL(19, 2),
    created_at      TIMESTAMP      NOT NULL
);

CREATE INDEX idx_payment_payer ON payment (payer_id);
