resource "aws_dynamodb_table" "website_counter" {
  name         = "WebsiteCounterTable"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "CounterID"

  attribute {
    name = "CounterID"
    type = "S" #
  }
}