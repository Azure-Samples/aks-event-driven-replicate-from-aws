#!/bin/bash
echo "Setting environment variables"

#K8s Variables
export K8sversion="1.30"


#KEDA Variables
export NAMESPACE="keda"
export SERVICE_ACCOUNT="aqs-app-service-account"
export AQS_TARGET_DEPLOYMENT="aqs-app"
export AQS_TARGET_NAMESPACE="aqs-demo"

#****************** ADD VALUES FOR THE FOLLOWING ENVIROMENT VARIABLES ***********************
export AZURE_STORAGE_ACCOUNT_NAME="<storage account name>"
export AZURE_QUEUE_NAME="aws2azmsgs"
export AZURE_TABLE_NAME="aws2azpmts"
#********************************************************************************************
export LOCAL_NAME="aksdemo"
export LOCATION="westus3"
export TAGS="owner=aksdemo"
export STORAGE_ACCOUNT_SKU="Standard_LRS"
export ACR_SKU="Basic"
export AKS_NODE_COUNT=3

export MY_IP_ADDRESS=$(curl -s ifconfig.me)

# echo color
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
CYAN=$(tput setaf 6)
BLUE=$(tput setaf 4)
YELLOW=$(tput setaf 3)
MAGENTA=$(tput setaf 5)
NC=$(tput sgr0)
