package ar.gob.santafe.demo.payments;

import javax.sql.DataSource;
import org.h2.jdbcx.JdbcDataSource;

/** Builds the DataSource from environment variables; no credentials live in the code. */
public final class DataSourceConfig {

    private DataSourceConfig() {}

    public static DataSource fromEnvironment() {
        JdbcDataSource ds = new JdbcDataSource();
        ds.setURL(requireEnv("PAYMENTS_DB_URL"));
        ds.setUser(requireEnv("PAYMENTS_DB_USER"));
        ds.setPassword(requireEnv("PAYMENTS_DB_PASSWORD"));
        return ds;
    }

    static String requireEnv(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException("Missing environment variable " + name);
        }
        return value;
    }
}
