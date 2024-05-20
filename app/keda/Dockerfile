FROM ubuntu:latest

RUN apt-get update
RUN apt update

RUN apt install python3 -y
RUN apt install -y python3-pip
RUN pip3 install --upgrade pip --break-system-packages
RUN pip3 install azure-storage-queue --break-system-packages
RUN pip3 install azure-cosmosdb-table --break-system-packages

WORKDIR /usr/app/src

COPY aqs-consumer.py ./

CMD [ "python3", "./aqs-consumer.py" ]
