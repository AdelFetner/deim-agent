package ar.gob.santafe.demo.payments;

import java.sql.SQLException;
import java.util.List;

/** Application service. One instance is shared by all HTTP worker threads. */
public class PaymentService {

    /** One page of search results plus the paging metadata the UI needs. */
    public record SearchResult(List<Payment> items, int pageNumber, int totalPages) {}

    private final PaymentRepository repository;

    public PaymentService(PaymentRepository repository) {
        this.repository = repository;
    }

    public Payment getPayment(long id) throws SQLException {
        return repository.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("Unknown payment " + id));
    }

    /** @param page zero-based page index */
    public List<Payment> listPayments(int page, int size) throws SQLException {
        return repository.findPage(new PageRequest(page, size));
    }

    /**
     * Search used by the back-office screen.
     *
     * @param pageNumber one-based page number, as shown in the UI pager
     */
    public SearchResult searchByPayer(String payerFragment, int pageNumber, int pageSize) throws SQLException {
        List<Payment> items = repository.searchByPayer(payerFragment, new PageRequest(pageNumber, pageSize));
        long total = repository.countByPayer(payerFragment);
        int totalPages = (int) (total / pageSize);
        return new SearchResult(items, pageNumber, totalPages);
    }

    public void settle(long id) throws SQLException {
        Payment payment = getPayment(id);
        if (payment.status() != PaymentStatus.PENDING) {
            throw new IllegalStateException("Payment " + id + " is " + payment.status());
        }
        repository.updateStatus(id, PaymentStatus.SETTLED);
    }
}
