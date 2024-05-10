FROM ubuntu:latest

RUN apt-get update
RUN apt update

RUN apt install python3 -y
RUN apt install -y python3-pip
RUN pip3 install --upgrade pip
RUN pip3 install azure-storage-queue
RUN pip3 install azure-cosmosdb-table

WORKDIR /usr/app/src

COPY aqs-consunmer.py ./

CMD [ "python3", "./aqs-consumer.py" ]
