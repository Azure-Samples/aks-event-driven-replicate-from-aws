#!/bin/bash
#
# This script is used to build the Docker image for the AQS Consumer application
# and push it to the Azure Container Registry.
#
# Usage: ./docker-command.sh  Run this script from the root of the project directory
#

. ./deployment/environmentVariables.sh

# Set resource name environment variables based on the deployment state file
while IFS= read -r line; do
  echo "export $line";
  export $line;
done < ./deployment/deploy.state

cd ./app/keda

echo "Logging into Azure Container Registry"
az acr login --name ${AZURE_CONTAINER_REGISTRY_NAME}

#KEDA - Build the image
echo "Building the AQS Consumer Docker image"
docker buildx build -t aqs-consumer --platform=linux/amd64 .
echo "Tagging the AQS Consumer Docker image"
docker tag aqs-consumer:latest ${AZURE_CONTAINER_REGISTRY_NAME}.azurecr.io/aws2azure/aqs-consumer:latest
echo "Pushing the AQS Consumer Docker image"
docker push ${AZURE_CONTAINER_REGISTRY_NAME}.azurecr.io/aws2azure/aqs-consumer:latest

exit 0