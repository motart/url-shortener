
package com.abadlirachid.shortenlambda;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.LambdaLogger;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.DynamoDbException;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

public class ShortenLambda implements RequestHandler<Map<String, Object>, Map<String, Object>> {

    Region region = Region.US_WEST_2;
    DynamoDbClient ddb = DynamoDbClient.builder()
            .region(region)
            .build();

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        LambdaLogger logger = context.getLogger();
        String longUrl = (String) ((Map<String, Object>) input.get("body")).get("longUrl");
        logger.log("Received URL: " + longUrl);

        String shortCode = UUID.randomUUID().toString().substring(0, 8);
        Map<String, Object> response = new HashMap<>();
        Map<String, AttributeValue> item = new HashMap<>();
        item.put("shortCode", AttributeValue.builder().s(shortCode).build());
        item.put("longUrl", AttributeValue.builder().s(longUrl).build());

        String urlTableName = "UrlTable";
        PutItemRequest request = PutItemRequest.builder()
                .tableName(urlTableName)
                .item(item)
                .build();

        try {
            ddb.putItem(request);

        } catch (DynamoDbException e) {
            response.put("ExceptionType", "DynamoDbException");
            response.put("statusCode", 500);
            response.put("body", "{\"error\":" +  e.getMessage());
        } catch (Exception e) {
            response.put("statusCode", 500);
            response.put("body", "{\"error\":" +  e.getMessage());
        }
        return response;
    }
}
