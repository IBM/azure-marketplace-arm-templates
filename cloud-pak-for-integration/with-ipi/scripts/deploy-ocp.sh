#!/bin/bash
#############################################
#
# Script to deploy OpenShift IPI on Azure
# To be run in an Azure deployment script container
#
# If using a managed identity, just supply the CLIENT_ID and CLIENT_SECRET 
# If using the service principal for the container, supply CLIENT_ID, CLIENT_SECRET, TENANT_ID and SUBSCRIPTION_ID
#
# Requires virtual network to be created ahead of time.
#
# Author: Rich Ehrhardt
# 
#############################################

########## TO DO: Add error output to Azure agent.

source common.sh

OUTPUT_FILE="ocp-script-output-$(date -u +'%Y-%m-%d-%H%M%S').log"
log-info "Script started" 

#######
# Check for critcal environment variables
ENV_VAR_NOT_SET=""
if [[ -z $CLIENT_ID ]]; then ENV_VAR_NOT_SET="CLIENT_ID"; fi
if [[ -z $CLIENT_SECRET ]]; then ENV_VAR_NOT_SET="CLIENT_SECRET"; fi
if [[ -z $BASE_DOMAIN ]]; then ENV_VAR_NOT_SET="BASE_DOMAIN"; fi
if [[ -z $BASE_DOMAIN_RESOURCE_GROUP ]]; then ENV_VAR_NOT_SET="BASE_DOMAIN_RESOURCE_GROUP"; fi
if [[ -z $PULL_SECRET ]]; then ENV_VAR_NOT_SET="PULL_SECRET"; fi
if [[ -z $PUBLIC_SSH_KEY ]]; then ENV_VAR_NOT_SET="PUBLIC_SSH_KEY"; fi
if [[ -z $VNET_NAME ]]; then ENV_VAR_NOT_SET="VNET_NAME"; fi
if [[ -z $WORKER_SUBNET_NAME ]]; then ENV_VAR_NOT_SET="WORKER_SUBNET_NAME"; fi
if [[ -z $CONTROL_SUBNET_NAME ]]; then ENV_VAR_NOT_SET="CONTROL_SUBNET_NAME"; fi
if [[ -z $MACHINE_CIDR ]]; then ENV_VAR_NOT_SET="MACHINE_CIDR"; fi
if [[ -z $CLUSTER_RESOURCE_GROUP ]]; then ENV_VAR_NOT_SET="CLUSTER_RESOURCE_GROUP"; fi
if [[ -z $NETWORK_RESOURCE_GROUP ]]; then ENV_VAR_NOT_SET="NETWORK_RESOURCE_GROUP"; fi

if [[ -n $ENV_VAR_NOT_SET ]]; then
  log-error "$ENV_VAR_NOT_SET not set. Please set and retry."
  exit 1
fi

##########
# Set defaults
if [[ -z $WORKSPACE_DIR ]]; then WORKSPACE_DIR="$(pwd)"; fi
if [[ -z $BIN_DIR ]]; then BIN_DIR="/usr/bin"; fi
if [[ -z $VERSION ]]; then VERSION="4"; fi
if [[ -z $MASTER_HYPERTHREADING ]]; then MASTER_HYPERTHREADING="Enabled"; fi
if [[ -z $MASTER_ARCHITECTURE ]]; then MASTER_ARCHITECTURE="amd64"; fi
if [[ -z $MASTER_NODE_DISK_SIZE ]]; then MASTER_NODE_DISK_SIZE=120; fi
if [[ -z $MASTER_NODE_DISK_TYPE ]]; then MASTER_NODE_DISK_TYPE="Premium_LRS"; fi
if [[ -z $MASTER_NODE_TYPE ]]; then MASTER_NODE_TYPE="Standard_D8s_v3"; fi
if [[ -z $MASTER_NODE_QTY ]]; then MASTER_NODE_QTY=3; fi
if [[ -z $WORKER_HYPERTHREADING ]]; then WORKER_HYPERTHREADING="Enabled"; fi
if [[ -z $WORKER_ARCHITECTURE ]]; then WORKER_ARCHITECTURE="amd64"; fi
if [[ -z $WORKER_NODE_TYPE ]]; then WORKER_NODE_TYPE="Standard_D4s_v3"; fi
if [[ -z $WORKER_NODE_DISK_SIZE ]]; then WORKER_NODE_DISK_SIZE=120; fi
if [[ -z $WORKER_NODE_DISK_TYPE ]]; then WORKER_NODE_DISK_TYPE="Premium_LRS"; fi
if [[ -z $WORKER_NODE_QTY ]]; then WORKER_NODE_QTY=3; fi
if [[ -z $HOST_ENCRYPTION ]]; then HOST_ENCRYPTION="true"; fi
if [[ -z $CLUSTER_NAME ]]; then CLUSTER_NAME=$(cat /dev/urandom | tr -dc '[:alpha:]' | fold -w ${1:-8} | head -n 1 | tr '[:upper:]' '[:lower:]'); fi
if [[ -z $CLUSTER_CIDR ]]; then CLUSTER_CIDR="10.128.0.0/14"; fi
if [[ -z $CLUSTER_HOST_PREFIX ]]; then CLUSTER_HOST_PREFIX="23"; fi
if [[ -z $SERVICE_NETWORK_CIDR ]]; then SERVICE_NETWORK_CIDR="172.30.0.0/16"; fi
if [[ -z $OCP_OUTBOUND_TYPE ]]; then OCP_OUTBOUND_TYPE="Loadbalancer"; fi
if [[ -z $CLUSTER_ACCESS ]]; then CLUSTER_ACCESS="External"; fi
if [[ -z $VM_NETWORKING_TYPE ]]; then VM_NETWORKING_TYPE="Accelerated"; fi
if [[ -z $NEW_CLUSTER_RESOURCE_GROUP ]]; then NEW_CLUSTER_RESOURCE_GROUP="true"; fi
if [[ -z $SECRET_NAME ]]; then SECRET_NAME="cluster-password"; fi

# The following can be "OVNKubernetes" (the default), or "OpenShiftSDN"
if [[ -z $OCP_NETWORK_TYPE ]]; then OCP_NETWORK_TYPE="OVNKubernetes"; fi

# The following value should be "AzureUSGovernmentCloud" for gov cloud deployments.
if [[ -z $CLOUD_TYPE ]]; then CLOUD_TYPE="AzurePublicCloud"; fi

# The following should be set to Enabled to use UltraSSD disks for persistent storage
if [[ -z $ENABLE_ULTRADISK ]]; then ENABLE_ULTRADISK="Disabled"; fi

if [[ -z $DEBUG ]]; then DEBUG=false; fi

log-info "Workspace directory is set to : $WORKSPACE_DIR"
log-info "Binary directory is set to : $BIN_DIR"
if [[ $CLIENT_ID ]]; then log-info "Client id is $CLIENT_ID"; fi
if [[ $CLIENT_SECRET ]]; then log-info "Client secret is set"; fi
if [[ $PULL_SECRET ]]; then log-info "Red Hat pull secret is set"; fi
log-info "Network resource group set to $NETWORK_RESOURCE_GROUP"
log-info "Virtual network name is set to $VNET_NAME"
log-info "Worker subnet name is set to $WORKER_SUBNET_NAME"
log-info "Control subnet name is set to $CONTROL_SUBNET_NAME"
log-info "OpenShift version is set to $VERSION"
log-info "Master hyperthreading is set to $MASTER_HYPERTHREADING"
log-info "Master architecture is set to $MASTER_ARCHITECTURE"
log-info "Master node disk size is set to $MASTER_NODE_DISK_SIZE"
log-info "Master node disk type is set to $MASTER_NODE_DISK_TYPE"
log-info "Master node VM type is set to $MASTER_NODE_TYPE"
log-info "Master node quantity is set to $MASTER_NODE_QTY"
log-info "Worker hyperthreading is set to $WORKER_HYPERTHREADING"
log-info "Worker architecture is set to $WORKER_ARCHITECTURE"
log-info "Worker disk size is set to $WORKER_NODE_DISK_SIZE"
log-info "Worker disk type is set to $WORKER_NODE_DISK_TYPE"
log-info "Worker node VM type is set to $WORKER_NODE_TYPE"
log-info "Worker node quantity is set to $WORKER_NODE_QTY"
log-info "Cluster name is set to $CLUSTER_NAME"
if [[ $CLUSTER_RESOURCE_GROUP ]]; then log-info "Cluster resource group is set to $CLUSTER_RESOURCE_GROUP"; fi
if [[ $CLUSTER_RESOURCE_GROUP ]]; then log-info "New cluster resource group is set to $NEW_CLUSTER_RESOURCE_GROUP"; fi
log-info "Cluster base domain is set to $BASE_DOMAIN"
log-info "Base domain resource group is set to $BASE_DOMAIN_RESOURCE_GROUP"
log-info "Internal OpenShift network CIDR set to $CLUSTER_CIDR"
log-info "Internal host prefix for OpenShift is set to $CLUSTER_HOST_PREFIX"
log-info "OpenShift virtual machine network CIDR is set to $MACHINE_CIDR"
log-info "OpenShift internal networking set to $OCP_NETWORK_TYPE"
log-info "OpenShift internal services network CIDR is set to $SERVICE_NETWORK_CIDR"
log-info "OpenShift outbound routing is set to $OCP_OUTBOUND_TYPE"
log-info "Cluster node networking type is set to $VM_NETWORKING_TYPE"
log-info "OpenShift ingress is set to $CLUSTER_ACCESS"
log-info "OpenShift UltraSSD is set to $ENABLE_ULTRADISK"
log-info "OpenShift cloud type is set to $CLOUD_TYPE"
if [[ $VAULT_NAME ]]; then 
  log-info "Will upload cluster secrets to $VAULT_NAME"
  log-info "Will upload cluster password to $VAULT_NAME as $SECRET_NAME"
fi
log-info "DEBUG: Debug is set to true"


#######
# Login to Azure CLI
az account show > /dev/null 2>&1
if (( $? != 0 )); then
    # Login with service principal details
    az-login $CLIENT_ID $CLIENT_SECRET $TENANT_ID $SUBSCRIPTION_ID
    SP_LOGIN=true
else
    SP_LOGIN=false
    log-info "Using existing Azure CLI login"
fi

#########
# Set location if not already
if [[ -z $LOCATION ]]; then
    LOCATION=$(az group show -n $NETWORK_RESOURCE_GROUP --query 'location' -o tsv)
    if (( $? != 0 )); then
      log-error "Unable to determine location. Please set as environment variable"
      exit 1
    fi
fi
log-info "Location is set to $LOCATION"

##########
# Get environment parameters
if [[ -z $SUBSCRIPTION_ID ]]; then
    SUBSCRIPTION_ID=$(az account show --query 'id' -o tsv)
fi
log-info "Subscription Id is set to $SUBSCRIPTION_ID"

if [[ -z $TENANT_ID ]]; then
    TENANT_ID=$(az account show --query 'tenantId' -o tsv)
fi
log-info "Tenant Id is set to $TENANT_ID"

##########
# Download OpenShift installer
download-openshift-installer $WORKSPACE_DIR $VERSION $BIN_DIR

##########
# Setup Azure credentials for OpenShift
log-info "Creating Azure login credentials file"
jq --null-input \
    --arg subscription_id "${SUBSCRIPTION_ID}" \
    --arg client_id "${CLIENT_ID}" \
    --arg client_secret "${CLIENT_SECRET}" \
    --arg tenant_id "${TENANT_ID}" \
    '{"subscriptionId":$subscription_id,"clientId":$client_id,"clientSecret":$client_secret,"tenantId":$tenant_id}' > ~/.azure/osServicePrincipal.json
chmod 0600 ~/.azure/osServicePrincipal.json

##########
# Log into Azure using service principal credentials
az login --service-principal -u $CLIENT_ID -p $CLIENT_SECRET --tenant $TENANT_ID

if (( $? != 0 )); then
  log-error "Unable to login with provided service principal. Check credentials"
  exit 1
else
  log-info "Successfully logged in with provided service principal credentials"
fi

##########
# Create the cluster resource group if it does not already exist
if [[ $NEW_CLUSTER_RESOURCE_GROUP == true ]]; then
  az group create --name $CLUSTER_RESOURCE_GROUP \
    --location $LOCATION

  if (( $? != 0 )); then
    log-error "Unable to create cluster resource group $CLUSTER_RESOURCE_GROUP. Check service principal permissions"
    exit 1
  else
    log-info "Successfully created cluster resource group $CLUSTER_RESOURCE_GROUP"
  fi
else
  if [[ $(az group list -o table | grep $CLUSTER_RESOURCE_GROUP) ]]; then
    log-info "Located existing resource group $CLUSTER_RESOURCE_GROUP"
  else
    log-error "Unable to find existing resource group $CLUSTER_RESOURCE_GROUP"
    exit 1
  fi
fi

# Check that the cluster resource group is empty
if [[ $(az resource list -g $CLUSTER_RESOURCE_GROUP -o table | grep $CLUSTER_RESOURCE_GROUP) ]]; then
  log-error "$CLUSTER_RESOURCE_GROUP is not empty."
  exit 1
else
  log-info "Confirmed $CLUSTER_RESOURCE_GROUP is empty."
fi


##########
# Create openshift install configuration file
if [[ -f ${WORKSPACE_DIR}/install-config.yaml ]]; then 
    log-info "Removing existing OpenShift install configuration"
    rm ${WORKSPACE_DIR}/install-config.yaml
fi

log-info "Creating OpenShift install configuration"
cat << EOF >> ${WORKSPACE_DIR}/install-config.yaml
apiVersion: v1
baseDomain: ${BASE_DOMAIN} 
controlPlane: 
  hyperthreading: ${MASTER_HYPERTHREADING}   
  architecture: ${MASTER_ARCHITECTURE}
  name: master
  platform:
    azure:
      osDisk:
        diskSizeGB: ${MASTER_NODE_DISK_SIZE} 
        diskType: ${MASTER_NODE_DISK_TYPE}
      type: ${MASTER_NODE_TYPE}
      encryptionAtHost: ${HOST_ENCRYPTION}
      vmNetworkingType: ${VM_NETWORKING_TYPE}
      zones: 
        - "1"
        - "2"
        - "3"
  replicas: ${MASTER_NODE_QTY}
compute: 
- hyperthreading: ${WORKER_HYPERTHREADING} 
  architecture: ${WORKER_ARCHITECTURE}
  name: worker
  platform:
    azure:
      type: ${WORKER_NODE_TYPE}
      encryptionAtHost: ${HOST_ENCRYPTION}
      vmNetworkingType: ${VM_NETWORKING_TYPE}
      osDisk:
        diskSizeGB: ${WORKER_NODE_DISK_SIZE} 
        diskType: ${WORKER_NODE_DISK_TYPE}
      zones:
        - "1"
        - "2"
        - "3"
  replicas: ${WORKER_NODE_QTY}
metadata:
  name: ${CLUSTER_NAME} 
networking:
  clusterNetwork:
  - cidr: ${CLUSTER_CIDR}
    hostPrefix: ${CLUSTER_HOST_PREFIX}
  machineNetwork:
  - cidr: ${MACHINE_CIDR}
  networkType: ${OCP_NETWORK_TYPE}
  serviceNetwork:
  - ${SERVICE_NETWORK_CIDR}
platform:
  azure:
    baseDomainResourceGroupName: ${BASE_DOMAIN_RESOURCE_GROUP}  
    resourceGroupName: ${CLUSTER_RESOURCE_GROUP} 
    region: ${LOCATION} 
    outboundType: ${OCP_OUTBOUND_TYPE}
    cloudName: ${CLOUD_TYPE}
    networkResourceGroupName: ${NETWORK_RESOURCE_GROUP} 
    virtualNetwork: ${VNET_NAME} 
    controlPlaneSubnet: ${CONTROL_SUBNET_NAME} 
    computeSubnet: ${WORKER_SUBNET_NAME} 
    defaultMachinePlatform:
      ultraSSDCapability: ${ENABLE_ULTRADISK}
publish: ${CLUSTER_ACCESS}
pullSecret: '${PULL_SECRET}' 
sshKey: '${PUBLIC_SSH_KEY}'
EOF


###########
# Create OpenShift cluster
log-info "Creating OpenShift cluster"
log-info "Following logs from openshift-install"
if [[ $DEBUG != true ]]; then
    openshift-install create cluster --dir ${WORKSPACE_DIR}/ --log-level=info | tee -a $OUTPUT_FILE
else
    openshift-install create cluster --dir ${WORKSPACE_DIR}/ --log-level=debug | tee -a $OUTPUT_FILE
fi

if (( $? != 0 )); then
  log-error "Cluster creation failed. Refer to openshift install logs for details"
  exit 1
else
  log-info "Cluster creation successfully completed"
fi

##########
# Output cluster details

API_SERVER="$(cat ${WORKSPACE_DIR}/auth/kubeconfig  | grep server | awk '{print $2}')"
CONSOLE_URL="$(cat ${WORKSPACE_DIR}/.openshift_install.log | grep "https://console-openshift-console" | tail -1 | egrep -o 'https?://[^ ]+' | sed 's/"//g')"
CLUSTER_NAME="$(cat ${WORKSPACE_DIR}/metadata.json | jq -r '.clusterName')"
INFRA_ID="$(cat ${WORKSPACE_DIR}/metadata.json | jq -r '.infraID')"
CLUSTER_ID="$(cat ${WORKSPACE_DIR}/metadata.json | jq -r '.clusterID')"

if [[ ! -z $VAULT_NAME ]]; then

    # Ensure logged in with managed identity with access to update vault.
    az login --identity

    az keyvault secret set --name "$SECRET_NAME" --vault-name $VAULT_NAME --file ${WORKSPACE_DIR}/auth/kubeadmin-password > /dev/null
    if (( $? ! = 0 )); then
      log-error "Unable to create secret for cluster password in $VAULT_NAME"
      exit 1
    else
      log-info "Cluster password added as secret to key vault $VAULT_NAME"
    fi

    az keyvault secret set --name "kubeconfig" --vault-name $VAULT_NAME --file ${WORKSPACE_DIR}/auth/kubeconfig > /dev/null
    if (( $? ! = 0 )); then
      log-error "Unable to create secret for kubeconfig in $VAULT_NAME"
      exit 1
    else
      log-info "kubeconfig file added as secret to key vault $VAULT_NAME"
    fi

    az keyvault secret set --name "cluster-metadata" --vault-name $VAULT_NAME --file ${WORKSPACE_DIR}/metadata.json > /dev/null
    if (( $? ! = 0 )); then
      log-error "Unable to create secret for cluster metadata in $VAULT_NAME"
      exit 1
    else
      log-info "Cluster metadata added as secret to key vault $VAULT_NAME"
    fi

    jq -n -c \
        --arg apiServer $API_SERVER \
        --arg consoleURL $CONSOLE_URL \
        --arg adminUser "kubeadmin" \
        --arg clusterName $CLUSTER_NAME \
        --arg clusterId $CLUSTER_ID \
        --arg infraId $INFRA_ID \
        --arg secretName $SECRET_NAME \
        '{"clusterDetails": {"apiServer": $apiServer, "consoleURL": $consoleURL, "adminUser": $adminUser, "clusterName": $clusterName, "clusterId": $clusterId, "infraId": $infraId, "secretName": $secretName} }' \
        > $AZ_SCRIPTS_OUTPUT_PATH
else
    CLUSTER_PASSWORD="$(cat ${WORKSPACE_DIR}/auth/kubeadmin-password)"

    jq -n -c \
        --arg apiServer $API_SERVER \
        --arg consoleURL $CONSOLE_URL \
        --arg adminUser "kubeadmin" \
        --arg adminPassword $CLUSTER_PASSWORD \
        --arg clusterName $CLUSTER_NAME \
        --arg clusterId $CLUSTER_ID \
        --arg infraId $INFRA_ID \
        '{"clusterDetails": {"apiServer": $apiServer, "consoleURL": $consoleURL, "adminUser": $adminUser, "adminPassword": $adminPassword, "clusterName": $clusterName, "clusterId": $clusterId, "infraId": $infraId} }' \
        > $AZ_SCRIPTS_OUTPUT_PATH
fi

log-info "OpenShift installation successfully completed"
