package ar.gob.santafe.demo.payments;

/**
 * Page request with a zero-based index: {@code pageIndex = 0} is the first page.
 */
public record PageRequest(int pageIndex, int size) {

    public static final int MAX_SIZE = 100;

    public PageRequest {
        if (pageIndex < 0) {
            throw new IllegalArgumentException("page must be >= 0");
        }
        if (size < 1 || size > MAX_SIZE) {
            throw new IllegalArgumentException("size must be between 1 and " + MAX_SIZE);
        }
    }

    public long offset() {
        return (long) pageIndex * size;
    }
}
