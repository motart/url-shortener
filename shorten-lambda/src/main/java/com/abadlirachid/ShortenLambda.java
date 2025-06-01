
package com.abadlirachid.shortenlambda;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.LambdaLogger;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.*;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

public class ShortenLambda implements RequestHandler<Map<String, Object>, Map<String, Object>> {

    private final DynamoDbClient dynamoDbClient = DynamoDbClient.create();
    private final String urlTableName = System.getenv("URL_TABLE");

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        LambdaLogger logger = context.getLogger();
        Map<String, Object> response = new HashMap<>();

        try {
            String longUrl = (String) ((Map<String, Object>) input.get("body-json")).get("longUrl");
            logger.log("Received URL: " + longUrl);

            String shortCode = UUID.randomUUID().toString().substring(0, 8);

            Map<String, AttributeValue> item = new HashMap<>();
            item.put("shortCode", AttributeValue.builder().s(shortCode).build());
            item.put("longUrl", AttributeValue.builder().s(longUrl).build());

            PutItemRequest request = PutItemRequest.builder()
                    .tableName(urlTableName)
                    .item(item)
                    .build();

            dynamoDbClient.putItem(request);
            logger.log("Inserted into DynamoDB: " + item);

            response.put("statusCode", 200);
            response.put("body", "{\"shortUrl\": " + shortCode + "}");

        } catch (Exception e) {
            logger.log("Error: " + e.getMessage());
            response.put("statusCode", 500);
            response.put("body", "{\"error\": \"Failed to shorten URL\"}");
        }

        return response;
    }
}
