
import boto3
from botocore.exceptions import ClientError
import json
import psycopg2




def get_secret(secret_name):

    #secret_name = "DatabaseEndpoint"
    region_name = "us-east-1"

    # Create a Secrets Manager client
    session = boto3.session.Session()
    client = session.client(
        service_name='secretsmanager',
        region_name=region_name
    )

    try:
        get_secret_value_response = client.get_secret_value(
            SecretId=secret_name
        )
    except ClientError as e:
        # For a list of exceptions thrown, see
        # https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_GetSecretValue.html
        raise e

    # Decrypts secret using the associated KMS key.
    secret = get_secret_value_response['SecretString']
    return secret
    # Your code goes here.


def lambda_handler(event, context):

    db_host = get_secret("DatabaseEndpoint")
    db_port = get_secret("DatabasePort")
    db_password = get_secret("MasterDatabaseSecret")
    db_user = get_secret("MasterDatabaseUser")
    db_name = get_secret("DatabaseName")

    connection = psycopg2.connect(user=db_user, password=db_password, host=db_host, database=db_name)


    return {
    'statusCode': 200,
    'body': json.dumps('Hello from Lambda!')
    }


