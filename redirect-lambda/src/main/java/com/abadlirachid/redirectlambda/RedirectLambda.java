
package com.abadlirachid.redirectlambda;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.LambdaLogger;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.*;
import redis.clients.jedis.Jedis;

import java.util.HashMap;
import java.util.Map;

public class RedirectLambda implements RequestHandler<Map<String, Object>, Map<String, Object>> {
    private final DynamoDbClient dynamoDbClient = DynamoDbClient.create();

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        LambdaLogger logger = context.getLogger();

        logger.log("REDIS_HOST ===> " + System.getenv("REDIS_HOST"));
        logger.log("REDIS_PORT ===> " + System.getenv("REDIS_PORT"));
        String redisHost = System.getenv("REDIS_HOST");
        int redisPort = Integer.parseInt(System.getenv("REDIS_PORT"));

        if (System.getenv("REDIS_HOST") == null || System.getenv("REDIS_PORT") == null) {
            logger.log("🔴 Environment variables are missing");
            logger.log("REDIS_HOST: " + System.getenv("REDIS_HOST"));
            logger.log("REDIS_PORT: " + System.getenv("REDIS_PORT"));
            throw new RuntimeException("Missing required env vars");
        }


        Jedis redis = new Jedis(redisHost, redisPort);

        Map<String, Object> response = new HashMap<>();

        try {
            Map<String, String> pathParams = (Map<String, String>) input.get("pathParameters");
            String shortCode = pathParams.get("shorturl");
            logger.log("Received shortCode: " + shortCode);

            String longUrl = redis.get(shortCode);
            if (longUrl != null) {
                logger.log("Found in Redis: " + longUrl);
            } else {
                logger.log("Not found in Redis. Checking DynamoDB...");

                Map<String, AttributeValue> key = new HashMap<>();
                key.put("shortCode", AttributeValue.builder().s(shortCode).build());

                String urlTableName = "UrlTable";
                GetItemRequest request = GetItemRequest.builder()
                        .tableName(urlTableName)
                        .key(key)
                        .build();

                Map<String, AttributeValue> item = dynamoDbClient.getItem(request).item();

                if (item == null || !item.containsKey("longUrl")) {
                    throw new RuntimeException("Short URL not found");
                }

                longUrl = item.get("longUrl").s();
                redis.set(shortCode, longUrl);
                logger.log("Loaded from DB and cached in Redis: " + longUrl);
            }

            response.put("statusCode", 302);
            Map<String, String> headers = new HashMap<>();
            headers.put("Location", longUrl);
            response.put("headers", headers);

        } catch (Exception e) {
            logger.log("Error: " + e.getMessage());
            response.put("statusCode", 404);
            response.put("body", "{\"error\":" + e.getMessage() + "\"}");
        } finally {
            redis.close();
        }

        return response;
    }
}
