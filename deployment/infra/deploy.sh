#!/bin/bash

# We assume the script is being run from the root of the repository
#
echo "$(date '+%Y-%m-%d %H:%M:%S%:z')  Starting deployment..."

# make sure we have environment variables set
source ./deployment/environmentVariables.sh

#
# IMPORTANT= Make sure to run ./deployment/environmentVariables.sh BEFORE running this script
#
# Required Environment Variables=
# - RESOURCE_GROUP= Name of the resource group
# - LOCATION= Location of the resource group
# - KEY_VAULT_NAME= Name of the key vault
# - AZURE_STORAGE_ACCOUNT_NAME= Name of the storage account
# - STORAGE_ACCOUNT_SKU= SKU of the storage account
# - STORAGE_ACCOUNT_KIND= Kind of the storage account
# - AZURE_CONTAINER_REGISTRY_NAME= Name of the Azure Container Registry
# - ACR_SKU= SKU of the Azure Container Registry
# - AKS_MANAGED_IDENTITY_NAME= Name of the user assigned managed identity
# - AKS_CLUSTER_NAME= Name of the Azure Kubernetes Service cluster
# - AKS_NODE_COUNT= Number of nodes in the AKS cluster
# - SUBSCRIPTION_ID= ID of the Azure subscription
# - TAGS= Tags to be applied to the resources
# - WORKLOAD_MANAGED_IDENTITY_NAME= Name of the workload identity
# - SERVICE_ACCOUNT= Name of the service account
# - FEDERATED_IDENTITY_CREDENTIAL_NAME= Name of the federated identity credential
# - COSMOSDB_ACCOUNT_NAME= The name of the Azure Cosmos DB account
# - COSMOSDB_DATABASE_NAME= The name of the Azure Cosmos DB database
# - COSMOSDB_CONTAINER_NAME= The name of the Azure Cosmos DB container

# Create a state for the deployment -- so we can clean it up later
if [ -f ./deployment/deploy.state ]; then
    echo ${YELLOW} "Detected a deployment state file. Overwriting..."
    rm -f ./deployment/deploy.state
fi

# Testing remove this later
# Use this suffix on the storage account name if a new storage account is created
export SUFFIX=$(
    tr -dc A-Za-z0-9 </dev/urandom | head -c 6
    echo
)
# Save the suffix to the deployment state file
echo "SUFFIX=$SUFFIX" >>./deployment/deploy.state

# Check if jq is installed
if ! command -v jq &>/dev/null; then
    echo "The command jq cannot be found. Please install jq to run this script. Exiting..."
    exit 1
fi

# Check if user is logged in
if ! az account show &>/dev/null; then
    echo ${RED} "User or app is not logged into Azure. Exiting..."
    exit 1
fi
az account show --output json | jq -r '. | {AccountID: .id, SubscriptionName: .name, UserName: .user.name}'
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)

# Check if aks-preview extension is installed
if ! az extension show --name aks-preview &>/dev/null; then
    echo ${RED} "$(date '+%Y-%m-%d %H:%M:%S%:z') aks-preview extension is not installed. Please install it using the following command=" ${NC}
    echo ${YELLOW} "az extension add --name aks-preview --version <version>" ${NC}
    exit 1
fi

# Check if NodeAutoProvisioningPreview feature is already enabled
if ! az feature show --namespace "Microsoft.ContainerService" --name "NodeAutoProvisioningPreview" --subscription "$SUBSCRIPTION_ID" --query "properties.state" --output tsv | grep -q "Registered"; then
    # Register the NodeAutoProvisioningPreview feature flag
    az feature register --namespace "Microsoft.ContainerService" --name "NodeAutoProvisioningPreview"

    # Wait for the feature registration to complete
    status=""
    timeout=60
    start_time=$(date +%s)
    while true; do
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        if [ $elapsed_time -ge $timeout ]; then
            echo "Unable to register NodeAutoProvisioningPreview feature. Exiting..."
            exit 1
        fi

        status=$(az feature show --namespace "Microsoft.ContainerService" --name "NodeAutoProvisioningPreview" --subscription "$SUBSCRIPTION_ID" --query "properties.state" --output tsv | tr '[=upper=]' '[=lower=]')
        if [ "$(echo "$status" | tr '[=upper=]' '[=lower=]')" = "registered" ]; then
            break
        else
            sleep 5
        fi
    done

    # Refresh the registration of the Microsoft.ContainerService resource provider
    az feature register --namespace "Microsoft.ContainerService" --name "NodeAutoProvisioningPreview"
else
    echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') NodeAutoProvisioningPreview feature is already registered."
fi

export RESOURCE_GROUP="rg-aksdemo-${SUFFIX}"
# Create a resource group
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --tags "$TAGS"
if [ $? == 0 ]; then 
    echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') Resource group $RESOURCE_GROUP created successfully." ${NC}

else 
    echo ${RED} "$(date '+%Y-%m-%d %H:%M:%S%:z') Resource group $RESOURCE_GROUP creation failed." ${NC}
    exit 1

fi


echo "RESOURCE_GROUP=${RESOURCE_GROUP}" >>./deployment/deploy.state

# Generate storage account
export AZURE_STORAGE_ACCOUNT_NAME="storaksdemo${SUFFIX,,}"
echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') Creating storage account $AZURE_STORAGE_ACCOUNT_NAME in resource group $RESOURCE_GROUP" ${NC}
if ! az storage account show --name "$AZURE_STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    # Generate storage account
    az storage account create --name "$AZURE_STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" --sku "$STORAGE_ACCOUNT_SKU"
    if [ $? -eq 0 ]; then  
        echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') Storage account $AZURE_STORAGE_ACCOUNT_NAME created successfully." ${NC}
     
    else 
        echo ${RED} "$(date '+%Y-%m-%d %H:%M:%S%:z') Storage account $AZURE_STORAGE_ACCOUNT_NAME creation failed." ${NC}
        exit 1
    
    fi
else
    echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') Storage account $AZURE_STORAGE_ACCOUNT_NAME already exists."
fi
echo "AZURE_STORAGE_ACCOUNT_NAME=${AZURE_STORAGE_ACCOUNT_NAME}" >>./deployment/deploy.state

# Create a storage queue
if ! az storage queue exists --name "$AZURE_QUEUE_NAME" --account-name "$AZURE_STORAGE_ACCOUNT_NAME" &>/dev/null; then
    az storage queue create --name "$AZURE_QUEUE_NAME" --account-name "$AZURE_STORAGE_ACCOUNT_NAME"
    if [ $? -eq 0 ]; then
        echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') Storage queue $AZURE_QUEUE_NAME created successfully." ${NC}
    else
        echo ${RED} "$(date '+%Y-%m-%d %H:%M:%S%:z') Storage queue $AZURE_QUEUE_NAME creation failed." ${NC}
        exit 1
    fi
else
    echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') Storage queue $AZURE_QUEUE_NAME already exists."
fi
# Shouldn't need this part since we are using workload identity for accessing reseources.
#
# # Create Azure Key Vault
# export KEY_VAULT_NAME="kv-aksdemo-${SUFFIX}"
# keyVaultResourceId=$(az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" --query id --output tsv)
# if [ -z "$keyVaultResourceId" ]; then
#     echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') Creating Azure Key Vault ${KEY_VAULT_NAME} in resource group ${KEYVAULT_RG_NAME}" ${NC}
#     az keyvault create --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" --location "$LOCATION" --enable-rbac-authorization true
#     if [ $? -eq 0 ]; then
#         echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') Key vault $KEY_VAULT_NAME created successfully." ${NC}
    
#     else
#         echo ${RED} "$(date '+%Y-%m-%d %H:%M:%S%:z') Key vault $KEY_VAULT_NAME creation failed." ${NC}
#         exit 1
#     fi
# else
#     echo ${YELLOW} "$(date '+%Y-%m-%d %H:%M:%S%:z') Key vault $KEY_VAULT_NAME already exists."
# fi
# echo "KEY_VAULT_NAME=${KEY_VAULT_NAME}" >>./deployment/deploy.state
# keyVaultResourceId=$(az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" --query id --output tsv)

# # Assign Key Vault Administrator role to the object id of the principal running the script.
# # This is required to create secrets in the key vault.
# if az account show --query "user.type" --output tsv | grep -q "servicePrincipal"; then
#     principalObjectId=$(az ad sp show --id $(az account show --query "user.name" --output tsv) --query id --output tsv)
#     principalType="ServicePrincipal"
# elif az account show --query "user.type" --output tsv | grep -q "managedIdentity"; then
#     principalObjectId=$(az ad sp show --id $(az account show --query "user.name" --output tsv) --query id --output tsv)
#     principalType="ServicePrincipal"
# else
#     principalObjectId=$(az ad signed-in-user show --query id --output tsv)
#     principalType="User"
# fi

# roleAssignment=$(az role assignment list --assignee "$principalObjectId" --scope $keyVaultResourceId --query "[?roleDefinitionName=='Key Vault Administrator']" --output json)
# if [ -z "$roleAssignment" ]; then
#     az role assignment create --assignee-object-id $principalObjectId --role "Key Vault Administrator" --scope $keyVaultResourceId --assignee-principal-type $principalType

#     # Validate role assignment propagation and wait if not propagated
#     roleAssignmentValidated=false
#     maxWaitTime=60
#     currentWaitTime=0

#     while [ $currentWaitTime -lt $maxWaitTime ]; do
#         roleAssignment=$(az role assignment list --assignee "$principalObjectId" --scope $keyVaultResourceId --query "[?roleDefinitionName=='Key Vault Administrator']" --output json)

#         if [ -n "$roleAssignment" ]; then
#             roleAssignmentValidated=true
#             break
#         else
#             sleep 5
#             currentWaitTime=$((currentWaitTime + 5))
#         fi
#     done
#     #TODO - Save role assignment to deployment state file
# else
#     echo ${YELLOW} "The principal with object ID $principalObjectId is already assigned the 'Key Vault Administrator' role to the key vault." ${NC}
# fi

# Shouldn't need this part since we are using workload identity for accessing reseources.
#
# Check if Storage Account PrimaryAccessKey secret exists in the key vault
# if ! az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name "$AZURE_STORAGE_ACCOUNT_NAME-PrimaryAccessKey" &>/dev/null && ! az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name "$AZURE_STORAGE_ACCOUNT_NAME-SecondaryAccessKey" &>/dev/null; then
#     # Extract primary and secondary storage account keys
#     storageAccountKeys=$(az storage account keys list --account-name "$AZURE_STORAGE_ACCOUNT_NAME" --resource-group "$STORAGE_RG_NAME" --output json)
#     primaryAccessKey=$(echo "$storageAccountKeys" | jq -r '.[0].value')
#     secondaryAccessKey=$(echo "$storageAccountKeys" | jq -r '.[1].value')

#     # Create secrets in the key vault for accessing the storage account
#     az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "$AZURE_STORAGE_ACCOUNT_NAME-PrimaryAccessKey" --value "$primaryAccessKey"
#     az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "$AZURE_STORAGE_ACCOUNT_NAME-SecondaryAccessKey" --value "$secondaryAccessKey"
# else
#     echo "Secrets 'PrimaryAccessKey' and 'SecondaryAccessKey' already exist in the key vault."
# fi

# Create Azure Container Registry
echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') Creating Azure Container Registry" ${NC}
export AZURE_CONTAINER_REGISTRY_NAME="acr${LOCAL_NAME,,}${SUFFIX,,}"
az acr create --name "$AZURE_CONTAINER_REGISTRY_NAME" --resource-group "$RESOURCE_GROUP" --sku "$ACR_SKU" --query "id" --output tsv
if [ $? -eq 0 ]; then
    echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') Azure Container Registry $AZURE_CONTAINER_REGISTRY_NAME created successfully." ${NC}
else
    echo ${RED} "$(date '+%Y-%m-%d %H:%M:%S%:z') Azure Container Registry $AZURE_CONTAINER_REGISTRY_NAME creation failed." ${NC}
    exit 1
fi

acrResourceId=$(az acr show --name "$AZURE_CONTAINER_REGISTRY_NAME" --resource-group "$RESOURCE_GROUP" --query "id" --output tsv)
echo "AZURE_CONTAINER_REGISTRY_NAME=${AZURE_CONTAINER_REGISTRY_NAME}" >>./deployment/deploy.state

# Shouldn't need this because we are going to connect the ACR to the AKS cluster using managed identity
#
# Check if the keyvault contains the service principal id
# and password for the Azure Container Registry. If they are missing, create them.
# if ! az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name "$AZURE_CONTAINER_REGISTRY_NAME-service-principal-id" &>/dev/null && ! az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name "$AZURE_CONTAINER_REGISTRY_NAME-sp-secret" &>/dev/null; then
#     ./deployment/cluster/create-acr-sp.sh "$AZURE_CONTAINER_REGISTRY_NAME" "$KEY_VAULT_NAME"
# else
#     echo "Secrets 'service-principal-id' and 'sp-secret' already exist in the key vault."
# fi

# Create User Assigned Managed Identity for the AKS cluster identity
export AKS_MANAGED_IDENTITY_NAME="mi-${LOCAL_NAME}-${SUFFIX}"
managedIdentity=$(az identity show --name "$AKS_MANAGED_IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" --output json)
if [ -z "$managedIdentity" ] || [ -z "${managedIdentity+x}" ]; then
    managedIdentity=$(az identity create --name "$AKS_MANAGED_IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" --output json)
    if [ $? -eq 0 ]; then
        echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') AKS user assigned managed identity $AKS_MANAGED_IDENTITY_NAME created successfully." ${NC}
    else
        echo ${RED} "$(date '+%Y-%m-%d %H:%M:%S%:z') AKS user assigned managed identity $AKS_MANAGED_IDENTITY_NAME creation failed." ${NC}
        exit 1
    fi
else
    echo "AKS user assigned managed identity $AKS_MANAGED_IDENTITY_NAME already exists."
fi
echo "AKS_MANAGED_IDENTITY_NAME=${AKS_MANAGED_IDENTITY_NAME}" >>./deployment/deploy.state

managedIdentityObjectId=$(echo "$managedIdentity" | jq -r '.principalId')
managedIdentityResourceId=$(echo "$managedIdentity" | jq -r '.id')

# Shouldn't need this because we are going to connect the ACR to the AKS cluster using managed identity
#
# Assign AcrPull role to the User Assigned Managed Identity for the Azure Container Registry
# roleAssignment=$(az role assignment list --assignee "$managedIdentityObjectId" --scope "$acrResourceId" --query "[?roleDefinitionName=='AcrPull']" --output json)
# if [ -z "$roleAssignment" ]; then
#     az role assignment create --assignee-object-id "$managedIdentityObjectId" --role "AcrPull" --scope "$acrResourceId" --assignee-principal-type ServicePrincipal
# else
#     echo "The managed identity with object ID $managedIdentityObjectId already has the 'AcrPull' role assigned to the Azure Container Registry."
# fi

# Grant the managed identity access to the ACR -- using assignee-principal-type and assignee-object-id to avoid calling the Grpah API
# acrResourceId=$(az acr show --name "$AZURE_CONTAINER_REGISTRY_NAME" --resource-group "$RESOURCE_GROUP" --query "id" --output tsv)

# Grant the managed identity access to the ACR
az role assignment create --assignee-object-id "$managedIdentityObjectId" --assignee-principal-type "ServicePrincipal" --role acrpull --scope "$acrResourceId"
if [ $? -eq 0 ]; then
    echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') Managed identity $AKS_MANAGED_IDENTITY_NAME granted access to Azure Container Registry $AZURE_CONTAINER_REGISTRY_NAME." ${NC}
else 
    echo ${RED} "$(date '+%Y-%m-%d %H:%M:%S%:z') Failed to grant access to Azure Container Registry $AZURE_CONTAINER_REGISTRY_NAME for managed identity $AKS_MANAGED_IDENTITY_NAME." ${NC}
    exit 1
fi

# Create AKS cluster
export AKS_CLUSTER_NAME="aks-${LOCAL_NAME}-${SUFFIX}"
echo "$(date '+%Y-%m-%d %H:%M:%S%:z') Creating AKS cluster..."
# Create Azure Kubernetes Service cluster
az aks create --tags "$TAGS" --name "$AKS_CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --enable-keda --enable-managed-identity \
 --assign-identity $managedIdentityResourceId --node-provisioning-mode Auto --network-plugin azure --network-plugin-mode overlay \
 --network-dataplane cilium --node-count "$AKS_NODE_COUNT" --enable-oidc-issuer --generate-ssh-keys \
 --attach-acr "$AZURE_CONTAINER_REGISTRY_NAME" --enable-addons monitoring --kubernetes-version "$K8sversion" \
 --node-resource-group "MC_${AKS_CLUSTER_NAME}_$(date '+%Y%m%d%H%M%S')" --tags $TAGS
if [ $? -eq 0 ]; then
    echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') AKS cluster $AKS_CLUSTER_NAME created successfully." ${NC}
else
    echo ${RED} "$(date '+%Y-%m-%d %H:%M:%S%:z') AKS cluster $AKS_CLUSTER_NAME creation failed." ${NC}
    exit 1
fi

# Add a new system node pool to the AKS cluster 
# that is tainted so no application pods are scheduled on it
echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') Adding system node pool with taint to the AKS cluster..." ${NC}
az aks nodepool add \
    --resource-group ${RESOURCE_GROUP} \
    --cluster-name ${AKS_CLUSTER_NAME} \
    --name systempool \
    --node-count 3 \
    --node-taints CriticalAddonsOnly=true:NoSchedule \
    --mode System
if [ $? -eq 0 ]; then
    echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') System node pool added successfully." ${NC}
else
    echo ${RED} "$(date '+%Y-%m-%d %H:%M:%S%:z') System node pool addition failed." ${NC}
    exit 1
fi

# Now delete the default nodepool so only system node pools with the taints are available
echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') Deleting default node pool from the AKS cluster..." ${NC}
az aks nodepool delete \
    --resource-group ${RESOURCE_GROUP} \
    --cluster-name ${AKS_CLUSTER_NAME} \
    --name nodepool1
if [ $? -eq 0 ]; then
    echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') Default node pool deleted successfully." ${NC}
else
    echo ${RED} "$(date '+%Y-%m-%d %H:%M:%S%:z') Default node pool deletion failed." ${NC}
    exit 1
fi

# Add a new user node pool to the AKS cluster 
# only application pods are scheduled on it
echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') Adding application node pool with taint to the AKS cluster..." ${NC}
az aks nodepool add \
    --resource-group ${RESOURCE_GROUP} \
    --cluster-name ${AKS_CLUSTER_NAME} \
    --name appnodepool \
    --node-count 3 \
    --node-taints CriticalAddonsOnly=true:NoSchedule \
    --mode User
if [ $? -eq 0 ]; then
    echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') Application node pool added successfully." ${NC}
else
    echo ${RED} "$(date '+%Y-%m-%d %H:%M:%S%:z') Application node pool addition failed." ${NC}
    exit 1
fi

# Now the cluster is finally created
echo "AKS_CLUSTER_NAME=${AKS_CLUSTER_NAME}" >>./deployment/deploy.state


# Get AKS cluster credentials
az aks get-credentials --name "${AKS_CLUSTER_NAME}" --resource-group "${RESOURCE_GROUP}"
if [ $? -ne 0 ]; then
    echo ${RED} "$(date '+%Y-%m-%d %H:%M:%S%:z') AKS cluster credentials retrieval failed." ${NC}
    exit 1
fi

# Create a separate managed identity for the AKS workload identity
export WORKLOAD_MANAGED_IDENTITY_NAME="mi-aks-workload-identity-${SUFFIX}"
# Create User Assigned Managed Identity for the AKS workload identity for KEDA and app code to access Cosmos DB
workloadManagedIdentity=$(az identity create --name "$WORKLOAD_MANAGED_IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" --output json)
if [ $? -eq 0 ]; then
    echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') AKS workload identity managed identity $WORKLOAD_MANAGED_IDENTITY_NAME created successfully." ${NC}
else
    echo ${RED} "$(date '+%Y-%m-%d %H:%M:%S%:z') AKS workload identity managed identity $WORKLOAD_MANAGED_IDENTITY_NAME creation failed." ${NC}
    exit 1
fi
echo "WORKLOAD_MANAGED_IDENTITY_NAME=${WORKLOAD_MANAGED_IDENTITY_NAME}" >>./deployment/deploy.state

workloadManagedIdentityObjectId=$(echo "$workloadManagedIdentity" | jq -r '.principalId')
workloadManagedIdentityResourceId=$(echo "$workloadManagedIdentityResourceId" | jq -r '.id')
workloadManagedIdentityClientId=$(az identity show --ids "$managedIdentityResourceId" --query clientId --output tsv)

#Check is the namespace already exists
if kubectl get namespace $AQS_TARGET_NAMESPACE &>/dev/null; then
    echo "Namespace $AQS_TARGET_NAMESPACE already exists"
else
    echo "Creating namespace $AQS_TARGET_NAMESPACE"
    kubectl create namespace $AQS_TARGET_NAMESPACE
fi

# Create and annotate the service account
echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') Creating service account ${SERVICE_ACCOUNT}" ${NC}
kubectl create serviceaccount "$SERVICE_ACCOUNT" -n "$AQS_TARGET_NAMESPACE"
if [ $? -eq 0 ]; then
    echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') Service account $SERVICE_ACCOUNT created successfully." ${NC}
else
    echo ${RED} "$(date '+%Y-%m-%d %H:%M:%S%:z') Service account $SERVICE_ACCOUNT creation failed." ${NC}
    exit 1
fi
# This is required to associate the managed identity with the service account
kubectl annotate serviceaccount "$SERVICE_ACCOUNT" -n "$AQS_TARGET_NAMESPACE" "azure.workload.identity/client-id=$workloadManagedIdentityClientId"
if [ $? -eq 0 ]; then
    echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') Managed identity $workloadManagedIdentityClientId associated with service account $SERVICE_ACCOUNT." ${NC}
    kubectl get serviceaccount "$SERVICE_ACCOUNT" -n "$AQS_TARGET_NAMESPACE" -o yaml
else
    echo ${RED} "$(date '+%Y-%m-%d %H:%M:%S%:z') Failed to associate managed identity $workloadManagedIdentityClientId with service account $SERVICE_ACCOUNT." ${NC}
    exit 1
fi

# Check if the federated identity credential already exists and if not create it and associate it to the managed identity
export FEDERATED_IDENTITY_CREDENTIAL_NAME="federated-credential-${SUFFIX}"
if ! az identity credential show --name "$FEDERATED_IDENTITY_CREDENTIAL_NAME" --resource-group "$RESOURCE_GROUP" --identity "$workloadManagedIdentityResourceId" &>/dev/null && ! az identity federated-credential show --name "$FEDERATED_IDENTITY_CREDENTIAL_NAME" --identity-name "$WORKLOAD_MANAGED_IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    AKS_OIDC_ISSUER=$(az aks show --name $AKS_CLUSTER_NAME --resource-group "$RESOURCE_GROUP" --query "oidcIssuerProfile.issuerUrl" -otsv)
    # Create the federated identity credential
    az identity federated-credential create --name ${FEDERATED_IDENTITY_CREDENTIAL_NAME} --identity-name ${WORKLOAD_MANAGED_IDENTITY_NAME} --resource-group "$RESOURCE_GROUP" --issuer ${AKS_OIDC_ISSUER} --subject system=serviceaccount=${AQS_TARGET_NAMESPACE}=${SERVICE_ACCOUNT}
    if [ $? -eq 0 ]; then
        echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') Federated identity credential '$FEDERATED_IDENTITY_CREDENTIAL_NAME' created successfully and associated with the workload identity managed identity." ${NC}
    else
        echo ${RED} "$(date '+%Y-%m-%d %H:%M:%S%:z') Federated identity credential '$FEDERATED_IDENTITY_CREDENTIAL_NAME' creation failed." ${NC}
        exit 1
    fi
else
    echo ${YELLOW} "$(date '+%Y-%m-%d %H:%M:%S%:z') The federated identity credential '$FEDERATED_IDENTITY_CREDENTIAL_NAME' already exists and is associated with the workload identity managed identity."
fi
echo "FEDERATED_IDENTITY_CREDENTIAL_NAME=${FEDERATED_IDENTITY_CREDENTIAL_NAME}" >>./deployment/deploy.state

# We're not going to use CosmosDB until the API issue is fixed
# 
#export COSMOSDB_ACCOUNT_NAME="cosmosdb-${LOCAL_NAME,,}-${SUFFIX,,}"
# Check if Azure Cosmos DB account already exists
# if ! az cosmosdb show --name "${COSMOSDB_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
#     # Create Azure Cosmos DB account
#     echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') Creating Azure Cosmos DB account ${COSMOSDB_ACCOUNT_NAME} in resource group ${RESOURCE_GROUP}"  ${NC}
#     az cosmosdb create --name "${COSMOSDB_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" \
#     --default-consistency-level Eventual --locations regionName="${LOCATION}" \
#     failoverPriority=0 isZoneRedundant=False --capabilities EnableServerless EnableTable

#     az cosmosdb table exists --account-name "${COSMOSDB_ACCOUNT_NAME}" --name "${AZURE_COSMOSDB_TABLE}" --resource-group "${RESOURCE_GROUP}"
#     if [ $? -eq 0 ]; then
#         # Create Azure Cosmos DB database
#         az cosmosdb table create --account-name "${COSMOSDB_ACCOUNT_NAME}" --resource-group "$RESOURCE_GROUP" --name "${AZURE_COSMOSDB_TABLE}"
#         if [ $? -eq 0 ]; then
#             echo ${GREEN} "$(date '+%Y-%m-%d %H:%M:%S%:z') Azure Cosmos DB table '${AZURE_COSMOSDB_TABLE}' created successfully." ${NC}
#         else
#             echo ${RED} "$(date '+%Y-%m-%d %H:%M:%S%:z') Azure Cosmos DB table '${AZURE_COSMOSDB_TABLE}' creation failed." ${NC}
#             exit 1
#         fi
#     else
#         echo "Azure Cosmos DB database '$AZURE_COSMOSDB_TABLE' already exists."
#     fi
# else
#     echo "Azure Cosmos DB account '${COSMOSDB_ACCOUNT_NAME}' already exists."
# fi
# echo "AZURE_COSMOSDB_TABLE=${AZURE_COSMOSDB_TABLE}" >>./deployment/deploy.state
# echo "COSMOSDB_ACCOUNT_NAME=${COSMOSDB_ACCOUNT_NAME}" >>./deployment/deploy.state


# Setup RBAC data plane access to Azure Storage and Azure Cosmos DB for the workload identity
# Grant Storage Blob Data Contributor role to the managed identity for the storage account
workloadManagedIdentity=$(az identity show --name "$WORKLOAD_MANAGED_IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" --output json) 
workloadManagedIdentityObjectId=$(echo "$workloadManagedIdentity" | jq -r '.principalId')
storageAccountResourceId=$(az storage account show --name "$AZURE_STORAGE_ACCOUNT_NAME" --resource-group "$STORAGE_RG_NAME" --query "id" --output tsv)
roleAssignment=$(az role assignment list --assignee "$workloadManagedIdentityObjectId" --scope "$storageAccountResourceId" --query "[?roleDefinitionName=='Storage Blob Data Contributor']" --output json)
if [ -z "$roleAssignment" ]; then
    az role assignment create --assignee-object-id "$workloadManagedIdentityObjectId" --role "Storage Blob Data Contributor" --scope "$storageAccountResourceId" --assignee-principal-type ServicePrincipal
else
    echo "The workload managed identity with object ID $workloadManagedIdentityObjectId already has the 'Storage Blob Data Contributor' role assigned to the storage account."
fi

# Grant Cosmos DB Account Contributor role to the managed identity for the Cosmos DB account
# cosmosdbAccountResourceId=$(az cosmosdb show --name "${COSMOSDB_ACCOUNT_NAME}" --resource-group "$RESOURCE_GROUP" --query "id" --output tsv)
# workloadManagedIdentityObjectId=$(echo "$workloadManagedIdentity" | jq -r '.principalId')
# roleAssignment=$(az role assignment list --assignee "$workloadManagedIdentityObjectId" --scope "$cosmosdbAccountResourceId" --query "[?roleDefinitionName=='DocumentDB Account Contributor']" --output json)
# if [ -z "$roleAssignment" ]; then
#     az role assignment create --assignee-object-id "$workloadManagedIdentityObjectId" --role "DocumentDB Account Contributor" --scope "$cosmosdbAccountResourceId" --assignee-principal-type ServicePrincipal
# else
#     echo "The workload managed identity with object ID $workloadManagedIdentityObjectId already has the 'DocumentDB Account Contributor' role assigned to the Cosmos DB account."
# fi

echo "Deployment completed successfully."
