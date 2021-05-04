#!/bin/bash

export RESOURCE_GROUP="rg-test123"
export REGION="westeurope"

az feature register --namespace "Microsoft.ContainerService" --name "CustomNodeConfigPreview"
az provider register --namespace Microsoft.ContainerService
az extension add --name aks-preview
az extension update --name aks-preview

az group create --name $RESOURCE_GROUP --location $REGION

az network public-ip create --resource-group $RESOURCE_GROUP --location $REGION \
  --name ip-outbound-test123 \
  --sku Standard \
  --version IPv4 \
  --allocation-method Static

export PUBLIC_IP_OUTBOUND_ID=$(az network public-ip show --resource-group $RESOURCE_GROUP --name ip-outbound-test123 --query id -o tsv)
echo "PUBLIC_IP_OUTBOUND_ID:    $PUBLIC_IP_OUTBOUND_ID"

echo "Creating AKS..."
az aks create --resource-group $RESOURCE_GROUP --location $REGION \
  --name test123 \
  --dns-name-prefix test123 \
  --nodepool-name "kubenet" \
  --outbound-type "loadBalancer" \
  --load-balancer-outbound-ips $PUBLIC_IP_OUTBOUND_ID \
  --linux-os-config ./linuxosconfig.json 