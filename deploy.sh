#!/bin/bash

while getopts c:n:r: flag
do
  case "${flag}" in
    c) name=${OPTARG};;
    n) nodes=${OPTARG};;
    r) region=${OPTARG};;    
  esac
done

if test -z "$name" 
then
  echo "Cluster name is empty. Use -c flag"
  exit 0  
fi

if test -z "$nodes" 
then
  echo "Number of nodes in the cluster is not defined. Use -n flag. Use default 3 nodes."
  export nodes=3
fi

if test -z "$region" 
then
  echo "Azure region is not defined. Use -r flag. Default WestEurope"
  export region=westeurope
fi

echo "Cluster name:                     $name";
echo "Number of nodes:                  $nodes";
echo "Azure region:                     $region";

export DEPLOYMENT_NAME=$name
export RESOURCE_GROUP=rg-$DEPLOYMENT_NAME
export AKS_NAME=k8s-$DEPLOYMENT_NAME

echo "Deployment name:                    $DEPLOYMENT_NAME"
echo "Azure resource group name:          $RESOURCE_GROUP"
echo "AKS name:                           $AKS_NAME"

az group create --name $RESOURCE_GROUP --location $region

az network public-ip create --resource-group $RESOURCE_GROUP --location $region \
  --name ip-outbound-$DEPLOYMENT_NAME \
  --sku Standard \
  --version IPv4 \
  --allocation-method Static

az network public-ip create --resource-group $RESOURCE_GROUP --location $region \
  --name ip-inbound-$DEPLOYMENT_NAME \
  --sku Standard \
  --version IPv4 \
  --allocation-method Static  

az storage account create --resource-group $RESOURCE_GROUP --location $region \
  --access-tier "cool" \
  --name st$RANDOM 

az monitor log-analytics workspace create --resource-group $RESOURCE_GROUP --location $region \
  --workspace-name log-k8s-$DEPLOYMENT_NAME \
  --sku "PerGB2018"

export PUBLIC_IP_INBOUND=$(az network public-ip show --resource-group $RESOURCE_GROUP --name ip-inbound-$DEPLOYMENT_NAME --query ipAddress -o tsv)
export PUBLIC_IP_OUTBOUND_ID=$(az network public-ip show --resource-group $RESOURCE_GROUP --name ip-outbound-$DEPLOYMENT_NAME --query id -o tsv)

if test -z "$PUBLIC_IP_INBOUND" 
then
  echo "Error: PUBLIC_IP_INBOUND is empty. It is required to configure the ingress of Kubernetes. Exit script"
  exit
fi
echo "PUBLIC_IP_INBOUND:    $PUBLIC_IP_INBOUND"

if test -z "$PUBLIC_IP_OUTBOUND_ID" 
then
  echo "Error: PUBLIC_IP_OUTBOUND_ID is empty. It is required to configure the egress of Kubernetes. Exit script"
  exit
fi
echo "PUBLIC_IP_OUTBOUND_ID:    $PUBLIC_IP_OUTBOUND_ID"

# az monitor log-analytics workspace show --resource-group $RESOURCE_GROUP --workspace-name log-k8s-$DEPLOYMENT_NAME 

# Register the CustomNodeConfigPreview preview feature
az feature register --namespace "Microsoft.ContainerService" --name "CustomNodeConfigPreview"
az provider register --namespace Microsoft.ContainerService
az extension add --name aks-preview
az extension update --name aks-preview

echo "Creating AKS..."
az aks create --resource-group $RESOURCE_GROUP --location $region \
  --name $AKS_NAME \
  --dns-name-prefix $AKS_NAME \
  --kubernetes-version "1.20.5" \
  --node-count $nodes \
  --node-vm-size "Standard_B2s" \
  --nodepool-name "kubenet" \
  --outbound-type "loadBalancer" \
  --load-balancer-outbound-ips $PUBLIC_IP_OUTBOUND_ID \
  --linux-os-config ./linuxosconfig.json 
  # --workspace-resource-id xxx \  
echo "Creating AKS done"

# az aks enable-addons --addons monitoring --name $AKS_NAME --resource-group $RESOURCE_GROUP --workspace-resource-id
az aks enable-addons --addons azure-policy --name $AKS_NAME --resource-group $RESOURCE_GROUP

# Add cluster key to the local .kubeconfig file
az aks get-credentials --name $AKS_NAME --resource-group $RESOURCE_GROUP

# List k8s available cluster
az aks list -o table

# Switch kubectl context to the newly created cluster
kubectl config use-context $AKS_NAME

# Install helm charts
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add csi-secrets-store-provider-azure https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts
helm repo update

# Add Azure Key Vault CSI driver
helm install csi-secrets-store-provider-azure/csi-secrets-store-provider-azure --generate-name

# Nginx ingress controller
kubectl create namespace ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --set controller.service.loadBalancerIP=$PUBLIC_IP_INBOUND 
