#!/bin/bash

# Load environment variables
#. ./deployment/environmentVariables.sh

echo ${YELLOW} "$(date '+%Y-%m-%d %H:%M:%S%:z') Get AKS cluster credentials" ${NC}
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME
if [ $? -ne 0 ]; then
  echo "Failed to get AKS cluster credentials"
  exit 1
fi

# Check if the target namespace exists
echo ${YELLOW} "$(date '+%Y-%m-%d %H:%M:%S%:z') Check if the target namespace exists" ${NC}
if kubectl get namespace $AQS_TARGET_NAMESPACE >/dev/null 2>&1; then
  echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') Namespace $AQS_TARGET_NAMESPACE exists" ${NC}
else
  echo ${YELLOW} "$(date '+%Y-%m-%d %H:%M:%S%:z') Creating $AQS_TARGET_NAMESPACE namespace" ${NC}
  kubectl create namespace $AQS_TARGET_NAMESPACE
  if [ $? -ne 0 ]; then
    echo ${RED} "$(date '+%Y-%m-%d %H:%M:%S%:z') Failed to create namespace $AQS_TARGET_NAMESPACE" ${NC}
    exit 1
  fi
fi


# get the workload identity client id
if [ -z "$WORKLOAD_MANAGED_IDENTITY_NAME" ]; then
  echo "WORKLOAD_MANAGED_IDENTITY_NAME is not set. Make sure you have run deployment/environmentVariables.sh"
  exit 1
else
  if ! az identity show -g $AZURE_RESOURCE_GROUP -n $WORKLOAD_MANAGED_IDENTITY_NAME --query clientId -o tsv >/dev/null; then
    echo "Workload Identity $WORKLOAD_MANAGED_IDENTITY_NAME does not exist in resource group $AZURE_RESOURCE_GROUP. Did you run deployment/all-azure/deploy.sh?"
    exit 1
  else
    echo "Getting workload identity client id for $WORKLOAD_MANAGED_IDENTITY_NAME"
    workloadManagedIdentityClientId=$(az identity show -g $AZURE_RESOURCE_GROUP -n $WORKLOAD_MANAGED_IDENTITY_NAME --query clientId -o tsv)
  fi
fi


echo ${YELLOW} "$(date '+%Y-%m-%d %H:%M:%S%:z') Deploying KEDA scale object using workload ID for auth" ${NC}
#cat >>./deployment/keda/keda-python-app.yaml <<EOF
cat <<EOF | kubectl apply -f -
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: aws2az-queue-scaleobj
  namespace: ${AQS_TARGET_NAMESPACE}
spec:
  scaleTargetRef:
    name: ${AQS_TARGET_DEPLOYMENT}     #K8s deployement to target
  minReplicaCount: 1  # We don't want pods if the queue is empty nginx-deployment
  maxReplicaCount: 15 # We don't want to have more than 15 replicas
  pollingInterval: 30 # How frequently we should go for metrics (in seconds)
  cooldownPeriod:  10 # How many seconds should we wait for downscale  
  triggers:
  - type: azure-queue
    authenticationRef:
      name: keda-az-credentials
    metadata:
      queueName: ${AZURE_QUEUE_NAME}
      accountName: ${AZURE_STORAGE_ACCOUNT_NAME}
      queueLength: '5'
      activationQueueLength: '50' # threshold for when the scaler is active
      cloud: AzurePublicCloud
---
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: keda-az-credentials
  namespace: $AQS_TARGET_NAMESPACE
spec:
  podIdentity:
    provider: azure-workload
    identityId: '${workloadManagedIdentityClientId}'
EOF
