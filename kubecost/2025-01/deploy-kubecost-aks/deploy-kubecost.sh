#!/bin/bash

# Install tools - kubectl, helm

wget -O helm.tgz https://get.helm.sh/helm-v3.4.1-linux-amd64.tar.gz
tar -zxvf helm.tgz
mv linux-amd64/helm /usr/local/bin/helm

az aks install-cli

# Log into cluster
az aks get-credentials -n $AKS_CLUSTER -g $RESOURCE_GROUP
kubelogin convert-kubeconfig -l azurecli

# Run helm chart
helm install kubecost cost-analyzer \
--repo https://kubecost.github.io/cost-analyzer/ \
--namespace kubecost --create-namespace \
--set kubecostToken="${KUBECOST_TOKEN}"