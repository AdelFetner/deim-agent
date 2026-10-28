package ar.gob.santafe.demo.payments;

import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import javax.sql.DataSource;

public class PaymentRepository {

    private final DataSource dataSource;

    public PaymentRepository(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    public Optional<Payment> findById(long id) throws SQLException {
        String sql = "SELECT id, payer_id, amount, currency, status, refunded_amount, created_at"
                + " FROM payment WHERE id = ?";
        try (Connection conn = dataSource.getConnection();
                PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setLong(1, id);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() ? Optional.of(mapRow(rs)) : Optional.empty();
            }
        }
    }

    public List<Payment> findPage(PageRequest page) throws SQLException {
        String sql = "SELECT id, payer_id, amount, currency, status, refunded_amount, created_at"
                + " FROM payment ORDER BY id LIMIT ? OFFSET ?";
        try (Connection conn = dataSource.getConnection();
                PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, page.size());
            ps.setLong(2, page.offset());
            try (ResultSet rs = ps.executeQuery()) {
                List<Payment> result = new ArrayList<>();
                while (rs.next()) {
                    result.add(mapRow(rs));
                }
                return result;
            }
        }
    }

    public long count() throws SQLException {
        try (Connection conn = dataSource.getConnection();
                PreparedStatement ps = conn.prepareStatement("SELECT COUNT(*) FROM payment");
                ResultSet rs = ps.executeQuery()) {
            rs.next();
            return rs.getLong(1);
        }
    }

    public void updateStatus(long id, PaymentStatus status) throws SQLException {
        try (Connection conn = dataSource.getConnection();
                PreparedStatement ps = conn.prepareStatement("UPDATE payment SET status = ? WHERE id = ?")) {
            ps.setString(1, status.name());
            ps.setLong(2, id);
            ps.executeUpdate();
        }
    }

    public void recordRefund(long id, BigDecimal refundedTotal, PaymentStatus status) throws SQLException {
        try (Connection conn = dataSource.getConnection();
                PreparedStatement ps = conn.prepareStatement(
                        "UPDATE payment SET refunded_amount = ?, status = ? WHERE id = ?")) {
            ps.setBigDecimal(1, refundedTotal);
            ps.setString(2, status.name());
            ps.setLong(3, id);
            ps.executeUpdate();
        }
    }

    private static Payment mapRow(ResultSet rs) throws SQLException {
        return new Payment(
                rs.getLong("id"),
                rs.getString("payer_id"),
                rs.getBigDecimal("amount"),
                rs.getString("currency"),
                PaymentStatus.valueOf(rs.getString("status")),
                rs.getBigDecimal("refunded_amount"),
                rs.getTimestamp("created_at").toInstant());
    }
}
