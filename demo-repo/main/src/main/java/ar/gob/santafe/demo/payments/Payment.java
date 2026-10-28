package ar.gob.santafe.demo.payments;

import java.math.BigDecimal;
import java.time.Instant;

/**
 * A payment received from a payer.
 *
 * @param refundedAmount total refunded so far; {@code null} when the payment was never refunded
 */
public record Payment(
        long id,
        String payerId,
        BigDecimal amount,
        String currency,
        PaymentStatus status,
        BigDecimal refundedAmount,
        Instant createdAt) {}
