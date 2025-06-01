package com.abadlirachid;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.*;

import java.util.Map;
import java.util.HashMap;

public class RedirectLambda implements RequestHandler<Map<String, Object>, Map<String, Object>> {

    private final DynamoDbClient dynamoDb = DynamoDbClient.create();

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        Map<String, Object> response = new HashMap<>();

        try {
            Map<String, String> pathParams = (Map<String, String>) input.get("pathParameters");
            if (pathParams == null || !pathParams.containsKey("shortCode")) {
                response.put("statusCode", 400);
                response.put("body", "Missing shortCode");
                return response;
            }

            String shortCode = pathParams.get("shortCode");

            GetItemRequest request = GetItemRequest.builder()
                    .tableName("ShortUrls")
                    .key(Map.of("shortCode", AttributeValue.fromS(shortCode)))
                    .build();

            Map<String, AttributeValue> item = dynamoDb.getItem(request).item();

            if (item == null || !item.containsKey("longUrl")) {
                response.put("statusCode", 404);
                response.put("body", "Short URL not found");
                return response;
            }

            String longUrl = item.get("longUrl").s();

            response.put("statusCode", 301);
            Map<String, String> headers = new HashMap<>();
            headers.put("Location", longUrl);
            response.put("headers", headers);
            return response;

        } catch (Exception e) {
            response.put("statusCode", 500);
            response.put("body", "Internal error: " + e.getMessage());
            return response;
        }
    }
}
