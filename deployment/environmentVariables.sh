#!/bin/bash
echo "Setting environment variables"


#K8s Variables
export CLUSTER_NAME="aks-cluster"
export K8sversion="1.28"

#Karpenter Variables
export KARPENTER_VERSION=v0.32.0

#KEDA Variables
export NAMESPACE=keda
export SERVICE_ACCOUNT=keda-service-account
export AQS_TARGET_DEPLOYMENT="aqs-app"
export AQS_TARGET_NAMESPACE="keda-test"

#****************** ADD VALUES FOR THE FOLLOWING ENVIROMENT VARIABLES ***********************
export AZURE_STORAGE_ACCOUNT_NAME="<storage account name>"
# export AZURE_STORAGE_ACCOUNT_KEY="<storage account key>"
# export AZURE_STORAGE_CONNECTION_STRING="<storage account connection string>"
export AZURE_QUEUE_NAME="aws2azmsgs"
# export AZURE_COSMOSDB_CONNECTION_STRING="<cosmosdb connection string>"
export AZURE_COSMOSDB_ACCOUNT_NAME="<cosmosdb account name>"
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
