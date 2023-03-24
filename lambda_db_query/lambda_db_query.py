
import boto3
from botocore.exceptions import ClientError
import json
import os
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
    data = json.loads(event['body'])
    print(data)
    if data['from_date'] is None:
        print('No From Date')
    else:
        print('From date is %s' % data['from_date'])
        
    to_date = data['to_date']
    from_date = data['from_date']
    agent_id = data['agent_name']
    consumer_number = data['consumer_number']
    
    db_creds = json.loads(get_secret("DatabaseCreds"))
    db_password = db_creds["password"]
    db_user = db_creds["username"]
    db_host = os.environ['DATABASE_HOST']
    db_name = os.environ['DATABASE_NAME']
    db_port = os.environ['DATABASE_PORT']

    conn = psycopg2.connect(user=db_user, password=db_password, host=db_host, database=db_name, port=db_port)
    results = db_query(conn,from_date,to_date,agent_id,consumer_number)
    return_data = {'results':results}
    
    return {
    'statusCode': 200,
    "headers": {
            "Access-Control-Allow-Headers": "Content-Type",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "OPTIONS,POST,GET"
        },
    'body': json.dumps(return_data, indent=4, sort_keys=True, default=str)
    }

def db_query(conn,from_date,to_date,agent_id,consumer_number):
    cur = conn.cursor()
    if consumer_number == '':
        consumer_number = '%'
    else:
        consumer_number = '%'+consumer_number+'%'
    query_string = "SELECT r.recording_url, r.recording_date, a.agent_name, r.consumer_number, r.recording_time FROM recordings r JOIN agents a ON r.agent_id = a.agent_id WHERE r.agent_id = %s AND r.recording_date::date >= %s AND r.recording_date::date <= %s AND r.consumer_number LIKE %s ORDER BY r.recording_date"
    query = cur.mogrify(query_string, (agent_id,from_date,to_date,consumer_number))
    print('Query being executed is %s' % query)
    cur.execute(
        query
        #"SELECT r.recording_url, r.recording_date, a.agent_name, r.consumer_number FROM recordings r JOIN agents a ON r.agent_id = a.agent_id WHERE r.agent_id = %s AND r.recording_date::date >= '%s' AND r.recording_date::date <= '%s' AND r.consumer_number LIKE '%s'" % (agent_id,from_date,to_date,consumer_number)
    )
    results = cur.fetchall()
    return_data = []
    for result in results:
        print(result)
        return_data.append(result)
    return return_data

