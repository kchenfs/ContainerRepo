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