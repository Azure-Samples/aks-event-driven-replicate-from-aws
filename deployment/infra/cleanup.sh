#!/bin/bash

# Remove the resources -- will clean up the resources created by the deployment script
# as defined in the ./deployment/deploy.state file.

# Run this script from the root of the project directory.

while IFS= read -r line; do \
  echo "export $line"; \
  export $line;
done < ./deployment/deploy.state

echo "Deleting resources..."
az group delete --name $RESOURCE_GROUP --yes --no-wait