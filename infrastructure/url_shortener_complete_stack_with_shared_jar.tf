
provider "aws" {
  region = "us-west-2"
}

resource "random_id" "bucket_id" {
  byte_length = 4
}

resource "aws_s3_bucket" "artifact_bucket" {
  bucket = "url-shortener-artifacts-${random_id.bucket_id.hex}"
  force_destroy = true
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "url_shortener_lambda_exec_role"
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
  name       = "lambda_logs_attachment"
  roles      = [aws_iam_role.lambda_exec_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_dynamodb_table" "url_counter" {
  name         = "UrlCounter"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_dynamodb_table" "shortened_urls" {
  name         = "ShortenedUrls"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "shortCode"

  attribute {
    name = "shortCode"
    type = "S"
  }
}

resource "aws_lambda_function" "shorten_lambda" {
  filename         = "url-shortener-1.0-SNAPSHOT.jar"
  function_name    = "ShortenUrlLambda"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "com.urlshortener.ShortenLambda::handleRequest"
  runtime          = "java17"
  source_code_hash = filebase64sha256("url-shortener-1.0-SNAPSHOT.jar")
}

resource "aws_lambda_function" "redirect_lambda" {
  filename         = "url-shortener-1.0-SNAPSHOT.jar"
  function_name    = "RedirectUrlLambda"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "com.urlshortener.RedirectLambda::handleRequest"
  runtime          = "java17"
  source_code_hash = filebase64sha256("url-shortener-1.0-SNAPSHOT.jar")
}

resource "aws_apigatewayv2_api" "http_api" {
  name          = "url-shortener-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "shorten_integration" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.shorten_lambda.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "redirect_integration" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.redirect_lambda.invoke_arn
  integration_method     = "POST"  # MUST be POST
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

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "shorten_api_permission" {
  statement_id  = "AllowShortenInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.shorten_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "redirect_api_permission" {
  statement_id  = "AllowRedirectInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.redirect_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}
