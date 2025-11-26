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