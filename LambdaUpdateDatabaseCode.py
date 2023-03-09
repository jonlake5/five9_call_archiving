import json

def lambda_handler(event, context):
    # TODO implement
    print('##### EVENT DATA#######')
    print(event)
    s3Message = json.loads(event['Records'][0]['Sns']['Message'])
    s3Object = s3Message['Records'][0]['s3']['object']
    
    print(s3Object)
    return {
        'statusCode': 200,
        'body': json.dumps('Hello from Lambda!')
    }
