import boto3
from botocore.exceptions import ClientError
import json
import psycopg2
import os
from psycopg2.extensions import AsIs
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

    # Decrypts secret using the associated KMS key.len
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
    # (agent_name,consumer_number,recording_date,time) = parse_file(file_name)
    #File format should be(agent_name,consumer_number,recording_date,time,call_guid,campaign_name,disposition_name,first_name,
    #ivr_module,last_name,length,number_1,number_2,number_3,owner,session_id,skill_name) = parse_file(file_name)
    #print(agent_name)
    output_dict = parse_file(file_name)
    print(output_dict)
    conn = database_connection()
    update_database(conn,output_dict)
    conn.close()
    return {
    'statusCode': 200,
    'body': json.dumps('Hello from Lambda!')
    }

def parse_file(file_name):
    file_string = os.path.splitext(file_name)[0]
    file_string = file_string.replace('+', ' ')
    fields = ["agent_id","recording_consumer_number","recording_date",
              "recording_time","recording_call_guid","recording_campaign_name",
              "recording_disposition_name","recording_first_name",
              "recording_ivr_module","recording_last_name","recording_length",
              "recording_number_1","recording_number_2","recording_number_3",
              "recording_owner","recording_session_id","recording_skill_name"]
    values = file_string.split('__')
    if len(fields) != len(values):
        raise Exception("The number of fields in the file did not line up with the number of defined fields.\n \
              %s fields found in %s.\n %s fields expected" % (len(values),file_string,len(fields))
            )
    output_dict = {}
    index = 0
    for field in fields:
        output_dict[field] = values[index]
        index = index + 1
    ##Add the S3 Key to the dict
    output_dict["recording_s3_key"] = file_name
    return output_dict


def database_connection():
    db_creds = json.loads(get_secret("DatabaseCreds"))
    db_password = db_creds["password"]
    db_user = db_creds["username"]
    db_host = os.environ['DATABASE_HOST']
    db_name = os.environ['DATABASE_NAME']
    db_port = os.environ['DATABASE_PORT']
    return psycopg2.connect(user=db_user, password=db_password, host=db_host, database=db_name, port=db_port)

def update_database(conn,update_dict):
    update_dict["agent_id"] = get_agent_id(conn,update_dict["agent_id"])
    print("Found agent_id: %s" % update_dict["agent_id"])
    print('#### Update database ####')
    # print(agent_id,agent_name,url,recording_date,consumer_number)
    print(update_dict)
    
    columns = update_dict.keys()
    values = update_dict.values()
    insert_statement = 'insert into recordings (%s) values %s'

    cur = conn.cursor()
    query = cur.mogrify(insert_statement, (AsIs(','.join(columns)), tuple(values)))
    cur.execute(query)
    # cur.execute("INSERT INTO recordings (recording_url,recording_date,agent_id,consumer_number,recording_time) VALUES ('%s','%s','%s','%s','%s')" % (url,recording_date,agent_id,consumer_number,time))
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
        


