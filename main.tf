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
    name                   = aws_lb.container_alb.dns_name
    zone_id                = aws_lb.container_alb.zone_id
    evaluate_target_health = true
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
  vpc_id = aws_vpc.personal_website_vpc.id
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

resource "aws_vpc_security_group_ingress_rule" "allow-lb-traffic" {
  security_group_id = aws_security_group.security_group_personal_website.id

  referenced_security_group_id = aws_security_group.alb_sg.id
  ip_protocol                  = -1
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


