import json
import boto3

dynamodb = boto3.client('dynamodb')
table_name = 'WebsiteCounterTable'

def lambda_handler(event, context):
    operation = event['httpMethod']
    
    if operation == 'GET':
        counter_value = get_counter()
        return {
            'statusCode': 200,
            'body': json.dumps({'CounterValue': counter_value})
        }
    elif operation == 'POST':
        increment_counter()
        return {
            'statusCode': 204
        }
    else:
        return {
            'statusCode': 400,
            'body': 'Unsupported method'
        }

def get_counter():
    response = dynamodb.get_item(
        TableName=table_name,
        Key={'CounterID': {'S': 'WebsiteCounter'}}
    )
    item = response.get('Item', {'CounterValue': {'N': '0'}})
    return int(item['CounterValue']['N'])

def increment_counter():
    dynamodb.update_item(
        TableName=table_name,
        Key={'CounterID': {'S': 'WebsiteCounter'}},
        UpdateExpression='SET CounterValue = CounterValue + :val',
        ExpressionAttributeValues={':val': {'N': '1'}}
    )
