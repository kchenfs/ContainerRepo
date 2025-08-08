resource "aws_s3_bucket" "website" {
  bucket        = "static-website-bucket-resources-ken"
  force_destroy = true

  tags = {
    Name        = "Ken Chen Resume Website"
    Environment = "Production"
    Project     = "Cloud Resume Challenge"
  }
}

resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "404.html"
  }
}

resource "aws_s3_bucket_public_access_block" "website" {
  bucket                  = aws_s3_bucket.website.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_cors_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = [
      "https://kchenfs.com",
      "https://www.kchenfs.com",
      "http://localhost:3000"
    ]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

output "s3_website_endpoint" {
  value = aws_s3_bucket_website_configuration.website.website_endpoint
}
