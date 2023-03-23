
import boto3
from botocore.exceptions import ClientError
import json
import psycopg2
import os
import urllib.parse


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
    s3Message = json.loads(event['Records'][0]['Sns']['Message'])
    s3Node = s3Message['Records'][0]['s3']
    s3Object = s3Message['Records'][0]['s3']['object']
    s3Record = s3Message['Records'][0]
    file_name = s3Object['key'].replace('+',' ')
    print("Here is S3 Record %s" % s3Record)
    ##File format is agentName_callingNumber_date_time.wav
    # bucket_name = s3Node['bucket']['name']
    ## region = s3Record['awsRegion']
    # url = generate_url(file_name,bucket_name,region)
    (agent_name,consumer_number,recording_date,time) = parse_file(file_name)
    print(agent_name)
    
    conn = database_connection()
    update_database(conn,agent_name,file_name,recording_date,consumer_number,time)
    conn.close()
    return {
    'statusCode': 200,
    'body': json.dumps('Hello from Lambda!')
    }

def parse_file(file_name):
    file_string = os.path.splitext(file_name)[0]
    file_string = file_string.replace('+', ' ')
    return file_string.split('_')

def generate_url(key,bucket_name,region):
    url = "https://%s.s3.%s.amazonaws.com/%s" % (
        bucket_name,
        region,
        urllib.parse.quote(key, safe="~()*!.'"),
    )
    #print(url)
    return key

def database_connection():
    db_host = get_secret("DatabaseEndpoint")
    db_port = get_secret("DatabasePort")
    db_password = get_secret("DatabaseMasterPassword")
    db_user = get_secret("DatabaseUser")
    db_name = get_secret("DatabaseName")
    return psycopg2.connect(user=db_user, password=db_password, host=db_host, database=db_name, port=db_port)

def update_database(conn,agent_name,url,recording_date,consumer_number,time):
    agent_id = get_agent_id(conn,agent_name)
    print("Found agent_id: %s" % agent_id)
    print('#### Update database ####')
    print(agent_id,agent_name,url,recording_date,consumer_number)
    
    cur = conn.cursor()
    cur.execute("INSERT INTO recordings (recording_url,recording_date,agent_id,consumer_number,recording_time) VALUES ('%s','%s','%s','%s','%s')" % (url,recording_date,agent_id,consumer_number,time))
    conn.commit()
    cur.close()
        
def get_agent_id(conn,agent_name):
    print("entered get_agent_id")
    cur = conn.cursor()
    check_agent_exists = agent_exists(conn,agent_name)
    print("check_agent_exists -> %s", check_agent_exists)
    if check_agent_exists[0]:
        agent_id = check_agent_exists[1]
        cur.close()
        return agent_id
    else:
        cur.close()
        agent_id = create_and_return_agent(conn,agent_name)
        return agent_id
              
def create_and_return_agent(conn,input_agent_name):
    cur = conn.cursor()
    print("Inserting %s into database" % input_agent_name)
    print(input_agent_name.__class__)
    cur.execute("INSERT INTO agents (agent_name) VALUES ('%s') RETURNING agent_id" % (str(input_agent_name)))
    conn.commit()
    agent_id = cur.fetchone()[0]
    cur.close()
    return agent_id

def agent_exists(conn,input_agent_name):
    cur = conn.cursor()
    cur.execute("SELECT agent_id FROM agents WHERE agent_name LIKE '%s';" % input_agent_name)
    if cur.rowcount == 1:
        agent_id = cur.fetchone()[0]
        print(agent_id)
        cur.close()
        return (True,agent_id)
    else:
        cur.close()
        return (False,0)
        


