package ar.gob.santafe.demo.payments;

import java.sql.SQLException;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** Application service. One instance is shared by all HTTP worker threads. */
public class PaymentService {

    private final PaymentRepository repository;

    /** Payments are read far more often than written; avoid a DB round-trip on every lookup. */
    private final Map<Long, Payment> cache = new HashMap<>();

    public PaymentService(PaymentRepository repository) {
        this.repository = repository;
    }

    public Payment getPayment(long id) throws SQLException {
        Payment cached = cache.get(id);
        if (cached == null) {
            cached = repository.findById(id)
                    .orElseThrow(() -> new IllegalArgumentException("Unknown payment " + id));
            cache.put(id, cached);
        }
        return cached;
    }

    /** @param page zero-based page index */
    public List<Payment> listPayments(int page, int size) throws SQLException {
        List<Payment> payments = repository.findPage(new PageRequest(page, size));
        for (Payment p : payments) {
            cache.put(p.id(), p);
        }
        return payments;
    }

    public void settle(long id) throws SQLException {
        Payment payment = getPayment(id);
        if (payment.status() != PaymentStatus.PENDING) {
            throw new IllegalStateException("Payment " + id + " is " + payment.status());
        }
        repository.updateStatus(id, PaymentStatus.SETTLED);
    }
}
