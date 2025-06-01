provider "aws" {
  region = "us-west-2"
}

resource "aws_s3_bucket" "lambda_artifacts" {
  bucket = "url-shortener-lambda-artifacts-${random_id.bucket_suffix.hex}"
  force_destroy = true
}

resource "null_resource" "build_and_upload_jars" {
  provisioner "local-exec" {
    command = <<EOT
      echo "🛠️ Building shorten-lambda..."
      cd ../shorten-lambda && mvn clean package

      echo "🛠️ Building redirect-lambda..."
      cd ../redirect-lambda && mvn clean package

      echo "☁️ Uploading to S3..."
      aws s3 cp ../shorten-lambda/target/shorten-lambda-1.0-SNAPSHOT.jar s3://${aws_s3_bucket.lambda_artifacts.bucket}/shorten-lambda.jar
      aws s3 cp ../redirect-lambda/target/redirect-lambda-1.0-SNAPSHOT.jar s3://${aws_s3_bucket.lambda_artifacts.bucket}/redirect-lambda.jar
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [aws_s3_bucket.lambda_artifacts]
}


resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_dynamodb_table" "url_table" {
  name         = "UrlTable"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "shortUrl"

  attribute {
    name = "shortUrl"
    type = "S"
  }
}

resource "aws_dynamodb_table" "counter_table" {
  name         = "CounterTable"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/url-shortener"
  retention_in_days = 14
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Principal = {
        Service = "lambda.amazonaws.com"
      },
      Effect = "Allow",
      Sid    = ""
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "shorten_url_lambda" {
  function_name = "ShortenUrlLambda"
  s3_bucket     = aws_s3_bucket.lambda_artifacts.bucket
  s3_key        = "shorten-lambda-1.0-SNAPSHOT.jar"
  handler       = "com.abadlirachid.ShortenLambda::handleRequest"
  runtime       = "java17"
  role          = aws_iam_role.lambda_exec_role.arn
  memory_size   = 512
  timeout       = 10
}

resource "aws_lambda_function" "redirect_url_lambda" {
  function_name = "RedirectUrlLambda"
  s3_bucket     = aws_s3_bucket.lambda_artifacts.bucket
  s3_key        = "redirect-lambda-1.0-SNAPSHOT.jar"
  handler       = "com.abadlirachid.RedirectLambda::handleRequest"
  runtime       = "java17"
  role          = aws_iam_role.lambda_exec_role.arn
  memory_size   = 512
  timeout       = 10
}

resource "aws_apigatewayv2_api" "url_shortener_api" {
  name          = "UrlShortenerAPI"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "shorten_integration" {
  api_id             = aws_apigatewayv2_api.url_shortener_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.shorten_url_lambda.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "redirect_integration" {
  api_id             = aws_apigatewayv2_api.url_shortener_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.redirect_url_lambda.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "shorten_route" {
  api_id    = aws_apigatewayv2_api.url_shortener_api.id
  route_key = "POST /shortenurl"
  target    = "integrations/${aws_apigatewayv2_integration.shorten_integration.id}"
}

resource "aws_apigatewayv2_route" "redirect_route" {
  api_id    = aws_apigatewayv2_api.url_shortener_api.id
  route_key = "GET /{shorturl}"
  target    = "integrations/${aws_apigatewayv2_integration.redirect_integration.id}"
}

resource "aws_apigatewayv2_stage" "api_stage" {
  api_id      = aws_apigatewayv2_api.url_shortener_api.id
  name        = "prod"
  auto_deploy = true
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "main" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"
}

resource "aws_elasticache_subnet_group" "cache_subnet_group" {
  name       = "url-shortener-subnet-group"
  subnet_ids = [aws_subnet.main.id]
}

resource "aws_elasticache_cluster" "cache" {
  cluster_id           = "url-shortener-cache"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  subnet_group_name    = aws_elasticache_subnet_group.cache_subnet_group.name
}