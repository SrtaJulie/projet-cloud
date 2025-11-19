terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region                      = "eu-west-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  s3_use_path_style           = true

  endpoints {
    s3         = "http://localhost:4566"
    lambda     = "http://localhost:4566"
    dynamodb   = "http://localhost:4566"
    apigateway = "http://localhost:4566"
    iam        = "http://localhost:4566"
    cloudwatch = "http://localhost:4566"
  }
}

# ---------------------------
# S3 (pour stockage futur)
# ---------------------------
resource "aws_s3_bucket" "site" {
  bucket = "projet-cloud-site-julie"
}

# ---------------------------
# DynamoDB
# ---------------------------
resource "aws_dynamodb_table" "bounties" {
  name         = "Bounties"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }
}

# ---------------------------
# Lambda ZIP
# ---------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

# Role Lambda
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = "sts:AssumeRole",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Permissions Lambda
resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda_policy"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["logs:*"],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = ["dynamodb:*"],
        Resource = aws_dynamodb_table.bounties.arn
      },
      {
        Effect = "Allow",
        Action = ["s3:*"],
        Resource = [
          aws_s3_bucket.site.arn,
          "${aws_s3_bucket.site.arn}/*"
        ]
      }
    ]
  })
}

# Lambda
resource "aws_lambda_function" "api_handler" {
  function_name = "api-handler"
  runtime       = "python3.11"
  handler       = "handler.handler"
  role          = aws_iam_role.lambda_exec_role.arn

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.bounties.name
      BUCKET     = aws_s3_bucket.site.bucket
    }
  }
}

# ---------------------------
# API Gateway REST
# ---------------------------
resource "aws_api_gateway_rest_api" "api" {
  name = "pirate-bounty-api"
}

# GET /hello
resource "aws_api_gateway_resource" "hello" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "hello"
}

resource "aws_api_gateway_method" "hello_get" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.hello.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "hello_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.hello.id
  http_method             = aws_api_gateway_method.hello_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api_handler.invoke_arn
}

# GET /bounties
resource "aws_api_gateway_resource" "bounties" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "bounties"
}

resource "aws_api_gateway_method" "bounties_get" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.bounties.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "bounties_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.bounties.id
  http_method             = aws_api_gateway_method.bounties_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api_handler.invoke_arn
}

# POST /bounty
resource "aws_api_gateway_resource" "bounty" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "bounty"
}

resource "aws_api_gateway_method" "bounty_post" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.bounty.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "bounty_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.bounty.id
  http_method             = aws_api_gateway_method.bounty_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api_handler.invoke_arn
}

# POST /claim
resource "aws_api_gateway_resource" "claim" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "claim"
}

resource "aws_api_gateway_method" "claim_post" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.claim.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "claim_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.claim.id
  http_method             = aws_api_gateway_method.claim_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api_handler.invoke_arn
}

# ---------------------------
# Lambda permission
# ---------------------------
resource "aws_lambda_permission" "allow_from_apig" {
  statement_id  = "AllowInvokeFromAPIG"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# ---------------------------
# DEPLOY API
# ---------------------------
resource "aws_api_gateway_deployment" "deploy" {
  depends_on = [
    aws_api_gateway_integration.hello_integration,
    aws_api_gateway_integration.bounty_integration,
    aws_api_gateway_integration.bounties_integration,
    aws_api_gateway_integration.claim_integration
  ]

  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "dev"
}

# ---------------------------
# OUTPUTS
# ---------------------------
output "base_url" {
  value = "http://localhost:4566/restapis/${aws_api_gateway_rest_api.api.id}/dev/_user_request_"
}