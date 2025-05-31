package com.urlshortener;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import software.amazon.awssdk.services.dynamodb.*;
import software.amazon.awssdk.services.dynamodb.model.*;

import java.util.*;

public class ShortenLambda implements RequestHandler<Map<String, Object>, Map<String, Object>> {

    private static final String COUNTER_TABLE = "UrlCounter";
    private static final String URL_TABLE = "ShortUrls";
    private static final String COUNTER_KEY = "global";
    private static final String BASE62 = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
    private final DynamoDbClient ddb = DynamoDbClient.create();

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        String longUrl = (String) input.get("longUrl");
        if (longUrl == null || longUrl.isEmpty()) {
            return Map.of("statusCode", 400, "body", "Missing 'longUrl'");
        }

        long id = incrementCounter();
        String shortCode = base62Encode(id);

        ddb.putItem(PutItemRequest.builder()
                .tableName(URL_TABLE)
                .item(Map.of(
                        "shortCode", AttributeValue.fromS(shortCode),
                        "longUrl", AttributeValue.fromS(longUrl),
                        "createdAt", AttributeValue.fromS(new Date().toString())
                ))
                .build());

        return Map.of("statusCode", 200, "body", "https://sho.rt/" + shortCode);
    }

    private long incrementCounter() {
        return Long.parseLong(ddb.updateItem(UpdateItemRequest.builder()
                .tableName(COUNTER_TABLE)
                .key(Map.of("counterId", AttributeValue.fromS(COUNTER_KEY)))
                .updateExpression("SET #cnt = if_not_exists(#cnt, :start) + :inc")
                .expressionAttributeNames(Map.of(
                    "#cnt", "count"
                ))
                .expressionAttributeValues(Map.of(
                        ":start", AttributeValue.fromN("0"),
                        ":inc", AttributeValue.fromN("1")
                ))
                .returnValues(ReturnValue.UPDATED_NEW)
                .build())
                .attributes()
                .get("count")
                .n());
    }

    private String base62Encode(long number) {
        if (number == 0) return "0";
        StringBuilder sb = new StringBuilder();
        while (number > 0) {
            sb.append(BASE62.charAt((int) (number % 62)));
            number /= 62;
        }
        return sb.reverse().toString();
    }
}
