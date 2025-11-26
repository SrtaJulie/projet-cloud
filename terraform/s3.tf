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