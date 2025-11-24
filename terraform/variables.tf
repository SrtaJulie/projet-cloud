variable "localstack_endpoint" {
  type      = string
  default   = "http://localhost:4566"
  sensitive = false
}


variable "aws_access_key" {
  description = "Clé d'accès AWS / LocalStack"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "Clé secrète AWS / LocalStack"
  type        = string
  sensitive   = true
}

variable "aws_region" {
  description = "Région AWS"
  type        = string
  sensitive   = true
}