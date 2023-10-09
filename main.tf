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

# Create an internet gateway
resource "aws_internet_gateway" "personal_website_igw" {
  vpc_id = aws_vpc.personal_website_vpc.id
}


# Existing security group resource
resource "aws_security_group" "security_group_personal_website" {
  name_prefix = "example-"
  vpc_id      = aws_vpc.personal_website_vpc.id # Specify the VPC ID here

  # Ingress rule for HTTP (port 80)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Ingress rule for HTTPS (port 443)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Ingress rule for SSH (port 22) - Allow SSH access only from your IP address
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Restrict SSH access to your specific IP address
  }

}


# Create an ECS Cluster
resource "aws_ecs_cluster" "personal_website_cluster" {
  name = "personal-website-cluster"
}

# Create an IAM role for ECS Fargate execution
resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

# Create an ECS Task Definition
resource "aws_ecs_task_definition" "personal_website_task" {
  family                   = "personal-website"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
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
    "image": "nginx:latest",
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

# Create an ECS Service
resource "aws_ecs_service" "personal_website_service" {
  name             = "personal-website-service"
  cluster          = aws_ecs_cluster.personal_website_cluster.id
  task_definition  = aws_ecs_task_definition.personal_website_task.arn
  launch_type      = "FARGATE"
  platform_version = "LATEST"
  desired_count    = 1
  network_configuration {
    subnets          = [aws_subnet.personal_website_public_subnet.id]
    security_groups  = [aws_security_group.security_group_personal_website.id]
    assign_public_ip = true
  }
}

output "ecs_service_name" {
  value = aws_ecs_service.personal_website_service.name
}


resource "aws_cloudwatch_log_group" "personal_website_log_group" {
  name = "PersonalWebsite"
}

resource "aws_route53_zone" "main" {
  name    = "kchenfs.com"
  comment = "Managed by Terraform"
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
