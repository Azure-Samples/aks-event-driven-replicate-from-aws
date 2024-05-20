echo "=====Deploy KEDA Scale Object Using WorkloadID for Auth===="

if test -f "./deployment/keda/kedaScaleObject.yaml"; then
  rm ./deployment/keda/kedaScaleObject.yaml
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

cat >>./deployment/keda/kedaScaleObject.yaml <<EOF
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: aws2az-queue-scaleobj
  namespace: ${AQS_TARGET_NAMESPACE}
spec:
  scaleTargetRef:
    name: ${AQS_TARGET_DEPLOYMENT}     #K8s deployement to target
  minReplicaCount: 1  # We don't want pods if the queue is empty nginx-deployment
  maxReplicaCount: 2000  # We don't want to have more than 15 replicas
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
