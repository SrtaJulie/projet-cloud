# ---------------------------------------------------------------
# OUTPUTS
# ---------------------------------------------------------------
output "base_url" {
  value = "http://localhost:4566/restapis/${aws_api_gateway_rest_api.api.id}/${aws_api_gateway_stage.dev.stage_name}/_user_request_"
}

output "frontend_website_endpoint" {
      value = "http://${aws_s3_bucket.site_front.bucket}.s3-website.localhost.localstack.cloud:4566"
}