#!/bin/bash

while getopts c: flag
do
  case "${flag}" in
    c) name=${OPTARG};;
  esac
done

if test -z "$name" 
then
  echo "Cluster name is empty. Use -c flag"
  exit 0  
fi

echo "Cluster name:                     $name";

export DEPLOYMENT_NAME=$name
export RESOURCE_GROUP=rg-$DEPLOYMENT_NAME
export AKS_NAME=k8s-$DEPLOYMENT_NAME

echo "Azure resource group name:          $RESOURCE_GROUP"
echo "AKS name:                           $AKS_NAME"

az group delete --resource-group $RESOURCE_GROUP