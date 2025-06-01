
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    random = {
      source = "hashicorp/random"
    }
  }

  required_version = ">= 1.0"
}

provider "aws" {
  region = "us-west-2"
}

# Random suffix for unique bucket name
resource "random_id" "suffix" {
  byte_length = 4
}

/*
0- Roles
1- S3 bucket
2- Build and upload the null_resource
3- Lambda functions
4- API Gateway
5- DynamoDB
6- Redis
*/

# Roles and policies
# IAM Role for Lambda
resource "aws_iam_role" "lambda_exec_role" {
  name = "url_shortener_lambda_role"

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

# Policy
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# S3 bucket for Lambda artifacts
resource "aws_s3_bucket" "lambda_artifacts" {
  bucket        = "url-shortener-lambda-artifacts-${random_id.suffix.hex}"
  force_destroy = true
}



resource "null_resource" "build_and_upload" {
  provisioner "local-exec" {
    command = <<EOT
      set -e
      cd ../shorten-lambda && mvn clean package || exit 1
      cd ../redirect-lambda && mvn clean package || exit 1

      aws s3 cp ../shorten-lambda/target/shorten-lambda-1.0-SNAPSHOT.jar s3://${aws_s3_bucket.lambda_artifacts.bucket}/shorten-lambda-1.0-SNAPSHOT.jar
      aws s3 cp ../redirect-lambda/target/redirect-lambda-1.0-SNAPSHOT.jar s3://${aws_s3_bucket.lambda_artifacts.bucket}/redirect-lambda-1.0-SNAPSHOT.jar
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [aws_s3_bucket.lambda_artifacts]
}

# Lamba functions
# Lambda: ShortenUrlLambda
resource "aws_lambda_function" "shorten_lambda" {
  function_name = "ShortenUrlLambda"
  s3_bucket     = aws_s3_bucket.lambda_artifacts.bucket
  s3_key        = "shorten-lambda-1.0-SNAPSHOT.jar"
  handler       = "com.abadlirachid.shortenlambda.ShortenLambda::handleRequest"
  runtime       = "java17"
  role          = aws_iam_role.lambda_exec_role.arn
  timeout       = 10

  environment {
    variables = {
      URL_TABLE  = aws_dynamodb_table.url_table.name
      REDIS_HOST = aws_elasticache_cluster.cache.cache_nodes[0].address
    }
  }

  depends_on = [null_resource.build_and_upload]
}

# Lambda: RedirectUrlLambda
resource "aws_lambda_function" "redirect_lambda" {
  function_name = "RedirectUrlLambda"
  s3_bucket     = aws_s3_bucket.lambda_artifacts.bucket
  s3_key        = "redirect-lambda-1.0-SNAPSHOT.jar"
  handler       = "com.abadlirachid.redirectlambda.RedirectLambda::handleRequest"
  runtime       = "java17"
  role          = aws_iam_role.lambda_exec_role.arn
  timeout       = 10

  environment {
    variables = {
      URL_TABLE  = aws_dynamodb_table.url_table.name
      REDIS_HOST = aws_elasticache_cluster.cache.cache_nodes[0].address
    }
  }

  depends_on = [null_resource.build_and_upload]
}

# API Gateway
resource "aws_apigatewayv2_api" "url_api" {
  name          = "url-shortener-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "shorten_integration" {
  api_id             = aws_apigatewayv2_api.url_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.shorten_lambda.invoke_arn
  integration_method = "POST"
  depends_on = [aws_lambda_function.shorten_lambda]

}

resource "aws_apigatewayv2_integration" "redirect_integration" {
  api_id             = aws_apigatewayv2_api.url_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.redirect_lambda.invoke_arn
  integration_method = "POST"
  depends_on = [aws_lambda_function.redirect_lambda]

}

resource "aws_apigatewayv2_route" "shorten_route" {
  api_id    = aws_apigatewayv2_api.url_api.id
  route_key = "POST /shortenurl"
  target    = "integrations/${aws_apigatewayv2_integration.shorten_integration.id}"
  depends_on = [ aws_apigatewayv2_integration.shorten_integration ]
}

resource "aws_apigatewayv2_route" "redirect_route" {
  api_id    = aws_apigatewayv2_api.url_api.id
  route_key = "GET /{shorturl}"
  target    = "integrations/${aws_apigatewayv2_integration.redirect_integration.id}"
  depends_on = [ aws_apigatewayv2_integration.redirect_integration ]
}

# DynamoDB Tables
# URL Table
resource "aws_dynamodb_table" "url_table" {
  name         = "UrlTable"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "shortCode"

  attribute {
    name = "shortCode"
    type = "S"
  }
}

# Counter Table
resource "aws_dynamodb_table" "counter_table" {
  name         = "UrlCounter"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "counterId"

  attribute {
    name = "counterId"
    type = "S"
  }
}


# Elastic Cache
# VPC and Subnet
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "main" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"
  depends_on = [ aws_vpc.main ]
}

# Elasticache Subnet Group
resource "aws_elasticache_subnet_group" "cache_subnet_group" {
  name       = "url-shortener-subnet-group"
  subnet_ids = [aws_subnet.main.id]
  depends_on = [ aws_subnet.main ]
}

# Elasticache Redis Cluster
resource "aws_elasticache_cluster" "cache" {
  cluster_id           = "url-shortener-cache"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  subnet_group_name    = aws_elasticache_subnet_group.cache_subnet_group.name
  depends_on = [ aws_elasticache_subnet_group.cache_subnet_group ]
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.url_api.api_endpoint
}
