resource "aws_s3_bucket" "website" {
  bucket        = "static-website-bucket-resources-ken"
  force_destroy = true

  tags = {
    Name        = "Ken Chen Resume Website"
    Environment = "Production"
    Project     = "Cloud Resume Challenge"
  }
}

# Configure the S3 bucket for static website hosting
resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "404.html" # Optional: create a custom 404 page
  }
}

# S3 bucket public access block (allow public read for static website)
resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# S3 bucket policy to allow public read access
resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id
  depends_on = [aws_s3_bucket_public_access_block.website]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.website.arn}/*"
      }
    ]
  })
}

# S3 bucket CORS configuration
resource "aws_s3_bucket_cors_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = [
      "https://kchenfs.com",
      "https://www.kchenfs.com",
      "http://localhost:3000"  # For local development
    ]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

