#!/bin/bash
#*************************
# Create manifest for the KEDA queue reader app using workload identity
#
# NOTE: Make sure you have run ./deployment/environmentVariables.sh before running this script
#*************************

# Load environment variables
. ./deployment/environmentVariables.sh

# Set resource name environment variables based on the deployment state file
while IFS= read -r line; do
  echo "export $line";
  export $line;
done < ./deployment/deploy.state

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

echo ${YELLOW} "$(date '+%Y-%m-%d %H:%M:%S%:z') Deploying app" ${NC}
#cat >>./deployment/keda/keda-python-app.yaml <<EOF
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $AQS_TARGET_DEPLOYMENT
  namespace: $AQS_TARGET_NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: aqs-reader
  template:
    metadata:
      labels:
        app: aqs-reader
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: $SERVICE_ACCOUNT
      containers:
      - name: keda-queue-reader
        image: ${AZURE_CONTAINER_REGISTRY_NAME}.azurecr.io/aws2azure/aqs-consumer
        imagePullPolicy: Always
        env:
        - name: AZURE_QUEUE_NAME
          value: $AZURE_QUEUE_NAME
        - name: AZURE_STORAGE_ACCOUNT_NAME
          value: $AZURE_STORAGE_ACCOUNT_NAME
        - name: AZURE_TABLE_NAME
          value: $AZURE_TABLE_NAME
        resources:
          requests:
            memory: "64Mi"
            cpu: "250m"
          limits:
            memory: "128Mi"
            cpu: "500m"
      tolerations:
      - key: deployment
        operator: Equal
        value: $AQS_TARGET_DEPLOYMENT-pool
        effect: NoSchedule
EOF

if [ $? -ne 0 ]; then
  echo ${RED} "$(date '+%Y-%m-%d %H:%M:%S%:z') Failed to deploy app" ${NC}
  exit 1
fi

echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') App deployed successfully" ${NC}
exit 0