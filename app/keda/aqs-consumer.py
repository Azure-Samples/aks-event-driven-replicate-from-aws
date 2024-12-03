import json
import time
import uuid
from datetime import datetime
import os
from os import environ
from azure.storage.queue import QueueClient
from azure.data.tables import TableServiceClient
from azure.identity import DefaultAzureCredential


def check_env():
    if 'AZURE_STORAGE_ACCOUNT_NAME' in os.environ:
        storage_account_name = os.environ['AZURE_STORAGE_ACCOUNT_NAME']
        print (f'Storage accout name {storage_account_name} set from envars')
    else:
        raise ValueError('Environment variable AZURE_STORAGE_ACCOUNT_NAME is missing!')

    if 'AZURE_QUEUE_NAME' in os.environ:
        queue_name = os.environ['AZURE_QUEUE_NAME']
        print (f'Queue name {queue_name} is set from envars')
    else:
        raise ValueError ('Environment variable AZURE_QUEUE_NAME is missing!')

    if 'AZURE_TABLE_NAME' not in os.environ:
        raise ValueError('Environment variable AZURE_TABLE_NAME is missing!')
    else:
        azure_table = os.environ['AZURE_TABLE_NAME']
        print (f'Azure table name {azure_table}')
    return storage_account_name, queue_name, azure_table

def receive_message():
    try:
        print("Start fn receive message")
        #sqs_client = QueueClient.from_connection_string(conn_str=conn_str, queue_name=queue_name)
        creds = DefaultAzureCredential()
        account_url = f"https://{storage_account_name}.queue.core.windows.net"
        aqs_client = QueueClient(account_url=account_url, queue_name=queue_name, credential=creds)

        response = aqs_client.receive_message(visibility_timeout=60)

        print (f'Received queue message {response}')
        message_body = response.content
        receipt_handle = response.pop_receipt
        print (f'Receipt handle: {receipt_handle}')

        save_data(message_body)
        # dequeue the message
        aqs_client.delete_message(response, receipt_handle)
        print("End fn receive message")
    except Exception as ex:
        print(f"Error happened in receive_message : {ex} ")
    finally:
        aqs_client.close()
    
def save_data(_message):
    print(f'save data src msg :{_message}')
    jsonMessage = json.loads(_message)
    print(f'Src Message :{jsonMessage["msg"]},{jsonMessage["srcStamp"]}')

    date_format = '%Y-%m-%d %H:%M:%S.%f'
    current_dateTime = datetime.utcnow().strftime(date_format)

    _id = str(uuid.uuid1())
    print(f"id:{_id}")

    creds = DefaultAzureCredential()
    table = TableServiceClient(
        endpoint=f"https://{storage_account_name}.table.core.windows.net/",  
        credential=creds).get_table_client(table_name=azure_table)
    
    messageProcessingTime = datetime.utcnow() - datetime.strptime(jsonMessage["srcStamp"],date_format) 
    print(f'messageProcessingTime: {messageProcessingTime.total_seconds()}')

    entity={
        'PartitionKey': _id,
        'RowKey': datetime.utcnow().strftime(date_format),
        'data': jsonMessage['msg'],
        'srcStamp': jsonMessage['srcStamp'],
        'dateStamp': current_dateTime
    }
    
    response = table.create_entity(entity=entity)
    print (f"insert_entity response timestamp {str(response)}")

try:
    # create a function to add numbers
    starttime = time.time()
    storage_account_name, queue_name, azure_table = check_env()

    while True:
        t = time.localtime()
        time.sleep(1.0 - ((time.time() - starttime) % 1.0)) #sleep for 1 sec
        currenttime = time.strftime("%H:%M:%S", t)
        print(f"Start SQS Call : {currenttime}")

        receive_message()

        '''i = 0
        while i < 20:
            i = i+1'''
        currenttime = time.strftime("%H:%M:%S", t)
        print(f"End SQS Call {currenttime}")
except ValueError as error:
    print(error)
except Exception as ex:
    print(f"Error happened : {ex} ")

