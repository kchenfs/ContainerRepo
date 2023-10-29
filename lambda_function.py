import json
import boto3

dynamodb = boto3.client('dynamodb')
table_name = 'WebsiteCounterTable'

def lambda_handler(event, context):
    operation = event['httpMethod']
    
    if operation == 'GET':
        counter_value = get_counter()
        response = {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': 'https://web.kchenfs.com',
                'Access-Control-Allow-Methods': 'POST,GET',
                'Access-Control-Allow-Headers': 'Content-Type',
            },
            'body': json.dumps({'CounterValue': counter_value})
        }
        return response
    elif operation == 'POST':
        increment_counter()
        response = {
            'statusCode': 204,
            'headers': {
                'Access-Control-Allow-Origin': 'https://web.kchenfs.com',
                'Access-Control-Allow-Methods': 'POST,GET',
                'Access-Control-Allow-Headers': 'Content-Type',
            },
        }
        return response
    else:
        response = {
            'statusCode': 400,
            'headers': {
                'Access-Control-Allow-Origin': 'https://web.kchenfs.com',
                'Access-Control-Allow-Methods': 'POST,GET',
                'Access-Control-Allow-Headers': 'Content-Type',
            },
            'body': 'Unsupported method'
        }
        return response

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
