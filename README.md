# aks-event-driven-replicate-from-aws

This sample provides the backing code for workshop content on replicating an event driven workload from AWS to Azure using Azure Kubernetes Service (AKS). The workshop content is available at [Replicating an event driven workload from AWS to Azure]()

## Features

This project demonstrates::

* How to translate an AWS workload using AWS first party services to Azure services.
* How to secure an AKS workoad using workload identity.
* ...

## Getting Started

For an understanding of the AWS workload being replicated, see  [Scalable and Cost-Effective Event-Driven Workloads with KEDA and Karpenter on Amazon EKS](https://aws.amazon.com/blogs/containers/scalable-and-cost-effective-event-driven-workloads-with-keda-and-karpenter-on-amazon-eks/).

### Prerequisites

The following prerequisites are required to run this sample:

* OS: Linux  (the deployment scripts use bash shell)
* Azure CLI version 2.56 or later. Use the `az --version` command to find the version. If you need to install or upgrade, see [Install the Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli).
* jq version 1.6 or later. Use the `jq --version` command to find the version. If you need to install or upgrade, see [jq](https://stedolan.github.io/jq/download/).
* Python version 3.8 or later. Use the `python --version` command to find the version. If you need to install or upgrade, see [Python](https://www.python.org/downloads/).
* kubectl version 1.21 or later. Use the `kubectl version --client` command to find the version. If you need to install or upgrade, see [Install kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/).
* Helm version 3.7 or later. Use the `helm version` command to find the version. If you need to install or upgrade, see [Helm](https://helm.sh/docs/intro/install/).

### Installation

Aside from the prerequisites, there is nothing else you need to install to run this sample.

### Quickstart

#### Deploy the Infrastructure

The first step of the workshop is to deploy the AKS cluster and the supporting infrastructure. The main infrastructure deployment script is located in the deployment/infra directory. The deployment script `deploy.sh` is run from the project root directory.

```bash
./deployment/infra/deploy.sh
```

The deployment script will stand up the a resource group, an Azure Storage Account, a Container Registry and an AKS cluster. In addition, the script also creates a managed identity for the AKS cluster and a managed identity to be used as the workload identity. The script also creates federated credentials for the workload identity.

The deployment script also creates a file, `deploy.state` in the deployment directory. This file contains the resource group name, storage account name, container registry name, AKS cluster name, and the managed identity names. The file can be used with the other deployment scripts to reference the names of the resources created by the script.

#### Populate the Message Queue

The next step is to populate the message queue with messages. The message queue is an Azure Storage Queue. In the `app/keda` directory you will find the `aqs-producer.py` Python app. Before running the app, you will need to: 

1. Set the environment variables for the storage account name. The code for the producer and consumer apps have already been modified to use the [Azure SDK for Python](https://learn.microsoft.com/en-us/azure/developer/python/sdk/azure-sdk-overview). Use the `deployment/deploy.state` file to set the environment variables you will need to run the producer app.

```bash
. ./deployment/environmentVariables.sh
while IFS= read -r line; do echo "export $line"; export $line; done < ./deployment/deploy.state
```

2. Login to your Azure account using the Azure CLI. Both the consumer and producer apps use Azure crednetials to authenticate with the storage account created in the previous step. In the case of the consumer app, the workload identity you created in the deployment (which has the role assigned to it) will be used to authenticate for access to the storage account. Because you will run the producer app from a terminal window, the producer app will authenticate using the Azure credential you logged in with. Therefore, the account you login with must have the Storage Queue Data Contributor role assigned to it.  You can assign the role to your user account using the Azure portal or the Azure CLI.

```bash
az login
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
az role assignment create --role "Storage Queue Data Contributor" \
--assignee <your-azure-account-email> \
--scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$AZURE_STORAGE_ACCOUNT_NAME
./deployment/app/keda/aqs-producer.py
```

Let the producer app run for a few minutes to populate the queue with messages, then enter Ctrl-C to stop the app.

#### Deploy the Consumer App Container to the Container Registry

The next step is to build the consumer app container and push it to the container registry. The consumer app is a Python app that reads messages from the Azure Storage Queue and writes them to an Azure Storage Table. The consumer app is located in the `app/keda` directory. The `Dockerfile` is located in the `app/keda` directory. In a separate terminal window, navigate to the project root directory and use the `app/keda/docker-command.sh` script is located in the `deployment/app/keda` directory to build and push the container to the Azure Container Registry you created.

```bash
. ./deployment/environmentVariables.sh
while IFS= read -r line; do echo "export $line"; export $line; done < ./deployment/deploy.state
./app/docker-command.sh
```

#### Deploy the Consumer App Container and ScaledObject to the AKS Cluster

Once the container is pushed to the container registry, you can deploy the consumer app container and the ScaledObject to the AKS cluster. The ScaledObject is a KEDA custom resource that scales the consumer app deployment based on the number of messages in the Azure Storage Queue. The scripts to deploy both the consumer app and the scaled object iares located in the `deployment/keda` directory.

```bash
. ./deployment/environmentVariables.sh
while IFS= read -r line; do echo "export $line"; export $line; done < ./deployment/deploy.state
./deployment/keda/deploy-keda-app-workload-id.sh
./deployment/keda/keda-scaleobject-workload-id.sh
```

You can use an app like [k9s](https://k9scli.io/) or `kubectl` to monitor the consumer app deployment and the ScaledObject. Before using either app, you will need to add the AKS cluster to your kubeconfig file. You can do this using the Azure CLI

```bash
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME
```

You can then verify the consumer app deployment and the ScaledObject using `kubectl`.

```bash
kubectl get pods -namespace $AQS_TARGET_NAMESPACE
```

As the producer app hydrates the Azure Storage Queue with messages, you will see the consumer app deployment scale up and down based on the number of messages in the queue.

#### Clean Up

To clean up the resources created by the deployment scripts, run the `cleanup.sh` script in the `deployment/infra` directory.

```bash
./deployment/infra/cleanup.sh
```

## Resources
