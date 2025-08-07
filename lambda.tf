import {
  id = "WebsiteCounterLambda"
  to = aws_lambda_function.website_counter_lambda
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

import {
  id = "lambda_execution_role"
  to = aws_iam_role.lambda_execution_role
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