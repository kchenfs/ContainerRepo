terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "6.7.0"
    }
  }
}

provider "aws" {
  # Configuration options
  region = var.region
  profile = "default"
  # Configuration options
}


provider "aws" {
  alias   = "us_east_1"
  region  = "us-east-1"
  profile = "default"
}