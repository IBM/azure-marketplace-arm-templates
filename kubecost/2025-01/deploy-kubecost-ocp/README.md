# Deploy Kubecost on OpenShift script

This script is designed to run in an Azure CLI container. It will:
- install the required CLI tools including helm
- log into the OpenShift cluster with the provided credentials
- install Kubecost with the helm command to the cluster