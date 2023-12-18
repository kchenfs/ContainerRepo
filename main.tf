resource "aws_route53_zone" "myzone" {
  name    = "kchenfs.com"
  comment = "Managed by Terraform in main.tf"
}

resource "aws_acm_certificate" "alb_cert" {
  domain_name       = "web.kchenfs.com"
  validation_method = "DNS"

  tags = {
    Environment = "test"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "alb_dns_record" {
  zone_id = aws_route53_zone.myzone.zone_id
  name    = "web.kchenfs.com"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.my_cdn.domain_name
    zone_id                = aws_cloudfront_distribution.my_cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "cert_record" {
  allow_overwrite = true
  name            = tolist(aws_acm_certificate.alb_cert.domain_validation_options)[0].resource_record_name
  records         = [tolist(aws_acm_certificate.alb_cert.domain_validation_options)[0].resource_record_value]
  type            = tolist(aws_acm_certificate.alb_cert.domain_validation_options)[0].resource_record_type
  zone_id         = aws_route53_zone.myzone.zone_id
  ttl             = 60
}

resource "aws_acm_certificate_validation" "alb_cert_validation" {
  certificate_arn         = aws_acm_certificate.alb_cert.arn
  validation_record_fqdns = [aws_route53_record.cert_record.fqdn]
}



resource "aws_lb" "container_alb" {
  name                       = "container-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb_sg.id]
  subnets                    = [aws_subnet.personal_website_public_subnet.id, aws_subnet.personal_website_public_subnet2.id]
  enable_deletion_protection = false
  enable_http2               = true
  ip_address_type            = "ipv4"

}


resource "aws_lb_listener" "front_end_redirect_to_https" {
  load_balancer_arn = aws_lb.container_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "front_end_https" {
  load_balancer_arn = aws_lb.container_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.alb_cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.front_end.arn
  }
}

resource "aws_lb_listener_rule" "Forward-Customer-Header-Rule" {
  listener_arn = aws_lb_listener.front_end_https.arn
  priority     = 1

  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.front_end.arn
  }

  condition {
    http_header {
      http_header_name = "X-Custom_Header"
      values           = ["randomvalue1234567890"]
    }
  }
}




resource "aws_lb_target_group" "front_end" {
  name        = "fe-target-groups"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.personal_website_vpc.id
}


# Existing security group resource
resource "aws_security_group" "alb_sg" {
  description = "security group for ALB"
  vpc_id      = aws_vpc.personal_website_vpc.id
  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_vpc_security_group_ingress_rule" "allow_http_lb" {
  security_group_id = aws_security_group.alb_sg.id
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "allow_https_lb" {
  security_group_id = aws_security_group.alb_sg.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "allow_healthcheck" {
  security_group_id = aws_security_group.alb_sg.id

  ip_protocol                  = -1
  referenced_security_group_id = aws_security_group.security_group_personal_website.id
}


resource "aws_security_group" "security_group_personal_website" {
  name_prefix = "container-sg"
  description = "security group for containers"
  vpc_id      = aws_vpc.personal_website_vpc.id
  lifecycle {
    create_before_destroy = true
  }
}



# Create a VPC
resource "aws_vpc" "personal_website_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

}

# Create a subnet within the VPC
resource "aws_subnet" "personal_website_public_subnet" {
  vpc_id                  = aws_vpc.personal_website_vpc.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "ca-central-1a" # Replace with your desired AZ
  map_public_ip_on_launch = true
}

resource "aws_subnet" "personal_website_public_subnet2" {
  vpc_id                  = aws_vpc.personal_website_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ca-central-1b" # Replace with your desired AZ
  map_public_ip_on_launch = true
}

# Create an internet gateway
resource "aws_internet_gateway" "personal_website_igw" { #route table rules to allow the ALB?
  vpc_id = aws_vpc.personal_website_vpc.id
}

resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = 2
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.kchenfs_cluster.name}/${aws_ecs_service.kchenfs_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_scaling_policy" {
  name               = "ecs-service-target-tracking-policy"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = 70 # Adjust this value based on your desired CPU utilization target
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
  }
}


resource "aws_ecs_cluster" "kchenfs_cluster" {
  name = "kchenfs-cluster"
}

resource "aws_ecs_service" "kchenfs_service" {
  name                 = "kchenfs-service"
  cluster              = aws_ecs_cluster.kchenfs_cluster.arn
  task_definition      = aws_ecs_task_definition.personal_website_task.arn
  launch_type          = "FARGATE"
  platform_version     = "LATEST"
  force_new_deployment = true
  desired_count        = 1

  lifecycle {
    ignore_changes = [desired_count]
  }

  network_configuration {
    subnets          = [aws_subnet.personal_website_public_subnet.id, aws_subnet.personal_website_public_subnet2.id]
    security_groups  = [aws_security_group.security_group_personal_website.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.front_end.arn
    container_name   = "web"
    container_port   = 80
  }
}



# Create an ECS Task Definition
resource "aws_ecs_task_definition" "personal_website_task" {
  family                   = "personal-website"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  cpu                      = 256
  memory                   = 512
  pid_mode                 = "task"
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = <<EOF
[
  {
    "name": "web",
    "image": "798965869505.dkr.ecr.ca-central-1.amazonaws.com/container-repo:latest",
    "cpu": 256,
    "portMappings": [
      {
        "containerPort": 80,
        "hostPort": 80,
        "protocol": "tcp"
      }
    ]
  }
]
EOF
}

resource "aws_ecr_repository" "personal_website_repo" {
  name                 = "container-repo"
  image_tag_mutability = "MUTABLE" # or "IMMUTABLE" as needed

  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Create an IAM role for ECS Fargate Task Role
resource "aws_iam_role" "ecs_task_role" {
  name = "ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}



resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}


resource "aws_dynamodb_table" "website_counter" {
  name         = "WebsiteCounterTable"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "CounterID"

  attribute {
    name = "CounterID"
    type = "S" #
  }
}





resource "aws_lambda_function" "website_counter_lambda" {
  function_name = "WebsiteCounterLambda"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"                           # The runtime for your Lambda function
  role          = aws_iam_role.lambda_execution_role.arn # ARN of the IAM role for your Lambda function
  s3_bucket     = "kencfswebsite"
  s3_key        = "lambda_function.zip"

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.website_counter.name
    }
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "lambda_execution_policy" {
  name       = "lambda_execution"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  roles      = [aws_iam_role.lambda_execution_role.name]
}

resource "aws_iam_policy_attachment" "dynamodb_policy" {
  name       = "dynamodb_access"
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
  roles      = [aws_iam_role.lambda_execution_role.name]
}


resource "aws_api_gateway_rest_api" "count_api" {
  name        = "CountAPI"
  description = "API for Counting"
}

resource "aws_api_gateway_resource" "count_resource" {
  rest_api_id = aws_api_gateway_rest_api.count_api.id
  parent_id   = aws_api_gateway_rest_api.count_api.root_resource_id
  path_part   = "myresource" # The URL path for your resource
}

resource "aws_api_gateway_method" "count_get_method" {
  rest_api_id   = aws_api_gateway_rest_api.count_api.id
  resource_id   = aws_api_gateway_resource.count_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "count_post_method" {
  rest_api_id   = aws_api_gateway_rest_api.count_api.id
  resource_id   = aws_api_gateway_resource.count_resource.id
  http_method   = "POST"
  authorization = "NONE"
}


resource "aws_api_gateway_integration" "count_get_integration" {
  rest_api_id             = aws_api_gateway_rest_api.count_api.id
  resource_id             = aws_api_gateway_resource.count_resource.id
  http_method             = aws_api_gateway_method.count_get_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.website_counter_lambda.invoke_arn
}

resource "aws_api_gateway_integration" "count_post_integration" {
  rest_api_id             = aws_api_gateway_rest_api.count_api.id
  resource_id             = aws_api_gateway_resource.count_resource.id
  http_method             = aws_api_gateway_method.count_post_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.website_counter_lambda.invoke_arn
}


resource "aws_api_gateway_method_response" "count_get_response" {
  rest_api_id = aws_api_gateway_rest_api.count_api.id
  resource_id = aws_api_gateway_resource.count_resource.id
  http_method = aws_api_gateway_method.count_get_method.http_method
  status_code = "200"
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_method_response" "count_post_response" {
  rest_api_id   = aws_api_gateway_rest_api.count_api.id
  resource_id   = aws_api_gateway_resource.count_resource.id
  http_method   = aws_api_gateway_method.count_post_method.http_method
  status_code   = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}



resource "aws_api_gateway_integration_response" "count_get_response" {
  rest_api_id = aws_api_gateway_rest_api.count_api.id
  resource_id = aws_api_gateway_resource.count_resource.id
  http_method = aws_api_gateway_method.count_get_method.http_method
  status_code = aws_api_gateway_method_response.count_get_response.status_code
  response_templates = {
    "application/json" = ""
  }
}

resource "aws_api_gateway_integration_response" "count_post_response" {
  rest_api_id = aws_api_gateway_rest_api.count_api.id
  resource_id = aws_api_gateway_resource.count_resource.id
  http_method = aws_api_gateway_method.count_post_method.http_method
  status_code = aws_api_gateway_method_response.count_post_response.status_code
  response_templates = {
    "application/json" = ""
  }
}

resource "aws_api_gateway_deployment" "count_deployment" {
  depends_on = [
    aws_api_gateway_integration.count_get_integration,
    aws_api_gateway_integration.count_post_integration,
  ]
  rest_api_id = aws_api_gateway_rest_api.count_api.id
  stage_name  = "prod"
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.website_counter_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.myregion}:${var.accountId}:${aws_api_gateway_rest_api.count_api.id}/*"
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