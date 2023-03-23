import boto3
from botocore.exceptions import ClientError
import json
import logging
import os


def lambda_handler(event, context):
    # TODO implement
    bucket_name = os.environ['BUCKET_NAME']
    print(event["body"])
    body = json.loads(event["body"])
    object_name = body["object_name"]
    s3_client = boto3.client('s3')
    try:
        response = s3_client.generate_presigned_url('get_object',
                                                    Params={'Bucket': bucket_name,
                                                            'Key': object_name
                                                    },
                                                    ExpiresIn=500)
    except ClientError as e:
        logging.error(e)
        return None

    # The response contains the presigned URL
    print(response)
    
    
    return {
        "headers": {
            "Access-Control-Allow-Headers": "Content-Type",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "OPTIONS,GET"
        },
        'statusCode': 200,
        'body': response
    }
