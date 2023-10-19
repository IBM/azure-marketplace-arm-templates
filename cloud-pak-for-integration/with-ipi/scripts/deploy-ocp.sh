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

source common.sh

OUTPUT_FILE="ocp-script-output-$(date -u +'%Y-%m-%d-%H%M%S').log"
log-output "INFO: Script started" 

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
if [[ -z $NETWORK_RESOURCE_GROU ]]; then ENV_VAR_NOT_SET="NETWORK_RESOURCE_GROU"; fi

if [[ -n $ENV_VAR_NOT_SET ]]; then
    log-output "ERROR: $ENV_VAR_NOT_SET not set. Please set and retry."
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

# The following can be "OVNKubernetes" (the default), or "OpenShiftSDN"
if [[ -z $OCP_NETWORK_TYPE ]]; then OCP_NETWORK_TYPE="OVNKubernetes"; fi

# The following value should be "AzureUSGovernmentCloud" for gov cloud deployments.
if [[ -z $CLOUD_TYPE ]]; then CLOUD_TYPE="AzurePublicCloud"; fi

# The following should be set to Enabled to use UltraSSD disks for persistent storage
if [[ -z $ENABLE_ULTRADISK ]]; then ENABLE_ULTRADISK="Disabled"; fi

if [[ -z $DEBUG ]]; then DEBUG=false; fi

log-output "INFO: Workspace directory is set to : $WORKSPACE_DIR"
log-output "INFO: Binary directory is set to : $BIN_DIR"
if [[ $CLIENT_ID ]]; then log-output "INFO: Client id is $CLIENT_ID"; fi
if [[ $CLIENT_SECRET ]]; then log-output "INFO: Client secret is set"; fi
log-output "INFO: Network resource group set to $NETWORK_RESOURCE_GROUP"
log-output "INFO: Virtual network name is set to $VNET_NAME"
log-output "INFO: Worker subnet name is set to $WORKER_SUBNET_NAME"
log-output "INFO: Control subnet name is set to $CONTROL_SUBNET_NAME"
log-output "INFO: OpenShift version is set to $VERSION"
log-output "INFO: Master hyperthreading is set to $MASTER_HYPERTHREADING"
log-output "INFO: Master architecture is set to $MASTER_ARCHITECTURE"
log-output "INFO: Master node disk size is set to $MASTER_NODE_DISK_SIZE"
log-output "INFO: Master node disk type is set to $MASTER_NODE_DISK_TYPE"
log-output "INFO: Master node VM type is set to $MASTER_NODE_TYPE"
log-output "INFO: Master node quantity is set to $MASTER_NODE_QTY"
log-output "INFO: Worker hyperthreading is set to $WORKER_HYPERTHREADING"
log-output "INFO: Worker architecture is set to $WORKER_ARCHITECTURE"
log-output "INFO: Worker disk size is set to $WORKER_NODE_DISK_SIZE"
log-output "INFO: Worker disk type is set to $WORKER_NODE_DISK_TYPE"
log-output "INFO: Worker node VM type is set to $WORKER_NODE_TYPE"
log-output "INFO: Worker node quantity is set to $WORKER_NODE_QTY"
log-output "INFO: Cluster name is set to $CLUSTER_NAME"
log-output "INFO: Internal OpenShift network CIDR set to $CLUSTER_CIDR"
log-output "INFO: Internal host prefix for OpenShift is set to $CLUSTER_HOST_PREFIX"
log-output "INFO: OpenShift virtual machine network CIDR is set to $MACHINE_CIDR"
log-output "INFO: OpenShift internal networking set to $OCP_NETWORK_TYPE"
log-output "INFO: OpenShift internal services network CIDR is set to $SERVICE_NETWORK_CIDR"
log-output "INFO: OpenShift outbound routing is set to $OCP_OUTBOUND_TYPE"
log-output "INFO: OpenShift ingress is set to $CLUSTER_ACCESS"
log-output "INFO: OpenShift UltraSSD is set to $ENABLE_ULTRADISK"
log-output "INFO: OpenShift cloud type is set to $CLOUD_TYPE"


#######
# Login to Azure CLI
az account show > /dev/null 2>&1
if (( $? != 0 )); then
    # Login with service principal details
    az-login $CLIENT_ID $CLIENT_SECRET $TENANT_ID $SUBSCRIPTION_ID
    SP_LOGIN=true
else
    SP_LOGIN=false
    log-output "INFO: Using existing Azure CLI login"
fi

#########
# Set location if not already
if [[ -z $LOCATION ]]; then
    LOCATION=$(az group show -n $RESOURCE_GROUP --query 'location' -o tsv)
    if (( $? != 0 )); then
        log-output "ERROR: Unable to determine location. Please set as environment variable."
        exit 1
    fi
fi
log-output "INFO: Location is set to $LOCATION"

##########
# Get environment parameters
if [[ -z $SUBSCRIPTION_ID ]]; then
    SUBSCRIPTION_ID=$(az account show --query 'id' -o tsv)
fi
log-output "INFO: Subscription Id is set to $SUBSCRIPTION_ID"

if [[ -z $TENANT_ID ]]; then
    TENANT_ID=$(az account show --query 'tenantId' -o tsv)
fi
log-output "INFO: Tenant Id is set to $TENANT_ID"

##########
# Download OpenShift installer
download-openshift-installer $WORKSPACE_DIR $VERSION $BIN_DIR

##########
# Setup Azure credentials for OpenShift
log-output "INFO: Creating Azure login credentials file"
jq --null-input \
    --arg subscription_id "${SUBSCRIPTION_ID}" \
    --arg client_id "${CLIENT_ID}" \
    --arg client_secret "${CLIENT_SECRET}" \
    --arg tenant_id "${TENANT_ID}" \
    '{"subscriptionId":$subscription_id,"clientId":$client_id,"clientSecret":$client_secret,"tenantId":$tenant_id}' > ~/.azure/osServicePrincipal.json
chmod 0600 ~/.azure/osServicePrincipal.json


##########
# Create openshift install configuration file
if [[ -f ${WORKSPACE_DIR}/install-config.json ]]; then 
    log-output "INFO: Removing existing OpenShift install configuration"
    rm ${WORKSPACE_DIR}/install-config.json
fi

log-output "INFO: Creating OpenShift install configuration"
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
    cloudName: ${$CLOUD_TYPE}
    networkResourceGroupName: ${RESOURCE_GROUP} 
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
log-output "INFO: Creating OpenShift cluster"
if [[ $DEBUG != true ]]; then
    openshift-install create cluster --dir ${WORKSPACE_DIR}/ --log-level=info  
else
    openshift-install create cluster --dir ${WORKSPACE_DIR}/ --log-level=debug
fi

##########
# Output cluster details

API_SERVER="$(cat ${WORKSPACE_DIR}/auth/kubeconfig  | grep server | awk '{print $2}')"
CONSOLE_URL="$(cat ${WORKSPACE_DIR}/.openshift_install.log | grep "https://console-openshift-console" | tail -1 | egrep -o 'https?://[^ ]+' | sed 's/"//g')"
CLUSTER_NAME="$(cat ${WORKSPACE_DIR}/metadata.json | jq -r '.clusterName')"
INFRA_ID="$(cat ${WORKSPACE_DIR}/metadata.json | jq -r '.infraID')"
CLUSTER_ID="$(cat ${WORKSPACE_DIR}/metadata.json | jq -r '.clusterID')"

if [[ ! -z $VAULT_NAME ]]; then
    az keyvault secret set --name "cluster-password" --vault-name $VAULT_NAME --file ${WORKSPACE_DIR}/auth/kubeadmin-password

    jq -n -c \
        --arg apiServer $API_SERVER \
        --arg consoleURL $CONSOLE_URL \
        --arg adminUser "kubeadmin" \
        --arg clusterName $CLUSTER_NAME \
        --arg clusterId $CLUSTER_ID \
        --arg infraId $INFRA_ID \
        '{"clusterDetails": {"apiServer": $apiServer, "consoleURL": $consoleURL, "adminUser": $adminUser, "clusterName": $clusterName, "clusterId": $clusterId, "infraId": $infraId} }' \
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

##### DEBUG ONLY. Keeps container running.
if [[ $DEBUG == true ]]; then
    while true; do 
        sleep 30; 
    done
fi