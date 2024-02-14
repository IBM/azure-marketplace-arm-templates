#!/bin/bash
# Basic script to update the OS and setup to manage an AKS cluster.
# This script runs as root

# Get the configured admin user (this comes from the bootstrap script)
if [[ -f /root/script-parameters.txt ]]; then
    ADMIN_USER=$(cat /root/script-parameters.txt  | grep adminuser | awk -F'=' '{print $2}')
else    # Take a guess by taking the first user (should be the only one)
    USER_LIST=( $(ls -h /home) )
    ADMIN_USER=$(echo ${USER_LIST[0]})
fi

# Update the OS
sudo apt update
sudo apt -y dist-upgrade

# Install the az CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Log into the VM (as root)
az login --identity

# Enable the firewall
sudo ufw allow "openSSH"
sudo ufw enable

# Install kubectl & kubelogin tools
az aks install-cli

# Log into Azure CLI as admin user
su - $ADMIN_USER -c 'az login --identity'

###### ADD STEP TO LOGIN INTO AKS CLUSTER
# The following assumes a single visible AKS cluster in the resource group

# Get the configured resource group (this comes from the bootstrap script)
if [[ -f /root/script-parameters.txt ]]; then
    RESOURCE_GROUP=$(cat script-parameters.txt  | grep resourcegroup | awk -F'=' '{print $2}')
else    # Take a guess by looking at visible 
    RESOURCE_GROUPS=( $(az group list -o table | grep -v "MC_" | grep Succeeded | awk '{print $1}') )
    RESOURCE_GROUP=$(echo ${RESOURCE_GROUPS[0]})
fi

# The the AKS cluster name
AKS_CLUSTER_NAME=$(az aks list -g $RESOURCE_GROUP --query '[0].name' -o tsv)

# Log admin user into AKS cluster
su - $ADMIN_USER -c "az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME --overwrite-existing"