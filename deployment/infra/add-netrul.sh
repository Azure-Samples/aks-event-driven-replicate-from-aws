managedRG=$(az aks show --name $AKS_CLUSTER_NAME -g $RESOURCE_GROUP --query nodeResourceGroup -o tsv)
networkRuleName=netrul-stor-${LOCAL_NAME}-${SUFFIX}
# Get the virtual network name and resource ID
vnetInfo=$(az network vnet list --resource-group $managedRG)
vnetName=$(echo $vnetInfo | jq -r '.[0].name')
vnetId=$(echo $vnetInfo | jq -r '.[0].id')
subnetId=$(echo $vnetInfo | jq -r '.[0].subnets[0].id')
subnetName=$(echo $vnetInfo | jq -r '.[0].subnets[0].name')

echo "Virtual network name - ${vnetName}"
echo "Virtual network id - ${vnetId}"
echo "Subnet id - ${subnetId}"
echo "Subnet name - ${subnetName}"

# Add a network rule to the storage account
echo "Adding storage account network rule"
az storage account network-rule add \
--vnet-name ${vnetName} \
--subnet ${subnetName} \


# Output the results
echo "You should see a new vnet rule in the rule set"
az storage account network-rule list --resource-group ${RESOURCE_GROUP} --account-name ${AZURE_STORAGE_ACCOUNT_NAME}
