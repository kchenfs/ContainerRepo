# backend/tests/test_lambda_function.py
import json
import pytest
import boto3
from moto.dynamodb import mock_dynamodb
from unittest.mock import patch, MagicMock
import sys
import os

# Add the parent directory to the path so we can import lambda_function
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import lambda_function


class TestLambdaFunction:
    
    @mock_dynamodb
    def setup_method(self):
        """Set up test fixtures before each test method."""
        # Create mock DynamoDB table
        self.dynamodb = boto3.resource('dynamodb', region_name='ca-central-1')
        
        # Create the table
        self.table = self.dynamodb.create_table(
            TableName='WebsiteCounterTable',
            KeySchema=[
                {
                    'AttributeName': 'CounterID',
                    'KeyType': 'HASH'
                }
            ],
            AttributeDefinitions=[
                {
                    'AttributeName': 'CounterID',
                    'AttributeType': 'S'
                }
            ],
            BillingMode='PAY_PER_REQUEST'
        )
        
        # Wait for table to be created
        self.table.wait_until_exists()
        
        # Initialize counter
        self.table.put_item(
            Item={
                'CounterID': 'CounterValue',
                'WebsiteCounter': 0
            }
        )

    @mock_dynamodb
    @patch('lambda_function.table')
    def test_options_request(self, mock_table):
        """Test that OPTIONS requests return proper CORS headers."""
        event = {
            'httpMethod': 'OPTIONS'
        }
        context = {}
        
        response = lambda_function.lambda_handler(event, context)
        
        assert response['statusCode'] == 200
        assert response['headers']['Access-Control-Allow-Origin'] == '*'
        assert response['headers']['Access-Control-Allow-Methods'] == 'GET,POST,OPTIONS'
        assert response['body'] == ''

    @mock_dynamodb
    def test_successful_counter_increment(self):
        """Test successful counter increment."""
        # Mock the table in the lambda function
        with patch('lambda_function.table', self.table):
            event = {
                'httpMethod': 'GET'
            }
            context = {}
            
            response = lambda_function.lambda_handler(event, context)
            
            assert response['statusCode'] == 200
            assert 'count' in json.loads(response['body'])
            
            # Check that counter was incremented
            body = json.loads(response['body'])
            assert body['count'] == 1
            
            # Test second increment
            response2 = lambda_function.lambda_handler(event, context)
            body2 = json.loads(response2['body'])
            assert body2['count'] == 2

    @mock_dynamodb
    def test_cors_headers_in_success_response(self):
        """Test that CORS headers are present in successful responses."""
        with patch('lambda_function.table', self.table):
            event = {
                'httpMethod': 'GET'
            }
            context = {}
            
            response = lambda_function.lambda_handler(event, context)
            
            expected_headers = {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
                'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
                'Content-Type': 'application/json'
            }
            
            for key, value in expected_headers.items():
                assert response['headers'][key] == value

    @mock_dynamodb
    @patch('lambda_function.table')
    def test_dynamodb_error_handling(self, mock_table):
        """Test error handling when DynamoDB fails."""
        # Mock DynamoDB to raise an exception
        mock_table.update_item.side_effect = Exception("DynamoDB error")
        
        event = {
            'httpMethod': 'GET'
        }
        context = {}
        
        response = lambda_function.lambda_handler(event, context)
        
        assert response['statusCode'] == 500
        assert 'error' in json.loads(response['body'])
        assert json.loads(response['body'])['error'] == 'Internal server error'
        
        # Ensure CORS headers are still present in error response
        assert response['headers']['Access-Control-Allow-Origin'] == '*'

    @mock_dynamodb
    def test_counter_atomic_increment(self):
        """Test that the counter increment is atomic using ADD operation."""
        with patch('lambda_function.table', self.table):
            event = {
                'httpMethod': 'POST'
            }
            context = {}
            
            # Simulate multiple concurrent requests
            responses = []
            for i in range(5):
                response = lambda_function.lambda_handler(event, context)
                responses.append(response)
            
            # All should succeed
            for response in responses:
                assert response['statusCode'] == 200
            
            # Final count should be 5
            final_response = lambda_function.lambda_handler(event, context)
            final_count = json.loads(final_response['body'])['count']
            assert final_count == 6  # 5 previous + 1 current

    @mock_dynamodb
    def test_response_format(self):
        """Test that the response format is correct."""
        with patch('lambda_function.table', self.table):
            event = {
                'httpMethod': 'GET'
            }
            context = {}
            
            response = lambda_function.lambda_handler(event, context)
            
            # Check response structure
            assert 'statusCode' in response
            assert 'headers' in response
            assert 'body' in response
            
            # Check body is valid JSON
            body = json.loads(response['body'])
            assert isinstance(body, dict)
            assert 'count' in body
            assert isinstance(body['count'], int)

    @mock_dynamodb
    @patch('lambda_function.table')
    def test_missing_counter_item(self, mock_table):
        """Test behavior when counter item doesn't exist in DynamoDB."""
        # Mock update_item to simulate item not existing initially
        mock_response = {
            'Attributes': {
                'WebsiteCounter': 1
            }
        }
        mock_table.update_item.return_value = mock_response
        
        event = {
            'httpMethod': 'GET'
        }
        context = {}
        
        response = lambda_function.lambda_handler(event, context)
        
        assert response['statusCode'] == 200
        body = json.loads(response['body'])
        assert body['count'] == 1