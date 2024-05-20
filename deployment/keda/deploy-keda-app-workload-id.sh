#!/bin/bash
#*************************
# Create manifest for the KEDA queue reader app using workload identity
#
# NOTE: Make sure you have run ./deployment/environmentVariables.sh before running this script
#*************************

#cat <<EOF | kubectl apply -f -
cat >>./deployment/keda/keda-python-app.yaml <<EOF
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
        - name: AZURE_COSMOSDB_TABLE
          value: $AZURE_COSMOSDB_TABLE
        - name: AZURE_COSMOSDB_ACCOUNT_NAME
          value: $AZURE_COSMOSDB_ACCOUNT_NAME
        resources:
          requests:
            memory: "64Mi"
            cpu: "250m"
          limits:
            memory: "128Mi"
            cpu: "500m"
EOF