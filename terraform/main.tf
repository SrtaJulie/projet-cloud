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

# ---------------------------------------------------------------
# PROVIDER LOCALSTACK
# ---------------------------------------------------------------
provider "aws" {
  region                      = var.aws_region
  access_key                  = var.aws_access_key
  secret_key                  = var.aws_secret_key
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true

  s3_use_path_style = true

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
# LAMBDA ZIP UNIQUE (toutes les lambdas dans /lambda)
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
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Scan"
        ],
        Resource = aws_dynamodb_table.bounties.arn
      }
    ]
  })
}

# ---------------------------------------------------------------
# LAMBDAS (4 fonctions séparées, même ZIP)
# ---------------------------------------------------------------
# handler = "hello.handler"  -> lambda/hello/handler.py
# handler = "get_bounties.handler" -> lambda/get_bounties/handler.py
# etc.

resource "aws_lambda_function" "hello" {
  function_name = "lambda-hello"
  runtime       = "python3.11"
  handler       = "hello.handler"
  role          = aws_iam_role.lambda_exec_role.arn

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
}

resource "aws_lambda_function" "get_bounties" {
  function_name = "lambda-get-bounties"
  runtime       = "python3.11"
  handler       = "get_bounties.handler"
  role          = aws_iam_role.lambda_exec_role.arn

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.bounties.name
    }
  }
}

resource "aws_lambda_function" "create_bounty" {
  function_name = "lambda-create-bounty"
  runtime       = "python3.11"
  handler       = "create_bounty.handler"
  role          = aws_iam_role.lambda_exec_role.arn

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.bounties.name
    }
  }
}

resource "aws_lambda_function" "claim_bounty" {
  function_name = "lambda-claim-bounty"
  runtime       = "python3.11"
  handler       = "claim_bounty.handler"
  role          = aws_iam_role.lambda_exec_role.arn

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.bounties.name
    }
  }
}

# ---------------------------------------------------------------
# API GATEWAY ROOT
# ---------------------------------------------------------------
resource "aws_api_gateway_rest_api" "api" {
  name = "pirate-bounty-api"
}

# ---------------------------------------------------------------
# CORS ROOT "/"
# ---------------------------------------------------------------
resource "aws_api_gateway_method" "root_options" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_rest_api.api.root_resource_id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "root_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_rest_api.api.root_resource_id
  http_method = aws_api_gateway_method.root_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{ \"statusCode\": 200 }"
  }
}

resource "aws_api_gateway_method_response" "root_options_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_rest_api.api.root_resource_id
  http_method = aws_api_gateway_method.root_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
  }
}

resource "aws_api_gateway_integration_response" "root_options_integration_response" {
  depends_on = [aws_api_gateway_integration.root_options_integration]

  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_rest_api.api.root_resource_id
  http_method = aws_api_gateway_method.root_options.http_method
  status_code = aws_api_gateway_method_response.root_options_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
  }
}

# ---------------------------------------------------------------
# ENDPOINT /hello (GET + OPTIONS) -> lambda hello
# ---------------------------------------------------------------
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
  uri                     = aws_lambda_function.hello.invoke_arn
}

# CORS /hello
resource "aws_api_gateway_method" "hello_options" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.hello.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "hello_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.hello.id
  http_method = aws_api_gateway_method.hello_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{ \"statusCode\": 200 }"
  }
}

resource "aws_api_gateway_method_response" "hello_options_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.hello.id
  http_method = aws_api_gateway_method.hello_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
  }
}

resource "aws_api_gateway_integration_response" "hello_options_integration_response" {
  depends_on = [aws_api_gateway_integration.hello_options_integration]

  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.hello.id
  http_method = aws_api_gateway_method.hello_options.http_method
  status_code = aws_api_gateway_method_response.hello_options_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
  }
}

# ---------------------------------------------------------------
# ENDPOINT /bounties (GET + OPTIONS) -> lambda get_bounties
# ---------------------------------------------------------------
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
  uri                     = aws_lambda_function.get_bounties.invoke_arn
}

# CORS /bounties
resource "aws_api_gateway_method" "bounties_options" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.bounties.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "bounties_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.bounties.id
  http_method = aws_api_gateway_method.bounties_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{ \"statusCode\": 200 }"
  }
}

resource "aws_api_gateway_method_response" "bounties_options_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.bounties.id
  http_method = aws_api_gateway_method.bounties_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
  }
}

resource "aws_api_gateway_integration_response" "bounties_options_integration_response" {
  depends_on = [aws_api_gateway_integration.bounties_options_integration]

  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.bounties.id
  http_method = aws_api_gateway_method.bounties_options.http_method
  status_code = aws_api_gateway_method_response.bounties_options_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
  }
}

# ---------------------------------------------------------------
# ENDPOINT /bounty (POST + OPTIONS) -> lambda create_bounty
# ---------------------------------------------------------------
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
  uri                     = aws_lambda_function.create_bounty.invoke_arn
}

# CORS /bounty
resource "aws_api_gateway_method" "bounty_options" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.bounty.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "bounty_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.bounty.id
  http_method = aws_api_gateway_method.bounty_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{ \"statusCode\": 200 }"
  }
}

resource "aws_api_gateway_method_response" "bounty_options_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.bounty.id
  http_method = aws_api_gateway_method.bounty_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
  }
}

resource "aws_api_gateway_integration_response" "bounty_options_integration_response" {
  depends_on = [aws_api_gateway_integration.bounty_options_integration]

  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.bounty.id
  http_method = aws_api_gateway_method.bounty_options.http_method
  status_code = aws_api_gateway_method_response.bounty_options_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
  }
}

# ---------------------------------------------------------------
# ENDPOINT /claim (POST + OPTIONS) -> lambda claim_bounty
# ---------------------------------------------------------------
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
  uri                     = aws_lambda_function.claim_bounty.invoke_arn
}

# CORS /claim
resource "aws_api_gateway_method" "claim_options" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.claim.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "claim_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.claim.id
  http_method = aws_api_gateway_method.claim_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{ \"statusCode\": 200 }"
  }
}

resource "aws_api_gateway_method_response" "claim_options_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.claim.id
  http_method = aws_api_gateway_method.claim_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
  }
}

resource "aws_api_gateway_integration_response" "claim_options_integration_response" {
  depends_on = [aws_api_gateway_integration.claim_options_integration]

  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.claim.id
  http_method = aws_api_gateway_method.claim_options.http_method
  status_code = aws_api_gateway_method_response.claim_options_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
  }
}

# ---------------------------------------------------------------
# PERMISSIONS LAMBDA (API Gateway -> Lambdas)
# ---------------------------------------------------------------
resource "aws_lambda_permission" "allow_from_apig_hello" {
  statement_id  = "AllowInvokeFromAPIGHello"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "allow_from_apig_get_bounties" {
  statement_id  = "AllowInvokeFromAPIGGetBounties"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_bounties.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "allow_from_apig_create_bounty" {
  statement_id  = "AllowInvokeFromAPIGCreateBounty"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_bounty.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "allow_from_apig_claim_bounty" {
  statement_id  = "AllowInvokeFromAPIGClaimBounty"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.claim_bounty.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# ---------------------------------------------------------------
# DEPLOYMENT + STAGE
# ---------------------------------------------------------------
resource "aws_api_gateway_deployment" "deploy" {
  depends_on = [
    aws_api_gateway_integration.hello_integration,
    aws_api_gateway_integration.bounties_integration,
    aws_api_gateway_integration.bounty_integration,
    aws_api_gateway_integration.claim_integration,
    aws_api_gateway_integration.hello_options_integration,
    aws_api_gateway_integration.bounties_options_integration,
    aws_api_gateway_integration.bounty_options_integration,
    aws_api_gateway_integration.claim_options_integration,
    aws_api_gateway_integration.root_options_integration
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

resource "aws_s3_bucket_website_configuration" "site_front" {
  bucket = aws_s3_bucket.site_front.id

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

  bucket = aws_s3_bucket.site_front.bucket
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
