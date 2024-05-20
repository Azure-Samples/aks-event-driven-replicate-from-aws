import json
import time
from datetime import datetime, timedelta
import os
from os import environ
import subprocess
from azure.storage.queue import QueueClient, QueueServiceClient
from azure.identity import DefaultAzureCredential


def send_message(message_body):

    print("Start fn send message")
    accountUrl = f"https://{os.environ['AZURE_STORAGE_ACCOUNT_NAME']}.queue.core.windows.net"
    queue_name = os.environ["AZURE_QUEUE_NAME"]


    creds = DefaultAzureCredential()
    aqs_client = QueueClient(accountUrl, queue_name, credential=creds)
    response = aqs_client.send_message(message_body)
    print(f"messages send: {response}")
    print("End fn send message")
    aqs_client.close()


starttime = time.time()
i = 0

if (
    "AZURE_STORAGE_ACCOUNT_NAME" in os.environ
    and "AZURE_QUEUE_NAME" in os.environ
):
    try:
        while True:
            t = time.localtime()
            time.sleep(1.0 - ((time.time() - starttime) % 1.0))
            currenttime = time.strftime("%H:%M:%S", t)
            print(f"Start ASQ call : {currenttime}")

            i = i + 1
            date_format = "%Y-%m-%d %H:%M:%S.%f"
            current_dateTime = datetime.utcnow().strftime(date_format)
            messageBody = {
                "msg": f"Scale Buddy !!! : COUNT {i}",
                "srcStamp": current_dateTime,
            }
            print(json.dumps(messageBody))
            send_message(json.dumps(messageBody))
            currenttime = time.strftime("%H:%M:%S", t)
            print(f"End ASQ call {currenttime}")
    except Exception as e:
        print(f"Error: {e}")
else:
    print(
        "Azure Storage Account name is missing from environment. Run environmentVariables.sh first "
    )
