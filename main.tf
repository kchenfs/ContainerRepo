provider "aws" {
  region = "ca-central-1"
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
  availability_zone       = "ca-central-1b"       # Replace with your desired AZ
  map_public_ip_on_launch = true
}


# Create an internet gateway
resource "aws_internet_gateway" "personal_website_igw" { #route table rules to allow the ALB?
  vpc_id = aws_vpc.personal_website_vpc.id
}


# Existing security group resource
resource "aws_security_group" "security_group_personal_website" {
  name_prefix = "example-"
  vpc_id      = aws_vpc.personal_website_vpc.id 

  # Ingress rule for HTTP (port 80)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Ingress rule for HTTP (port 80)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

}


# Existing security group resource
resource "aws_security_group" "alb_sg" {
  vpc_id      = aws_vpc.personal_website_vpc.id 

   # Ingress rule for HTTP (port 80)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
}





# Create an ECS Cluster
resource "aws_ecs_cluster" "personal_website_cluster" {
  name = "personal-website-cluster"
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

resource "aws_iam_policy" "combined_policy" {
  name        = "CombinedECSPolicy"
  description = "Combined policy for ECS Task Role"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = [
          
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ],
        Effect   = "Allow",
        Resource = "*",
      },
    ],
  })
}


# Attach the ECS Exec policy to the ECS task role
resource "aws_iam_role_policy_attachment" "ecs_task_attachment" {
  policy_arn = aws_iam_policy.combined_policy.arn
  role       = aws_iam_role.ecs_task_role.name
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
        "containerPort": 8081,
        "hostPort": 8081,
        "protocol": "tcp"
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "container-website-log-group",
        "awslogs-region": "ca-central-1",
        "awslogs-stream-prefix" : "personal_website"
      }
    }
  }
]
EOF
}

# Create an ECS Service
resource "aws_ecs_service" "personal_website_service" {
  name                   = "personal-website-service"
  cluster                = aws_ecs_cluster.personal_website_cluster.id
  task_definition        = aws_ecs_task_definition.personal_website_task.arn
  launch_type            = "FARGATE"
  platform_version       = "LATEST"
  enable_execute_command = true
  health_check_grace_period_seconds = 10
  desired_count          = 0
  network_configuration {
    subnets          = [aws_subnet.personal_website_public_subnet.id, aws_subnet.personal_website_public_subnet2.id]
    security_groups  = [aws_security_group.security_group_personal_website.id]
    assign_public_ip = true
  }
  
  load_balancer {
    target_group_arn = aws_lb_target_group.front_end_target_group.arn
    container_name   = "web"
    container_port   = 8081
  }
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




resource "aws_iam_policy" "ecs_execution_role_policy" {
  name        = "ECSExecutionRolePolicy"
  description = "Policy for ECS Execution Role"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          # Add other actions if needed
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy_attachment" {
  policy_arn = aws_iam_policy.ecs_execution_role_policy.arn
  role       = aws_iam_role.ecs_execution_role.name
}


output "ecs_service_name" {
  value = aws_ecs_service.personal_website_service.name
}


resource "aws_route53_zone" "main" {
  name    = "kchenfs.com"
  comment = "Managed by Terraform"
}

resource "aws_cloudwatch_log_group" "container_log_group" {
  name              = "container-website-log-group"
  retention_in_days = 7 # Set your desired retention period in days
}

resource "aws_acm_certificate" "wildcard_certificate" {
  domain_name       = "*.kchenfs.com"
  validation_method = "DNS"
}

resource "aws_route53_record" "root_domain" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "ALB"
  type    = "A"
  alias {
    name                   = aws_lb.container_alb.dns_name  
    zone_id                = aws_lb.container_alb.zone_id  
    evaluate_target_health = true
  }
}

resource "aws_lb" "container_alb" {
  name               = "container-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.personal_website_public_subnet.id, aws_subnet.personal_website_public_subnet2.id]
  enable_deletion_protection = false
  enable_http2 = true
  ip_address_type = "ipv4"  

}



resource "aws_lb_listener" "front_end_listener" {
  load_balancer_arn = aws_lb.container_alb.arn  # Replace with your ALB ARN
  port              = 80
  protocol          = "HTTP"
    default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.front_end_target_group.arn

   }
}

resource "aws_lb_target_group" "front_end_target_group" {
  name        = "fe-target-group"
  port        = 8081
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.personal_website_vpc.id
}

