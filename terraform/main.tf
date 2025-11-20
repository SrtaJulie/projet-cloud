#############################################################
# TERRAFORM + PROVIDERS
#############################################################
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
  region                      = var.aws_region
  access_key                  = var.aws_access_key
  secret_key                  = var.aws_secret_key
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  s3_use_path_style           = true

  endpoints {
    s3         = var.localstack_endpoint
    lambda     = var.localstack_endpoint
    dynamodb   = var.localstack_endpoint
    apigateway = var.localstack_endpoint
    iam        = var.localstack_endpoint
    cloudwatch = var.localstack_endpoint
  }
}

# ---------------------------------------------------------------
# DYNAMODB TABLE
# ---------------------------------------------------------------
resource "aws_dynamodb_table" "bounties" {
  name         = "Bounties"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  # NOTE:
  # En prod AWS, on activerait le chiffrement côté serveur (SSE) ici.
  # Sur LocalStack, le bloc server_side_encryption provoque des erreurs
  # CreateTable / ResourceInUseException, donc il est volontairement omis.
  #
  # Exemple (à utiliser en VRAI AWS, pas dans ce TP LocalStack) :
  #
  # server_side_encryption {
  #   enabled = true
  # }
}

# ---------------------------------------------------------------
# LAMBDA ZIP
# ---------------------------------------------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

# ---------------------------------------------------------------
# IAM ROLE + POLICIES (principe du moindre privilège)
# ---------------------------------------------------------------
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Action    = "sts:AssumeRole",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Logs
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      },
      # Accès Dynamo strict
      {
        Effect = "Allow",
        Action = [
          "dynamodb:Scan",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem"
        ],
        Resource = aws_dynamodb_table.bounties.arn
      }
    ]
  })
}

#############################################################
# PACKAGING DES 4 LAMBDAS
#############################################################

# 1 — HELLO
data "archive_file" "hello_zip" {
  type        = "zip"
  source_file = "${path.module}/lambdas/hello.py"
  output_path = "${path.module}/build/hello.zip"
}

resource "aws_lambda_function" "hello" {
  function_name = "hello"
  role          = aws_iam_role.lambda_role.arn
  runtime       = "python3.11"
  handler       = "hello.handler"
  filename      = data.archive_file.hello_zip.output_path
}

# 2 — LIST BOUNTIES
data "archive_file" "list_bounties_zip" {
  type        = "zip"
  source_file = "${path.module}/lambdas/list_bounties.py"
  output_path = "${path.module}/build/list_bounties.zip"
}

resource "aws_lambda_function" "list_bounties" {
  function_name = "list-bounties"
  role          = aws_iam_role.lambda_role.arn
  runtime       = "python3.11"
  handler       = "list_bounties.handler"
  filename      = data.archive_file.list_bounties_zip.output_path

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.bounties.name
    }
  }
}

# 3 — CREATE BOUNTY
data "archive_file" "create_bounty_zip" {
  type        = "zip"
  source_file = "${path.module}/lambdas/create_bounty.py"
  output_path = "${path.module}/build/create_bounty.zip"
}

resource "aws_lambda_function" "create_bounty" {
  function_name = "create-bounty"
  role          = aws_iam_role.lambda_role.arn
  runtime       = "python3.11"
  handler       = "create_bounty.handler"
  filename      = data.archive_file.create_bounty_zip.output_path

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.bounties.name
    }
  }
}

# 4 — CLAIM
data "archive_file" "claim_bounty_zip" {
  type        = "zip"
  source_file = "${path.module}/lambdas/claim_bounty.py"
  output_path = "${path.module}/build/claim_bounty.zip"
}

resource "aws_lambda_function" "claim_bounty" {
  function_name = "claim-bounty"
  role          = aws_iam_role.lambda_role.arn
  runtime       = "python3.11"
  handler       = "claim_bounty.handler"
  filename      = data.archive_file.claim_bounty_zip.output_path

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.bounties.name
    }
  }
}

#############################################################
# API GATEWAY
#############################################################
resource "aws_api_gateway_rest_api" "api" {
  name = "pirate-bounty-api"
}

#############################
# CORS HELPER (réutilisé)
#############################
locals {
  cors_headers = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
  }

  cors_params = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
  }
}

#############################################################
# ROUTES
#############################################################

### /hello (GET)
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

resource "aws_api_gateway_integration" "hello_int" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.hello.id
  http_method             = aws_api_gateway_method.hello_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.hello.invoke_arn
}

# CORS /hello
resource "aws_api_gateway_method" "hello_options" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.hello.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "hello_cors" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.hello.id
  http_method = "OPTIONS"
  type        = "MOCK"
  request_templates = {
    "application/json" = "{ \"statusCode\": 200 }"
  }
}

resource "aws_api_gateway_method_response" "hello_cors_resp" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.hello.id
  http_method = "OPTIONS"
  status_code = "200"
  response_parameters = local.cors_headers
}

resource "aws_api_gateway_integration_response" "hello_cors_int_resp" {
  rest_api_id  = aws_api_gateway_rest_api.api.id
  resource_id  = aws_api_gateway_resource.hello.id
  http_method  = "OPTIONS"
  status_code  = "200"
  response_parameters = local.cors_params
}

#############################################################
# /bounties (GET)
#############################################################
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

resource "aws_api_gateway_integration" "bounties_int" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.bounties.id
  http_method             = "GET"
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.list_bounties.invoke_arn
}

# CORS /bounties
resource "aws_api_gateway_method" "bounties_opt" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.bounties.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "bounties_cors" {
  rest_api_id        = aws_api_gateway_rest_api.api.id
  resource_id        = aws_api_gateway_resource.bounties.id
  http_method        = "OPTIONS"
  type               = "MOCK"
  request_templates  = { "application/json" = "{ \"statusCode\": 200 }" }
}

resource "aws_api_gateway_method_response" "bounties_cors_resp" {
  rest_api_id        = aws_api_gateway_rest_api.api.id
  resource_id        = aws_api_gateway_resource.bounties.id
  http_method        = "OPTIONS"
  status_code        = "200"
  response_parameters = local.cors_headers
}

resource "aws_api_gateway_integration_response" "bounties_cors_int_resp" {
  rest_api_id        = aws_api_gateway_rest_api.api.id
  resource_id        = aws_api_gateway_resource.bounties.id
  http_method        = "OPTIONS"
  status_code        = "200"
  response_parameters = local.cors_params
}

#############################################################
# /bounty (POST)
#############################################################
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

resource "aws_api_gateway_integration" "bounty_int" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.bounty.id
  http_method             = "POST"
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.create_bounty.invoke_arn
}

# CORS /bounty
resource "aws_api_gateway_method" "bounty_opt" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.bounty.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "bounty_cors" {
  rest_api_id       = aws_api_gateway_rest_api.api.id
  resource_id       = aws_api_gateway_resource.bounty.id
  http_method       = "OPTIONS"
  type              = "MOCK"
  request_templates = { "application/json" = "{ \"statusCode\": 200 }" }
}

resource "aws_api_gateway_method_response" "bounty_cors_resp" {
  rest_api_id        = aws_api_gateway_rest_api.api.id
  resource_id        = aws_api_gateway_resource.bounty.id
  http_method        = "OPTIONS"
  status_code        = "200"
  response_parameters = local.cors_headers
}

resource "aws_api_gateway_integration_response" "bounty_cors_int_resp" {
  rest_api_id        = aws_api_gateway_rest_api.api.id
  resource_id        = aws_api_gateway_resource.bounty.id
  http_method        = "OPTIONS"
  status_code        = "200"
  response_parameters = local.cors_params
}

#############################################################
# /claim (POST)
#############################################################
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

resource "aws_api_gateway_integration" "claim_int" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.claim.id
  http_method             = "POST"
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.claim_bounty.invoke_arn
}

# CORS /claim
resource "aws_api_gateway_method" "claim_opt" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.claim.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "claim_cors" {
  rest_api_id       = aws_api_gateway_rest_api.api.id
  resource_id       = aws_api_gateway_resource.claim.id
  http_method       = "OPTIONS"
  type              = "MOCK"
  request_templates = { "application/json" = "{ \"statusCode\": 200 }" }
}

resource "aws_api_gateway_method_response" "claim_cors_resp" {
  rest_api_id        = aws_api_gateway_rest_api.api.id
  resource_id        = aws_api_gateway_resource.claim.id
  http_method        = "OPTIONS"
  status_code        = "200"
  response_parameters = local.cors_headers
}

resource "aws_api_gateway_integration_response" "claim_cors_int_resp" {
  rest_api_id        = aws_api_gateway_rest_api.api.id
  resource_id        = aws_api_gateway_resource.claim.id
  http_method        = "OPTIONS"
  status_code        = "200"
  response_parameters = local.cors_params
}

#############################################################
# PERMISSION API GATEWAY → LAMBDA
#############################################################
resource "aws_lambda_permission" "hello" {
  statement_id  = "AllowInvokeHello"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "list" {
  statement_id  = "AllowInvokeList"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.list_bounties.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "create" {
  statement_id  = "AllowInvokeCreate"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_bounty.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "claim" {
  statement_id  = "AllowInvokeClaim"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.claim_bounty.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

#############################################################
# DEPLOY + STAGE
#############################################################
resource "aws_api_gateway_deployment" "deploy" {
  depends_on = [
    aws_api_gateway_integration.hello_int,
    aws_api_gateway_integration.bounties_int,
    aws_api_gateway_integration.bounty_int,
    aws_api_gateway_integration.claim_int,
  ]

  rest_api_id = aws_api_gateway_rest_api.api.id
}

resource "aws_api_gateway_stage" "dev" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deploy.id
  stage_name    = "dev"
}

# ---------------------------------------------------------------
# S3 FRONT : Site statique + ACL + SSE
# ---------------------------------------------------------------
resource "aws_s3_bucket" "site_front" {
  bucket = "pirate-site-front-julie"
}

resource "aws_s3_bucket_acl" "site_acl" {
  bucket = aws_s3_bucket.site.id
  acl    = "public-read"
}

resource "aws_s3_bucket_public_access_block" "site_pub" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "site_policy" {
  bucket = aws_s3_bucket.site.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = "*",
      Action   = "s3:GetObject",
      Resource = "${aws_s3_bucket.site.arn}/*"
    }]
  })
}

resource "aws_s3_bucket_website_configuration" "site_web" {
  bucket = aws_s3_bucket.site.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

# ACL : site statique public (lecture seule)
resource "aws_s3_bucket_acl" "site_front_acl" {
  bucket = aws_s3_bucket.site_front.id
  acl    = "public-read"
}

# SSE-S3 : chiffrement côté serveur (AES256)
resource "aws_s3_bucket_server_side_encryption_configuration" "site_front_sse" {
  bucket = aws_s3_bucket.site_front.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Public access block (laisse passer le public pour le site web)
resource "aws_s3_bucket_public_access_block" "site_front_access" {
  bucket                  = aws_s3_bucket.site_front.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Bucket policy : autorise GET public sur les fichiers
resource "aws_s3_bucket_policy" "site_front_policy" {
  bucket = aws_s3_bucket.site_front.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.site_front.arn}/*"
    }]
  })
}

# Upload des fichiers du front
resource "aws_s3_object" "site_files" {
  for_each = fileset("${path.module}/website", "**")

  bucket = aws_s3_bucket.site.bucket
  key    = each.value
  source = "${path.module}/website/${each.value}"
  etag   = filemd5("${path.module}/website/${each.value}")
  content_type = lookup({
    "html" = "text/html",
    "css"  = "text/css",
    "js"   = "application/javascript",
    "png"  = "image/png",
    "jpg"  = "image/jpeg",
    "jpeg" = "image/jpeg",
    "gif"  = "image/gif",
    "ico"  = "image/x-icon"
  }, split(".", each.value)[length(split(".", each.value)) - 1], "application/octet-stream")
}
