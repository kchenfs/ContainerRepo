resource "aws_cloudfront_distribution" "my_cdn" {
  aliases = ["web.kchenfs.com"]
  origin {
    domain_name = aws_lb.container_alb.dns_name
    origin_id   = "my-alb-origin"
    custom_header {
      name  = "X-Custom-Header"
      value = "random-value-1234567890"
    }
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "match-viewer"
      origin_ssl_protocols   = ["TLSv1.2"]

    }
  }

  enabled             = true
  http_version        = "http3"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }
  viewer_certificate {
    acm_certificate_arn      = "arn:aws:acm:us-east-1:798965869505:certificate/701a8a27-1ff7-49a8-8277-48e2109e9f0e"
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  default_cache_behavior {
    target_origin_id         = "my-alb-origin"
    allowed_methods          = ["GET", "HEAD"]
    cached_methods           = ["GET", "HEAD"]
    min_ttl                  = 0
    default_ttl              = 3600
    max_ttl                  = 86400
    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    origin_request_policy_id = aws_cloudfront_origin_request_policy.my_origin_request_policy.id
  }
}


resource "aws_cloudfront_origin_request_policy" "my_origin_request_policy" {
  name    = "HTTPS-ALB-CACHE-POLICY"
  comment = "my origin request policy"

  cookies_config {
    cookie_behavior = "none"
  }

  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["host"]
    }
  }

  query_strings_config {
    query_string_behavior = "none"
  }
}