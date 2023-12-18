import json
import boto3

dynamodb = boto3.resource('dynamodb', region_name='ca-central-1')
table = dynamodb.Table('WebsiteCounterTable')

def lambda_handler(event, context):
    response = table.get_item(
        Key = {
            'CounterID':'WebsiteCounter'
        }
    )
    
    visit_count = response['Item']['CounterValue'] 
    visit_count = (int(visit_count) + 1)
    
    response = table.put_item(
        Item = {
            'CounterID':'WebsiteCounter',
            'CounterValue': visit_count
        }
    )

    return {
        'statusCode': 200,
        'headers': {
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST'
        },
        'body': visit_count
    }