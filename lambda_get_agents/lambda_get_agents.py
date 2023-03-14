
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



def lambda_handler(event, context):

    db_host = get_secret("DatabaseEndpoint")
    db_port = get_secret("DatabasePort")
    db_password = get_secret("DatabaseMasterPassword")
    db_user = get_secret("DatabaseUser")
    db_name = get_secret("DatabaseName")

    conn = psycopg2.connect(user=db_user, password=db_password, host=db_host, database=db_name, port=db_port)
    results = db_query(conn)
    return_data = []
    for result in results:
        return_data.append({'agent_id': result[0],'agent_name': result[1] })
        
    print(return_data)
    return_json = {'agents': return_data}
    print(return_json)
    return {
    'statusCode': 200,
    "headers": {
            "Access-Control-Allow-Headers": "Content-Type",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "OPTIONS,POST,GET"
        },
    'body': json.dumps(return_json)
    }


def db_query(conn):
    cur = conn.cursor()
    cur.execute("SELECT agent_id,agent_name from agents")
    results = cur.fetchall()
    print(results)
    return results

