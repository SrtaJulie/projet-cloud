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
  handler       = "hello.handler.handler"
  role          = aws_iam_role.lambda_exec_role.arn

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
}

resource "aws_lambda_function" "get_bounties" {
  function_name = "lambda-get-bounties"
  runtime       = "python3.11"
  handler       = "get_bounties.handler.handler"
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
  handler       = "create_bounty.handler.handler"
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
  handler       = "claim_bounty.handler.handler"
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