
# This Terraform configuration sets up:
# - Two Lambda functions (Shorten and Redirect)
# - IAM roles with permissions
# - DynamoDB table for URL storage and counter
# - API Gateway (HTTP API) with two routes

provider "aws" {
  region = "us-west-2"
}

# --- IAM Role for Lambdas ---
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy_attachment" "lambda_logs" {
  name       = "attach_lambda_logs"
  roles      = [aws_iam_role.lambda_exec_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy_attachment" "dynamo_access" {
  name       = "attach_dynamo_access"
  roles      = [aws_iam_role.lambda_exec_role.name]
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

# --- DynamoDB Tables ---
resource "aws_dynamodb_table" "url_mapping" {
  name           = "UrlMapping"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "shortCode"

  attribute {
    name = "shortCode"
    type = "S"
  }
}

resource "aws_dynamodb_table" "url_counter" {
  name           = "UrlCounter"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "counterId"

  attribute {
    name = "counterId"
    type = "S"
  }
}

# --- Lambda Functions ---
resource "aws_lambda_function" "shorten" {
  function_name = "ShortenUrlLambda"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "com.urlshortener.ShortenLambda::handleRequest"
  runtime       = "java17"
  filename      = "build/shorten-lambda.jar"
  timeout       = 10
  memory_size   = 512
}

resource "aws_lambda_function" "redirect" {
  function_name = "RedirectUrlLambda"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "com.urlshortener.RedirectLambda::handleRequest"
  runtime       = "java17"
  filename      = "build/redirect-lambda.jar"
  timeout       = 10
  memory_size   = 512
}

# --- API Gateway ---
resource "aws_apigatewayv2_api" "http_api" {
  name          = "UrlShortenerAPI"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "shorten_integration" {
  api_id             = aws_apigatewayv2_api.http_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.shorten.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "redirect_integration" {
  api_id             = aws_apigatewayv2_api.http_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.redirect.invoke_arn
  integration_method = "GET"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "shorten_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /shorten"
  target    = "integrations/${aws_apigatewayv2_integration.shorten_integration.id}"
}

resource "aws_apigatewayv2_route" "redirect_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /{shortCode}"
  target    = "integrations/${aws_apigatewayv2_integration.redirect_integration.id}"
}

resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "prod"
  auto_deploy = true
}

# --- Lambda Permissions for API Gateway ---
resource "aws_lambda_permission" "allow_apigw_shorten" {
  statement_id  = "AllowExecutionFromAPIGatewayShorten"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.shorten.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "allow_apigw_redirect" {
  statement_id  = "AllowExecutionFromAPIGatewayRedirect"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.redirect.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}
