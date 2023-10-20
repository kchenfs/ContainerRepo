resource "aws_route53_zone" "main" {
  name    = "kchenfs.com"
  comment = "Managed by Terraform"
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


resource "aws_lb_listener" "front_end_listener" {
  load_balancer_arn = aws_lb.container_alb.arn # Replace with your ALB ARN
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.front_end_target_group.arn

  }
}

resource "aws_lb_target_group" "front_end_target_group" {
  name        = "fe-target-groups"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.personal_website_vpc.id
}

# Existing security group resource
resource "aws_security_group" "alb_sg" {
  vpc_id = aws_vpc.personal_website_vpc.id
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_lb" {
  security_group_id = aws_security_group.alb_sg.id
  from_port   = 0
  to_port     = 65535
  ip_protocol    = "tcp"
  cidr_ipv4 = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "allow_healthcheck" {
  security_group_id = aws_security_group.alb_sg.id

  ip_protocol        = -1
  referenced_security_group_id = aws_security_group.security_group_personal_website.id
}


resource "aws_security_group" "security_group_personal_website" {
  name_prefix = "container-sg"
  vpc_id      = aws_vpc.personal_website_vpc.id
}

resource "aws_vpc_security_group_ingress_rule" "allow_http" {
  security_group_id = aws_security_group.security_group_personal_website.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  ip_protocol = "tcp"
  to_port     = 80
}
resource "aws_vpc_security_group_ingress_rule" "allow_https" {
  security_group_id = aws_security_group.security_group_personal_website.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  ip_protocol = "tcp"
  to_port     = 443
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
  desired_count        = 0

  network_configuration {
    subnets          = [aws_subnet.personal_website_public_subnet.id, aws_subnet.personal_website_public_subnet2.id]
    security_groups  = [aws_security_group.security_group_personal_website.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.front_end_target_group.arn
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


