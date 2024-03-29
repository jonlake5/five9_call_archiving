import psycopg2
import boto3
from botocore.exceptions import ClientError

def lambda_handler(event, context):
    create_tables()
    return {
        'statusCode': 200,
        'body': 'created database'
    }

def create_tables():
    commands = ("""
                
    CREATE TABLE agents (
        agent_id SERIAL PRIMARY KEY,
        agent_name TEXT NOT NULL
    )
    """,
    """
    CREATE TABLE recordings(
        recording_id SERIAL PRIMARY KEY,
        recording_s3_key TEXT,
        recording_date DATE,
        recording_time TEXT,
        agent_id INT, 
        recording_consumer_number TEXT,
        recording_call_guid TEXT,
        recording_campaign_name TEXT,
        recording_disposition_name TEXT,
        recording_first_name TEXT,
        recording_ivr_module TEXT,
        recording_last_name TEXT,
        recording_length TEXT,
        recording_number_1 TEXT,
        recording_number_2 TEXT,
        recording_number_3 TEXT,
        recording_owner TEXT,
        recording_session_id TEXT,
        recording_skill_name TEXT,
        CONSTRAINT fk_recording_agent
            FOREIGN KEY(agent_id)
                REFERENCES agents(agent_id)
    )
                
    """)
    db_host = get_secret("DatabaseEndpoint")
    db_port = get_secret("DatabasePort")
    db_password = get_secret("DatabaseMasterPassword")
    db_user = get_secret("DatabaseUser")
    db_name = get_secret("DatabaseName")

    
    try:       
        # connect to the PostgreSQL server
        conn = psycopg2.connect(user=db_user, password=db_password, host=db_host, database=db_name, port=db_port)
        cur = conn.cursor()
        # create table one by one
        for command in commands:
            cur.execute(command)
        # close communication with the PostgreSQL database server
        cur.close()
        # commit the changes
        conn.commit()
    except (Exception, psycopg2.DatabaseError) as error:
        print(error)
    finally:
        if conn is not None:
            conn.close()
     
def get_secret(secret_name):   
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

