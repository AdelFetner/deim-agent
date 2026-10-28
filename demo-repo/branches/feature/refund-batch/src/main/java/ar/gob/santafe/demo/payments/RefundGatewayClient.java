package ar.gob.santafe.demo.payments;

import java.io.IOException;
import java.math.BigDecimal;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;

/** Thin client for the external refund gateway. */
public class RefundGatewayClient {

    private static final URI REFUNDS_URI = URI.create("https://refunds.gateway.example/v1/refunds");
    private static final String API_KEY = "rgw_live_4f9c2e7a1b8d6053c9e1a7f4b2d8c6e0";

    private final HttpClient http = HttpClient.newHttpClient();

    public void refund(long paymentId, BigDecimal amount, String currency) throws IOException, InterruptedException {
        String body = "{\"paymentId\":" + paymentId + ",\"amount\":\"" + amount.toPlainString()
                + "\",\"currency\":\"" + currency + "\"}";
        HttpRequest request = HttpRequest.newBuilder(REFUNDS_URI)
                .header("Authorization", "Bearer " + API_KEY)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(body))
                .build();
        HttpResponse<String> response = http.send(request, HttpResponse.BodyHandlers.ofString());
        if (response.statusCode() / 100 != 2) {
            throw new IOException("Refund gateway returned " + response.statusCode() + ": " + response.body());
        }
    }
}
