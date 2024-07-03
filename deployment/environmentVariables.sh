#!/bin/bash
echo "Setting environment variables"

#K8s Variables
export K8sversion="1.28"

#Karpenter Variables
export KARPENTER_VERSION=v0.32.0

#KEDA Variables
export NAMESPACE="keda"
export SERVICE_ACCOUNT="aqs-app-service-account"
export AQS_TARGET_DEPLOYMENT="aqs-app"
export AQS_TARGET_NAMESPACE="aqs-demo"

#****************** ADD VALUES FOR THE FOLLOWING ENVIROMENT VARIABLES ***********************
export AZURE_QUEUE_NAME="aws2azmsgs"
export AZURE_TABLE_NAME="aws2azpmts"
export AZURE_COSMOSDB_TABLE="aws2azpmts"
#********************************************************************************************
export LOCAL_NAME="aksdemo"
export LOCATION="westus"
export TAGS="owner=aksdemo"
export STORAGE_ACCOUNT_SKU="Standard_LRS"
export ACR_SKU="Basic"
export AKS_NODE_COUNT=3

# echo color
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
CYAN=$(tput setaf 6)
BLUE=$(tput setaf 4)
YELLOW=$(tput setaf 3)
MAGENTA=$(tput setaf 5)
NC=$(tput sgr0)
