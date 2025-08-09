import json
import boto3

dynamodb = boto3.resource('dynamodb', region_name='ca-central-1')
table = dynamodb.Table('WebsiteCounterTable')

def lambda_handler(event, context):
    # CORS headers
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
        'Content-Type': 'application/json'
    }
    
    # Handle preflight OPTIONS request
    if event.get('httpMethod') == 'OPTIONS':
        return {
            'statusCode': 200,
            'headers': headers,
            'body': ''
        }
    
    try:
        response = table.update_item(
            Key={
                'CounterID': 'CounterValue'
            },
            UpdateExpression='ADD WebsiteCounter :inc',  # Use ADD for atomic increment
            ExpressionAttributeValues={
                ':inc': 1
            },
            ReturnValues='UPDATED_NEW'
        )
        
        print("This is dynamodb response", response)
        
        # Get the updated counter value
        visit_count = int(response['Attributes']['WebsiteCounter'])
        print("printing, visit count", visit_count)
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({'count': visit_count})
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        print(f"Error: {str(e)}")

        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'error': 'Internal server error'})
        }