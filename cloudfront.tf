resource "aws_cloudfront_distribution" "website" {
  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id                = aws_s3_bucket.website.id
    origin_access_control_id = aws_cloudfront_origin_access_control.website.id
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  aliases             = ["kchenfs.com", "www.kchenfs.com"]

  default_cache_behavior {
    allowed_methods   = ["GET", "HEAD", "OPTIONS"]
    cached_methods    = ["GET", "HEAD"]
    target_origin_id  = aws_s3_bucket.website.id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy   = "redirect-to-https"
    min_ttl                  = 0
    default_ttl              = 3600
    max_ttl                  = 86400
    compress                 = true
  }

  custom_error_response {
    error_caching_min_ttl   = 0
    error_code              = 404
    response_code           = 200
    response_page_path      = "/index.html"
  }

  custom_error_response {
    error_caching_min_ttl   = 0
    error_code              = 403
    response_code           = 200
    response_page_path      = "/index.html"
  }

  price_class               = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type       = "none"
    }
  }

viewer_certificate { 
 cloudfront_default_certificate=false 
 acm_certificate_arn=data.aws_ssm_parameter.cloudflare_cert.value 
 ssl_support_method="sni-only" 
 minimum_protocol_version="TLSv1.2_2021" 
} 

tags={ 
Name="Website CloudFront Distribution" 
Environment="prod" 
} 
}

# Update S3 bucket policy to allow CloudFront OAC

resource "aws_s3_bucket_policy" "website" { bucket=aws_s3_bucket.website.id policy=jsonencode({ Version="2012-10-17", Statement=[ { Sid="AllowCloudFrontServicePrincipal", Effect="Allow", Principal={ Service="cloudfront.amazonaws.com"}, Action="s3:GetObject", Resource="${aws_s3_bucket.website.arn}/*", Condition={ StringEquals={ "AWS:SourceArn": aws_cloudfront_distribution.website.arn } } } ] }) }

# Output the CloudFront domain name output

output cloudfront_domain_name{ value=aws_cloudfront_distribution.website.domain_name }

output cloudfront_distribution_id{ value=aws_cloudfront_distribution.website.id }
