package ar.gob.santafe.demo.payments;

import java.io.IOException;
import java.math.BigDecimal;
import java.sql.SQLException;
import java.util.List;

/** Refunds a percentage of a list of payments, e.g. when an event is cancelled. */
public class RefundService {

    private final PaymentRepository repository;
    private final RefundGatewayClient gateway;

    public RefundService(PaymentRepository repository, RefundGatewayClient gateway) {
        this.repository = repository;
        this.gateway = gateway;
    }

    /**
     * @param percentage refund percentage, 0-100
     * @return number of payments refunded
     */
    public int refundBatch(List<Long> paymentIds, int percentage) throws SQLException, IOException, InterruptedException {
        int refunded = 0;
        for (long id : paymentIds) {
            Payment payment = repository.findById(id).orElseThrow();
            if (payment.status() != PaymentStatus.SETTLED) {
                continue;
            }
            double alreadyRefunded = payment.refundedAmount().doubleValue();
            double refundable = payment.amount().doubleValue() - alreadyRefunded;
            double refund = refundable * percentage / 100;
            if (refund <= 0) {
                continue;
            }
            gateway.refund(id, BigDecimal.valueOf(refund), payment.currency());
            BigDecimal newTotal = BigDecimal.valueOf(alreadyRefunded + refund);
            PaymentStatus status = newTotal.compareTo(payment.amount()) == 0 ? PaymentStatus.REFUNDED : PaymentStatus.SETTLED;
            repository.recordRefund(id, newTotal, status);
            refunded++;
        }
        return refunded;
    }
}
