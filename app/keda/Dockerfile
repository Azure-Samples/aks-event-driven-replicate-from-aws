FROM ubuntu:22.04

RUN apt-get update
RUN apt update

RUN apt install python3 -y
RUN apt install -y python3-pip
RUN pip3 install --upgrade pip
RUN pip3 install azure-storage-queue
RUN pip3 install azure-data-tables
RUN pip3 install azure-identity

WORKDIR /usr/app/src

COPY aqs-consumer.py ./

CMD [ "python3", "./aqs-consumer.py" ]
