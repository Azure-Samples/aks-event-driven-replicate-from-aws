
az acr login --name ${AZURE_CONTAINER_REGISTRY_NAME}

#KEDA - Build the image
docker buildx build -t aqs-consumer --platform=linux/amd64 ./app/keda/.
docker tag aqs-consumer:latest ${AZURE_CONTAINER_REGISTRY_NAME}.azurecr.io/aws2azure/aqs-consumer:latest
docker push ${AZURE_CONTAINER_REGISTRY_NAME}.azurecr.io/aws2azure/aqs-consumer:latest