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
echo "AKS resource name:                  $AKS_NAME"

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

export PUBLIC_IP_INBOUND=$(az network public-ip show --resource-group $RESOURCE_GROUP --name ip-inbound-$DEPLOYMENT_NAME --query ipAddress)
export PUBLIC_IP_OUTBOUND=$(az network public-ip show --resource-group $RESOURCE_GROUP --name ip-outbound-$DEPLOYMENT_NAME --query ipAddress)
# az monitor log-analytics workspace show --resource-group $RESOURCE_GROUP --workspace-name log-k8s-$DEPLOYMENT_NAME 

# Register the CustomNodeConfigPreview preview feature
az feature register --namespace "Microsoft.ContainerService" --name "CustomNodeConfigPreview"
az provider register --namespace Microsoft.ContainerService
az extension add --name aks-preview
az extension update --name aks-preview

az aks create --resource-group $RESOURCE_GROUP --location $region \
  --name $AKS_NAME \  
  --dns-name-prefix $AKS_NAME \
  --kubernetes-version "1.20.5" \
  --node-count $nodes \
  --enable-rbac true \
  --node-vm-size "Standard_B2s" \
  --nodepool-name "kubenet" \
  --outbound-type "loadBalancer" \
  --load-balancer-outbound-ips $PUBLIC_IP_OUTBOUND \
  --linux-os-config ./linuxosconfig.json \
  # --workspace-resource-id xxx \  

# az aks enable-addons --addons monitoring --name $AKS_NAME --resource-group $RESOURCE_GROUP --workspace-resource-id
az aks enable-addons --addons azure-policy --name $AKS_NAME --resource-group $RESOURCE_GROUP

# Add cluster key to the local .kubeconfig file
az aks get-credentials --name $AKS_NAME --resource-group $RESOURCE_GROUP

# Install helm charts
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add csi-secrets-store-provider-azure https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts
helm repo update

# Add Azure Key Vault CSI driver
helm install csi-secrets-store-provider-azure/csi-secrets-store-provider-azure --generate-name

# Nginx ingress controller
kubectl create namespace ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --set controller.service.loadBalancerIP=$PUBLIC_IP_INBOUND 
