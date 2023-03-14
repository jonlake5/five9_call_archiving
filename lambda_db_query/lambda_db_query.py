
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
    
    db_host = get_secret("DatabaseEndpoint")
    db_port = get_secret("DatabasePort")
    db_password = get_secret("DatabaseMasterPassword")
    db_user = get_secret("DatabaseUser")
    db_name = get_secret("DatabaseName")

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
    # cur.execute("SELECT * from recordings WHERE agent_id = %s", (agent_id))
    #cur.execute("SELECT recordings.recording_url, recordings.recording_date, agents.agent_name,  recordings.consumer_number FROM recordings JOIN agents ON recordings.agent_id = agents.agent_id")
    cur.execute(
        "SELECT r.recording_url, r.recording_date, a.agent_name, r.consumer_number FROM recordings r JOIN agents a ON r.agent_id = a.agent_id WHERE r.agent_id = %s" % (agent_id)
    )
    results = cur.fetchall()
    return_data = []
    for result in results:
        print(result)
        return_data.append(result)
    return return_data

