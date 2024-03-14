#!/bin/bash

source common.sh

OUTPUT_FILE="azure-file-join-script-output-$(date -u +'%Y-%m-%d-%H%M%S').log"
log-info "Script started" 

#######
# Login to Azure CLI
az account show > /dev/null 2>&1
if (( $? != 0 )); then
    # Login with service principal details
    az login --identity
    if (( $? != 0 )); then
        log-error "Unable to log into Azure CLI with system identity"
        exit 1
    fi
else
    log-info "Using existing Azure CLI login"
fi

######
# Check environment variables
ENV_VAR_NOT_SET=""
if [[ -z $ARO_CLUSTER ]]; then ENV_VAR_NOT_SET="ARO_CLUSTER"; fi
if [[ -z $RESOURCE_GROUP ]]; then ENV_VAR_NOT_SET="RESOURCE_GROUP"; fi
if [[ -z $ACR_REGISTRY ]]; then ENV_VAR_NOT_SET="ACR_REGISTRY"; fi
if [[ -z $NAMESPACE ]]; then ENV_VAR_NOT_SET="NAMESPACE"; fi

if [[ -n $ENV_VAR_NOT_SET ]]; then
    log-error "Mandatory environment variable $ENV_VAR_NOT_SET not set. Please set and retry."
    exit 1
fi

#######
# Set defaults
if [[ -z $SECRET_NAME ]]; then SECRET_NAME="acr-secret"; fi
if [[ -z $BIN_DIR ]]; then BIN_DIR="/usr/local/bin"; fi

#######
# Download and install CLI's if they do not already exist
if [[ ! -f ${BIN_DIR}/oc ]] || [[ ! -f ${BIN_DIR}/kubectl ]]; then
    cli-download $BIN_DIR $TMP_DIR
fi

#######
# Login to cluster
oc-login $ARO_CLUSTER $BIN_DIR $RESOURCE_GROUP

######
# Wait for cluster operators to finish
count=0
while [[ $(${BIN_DIR}/oc get clusteroperators -o json | jq -r '.items[].status.conditions[] | select(.type=="Available") | .status' | grep False) ]]; do
    log-info "INFO: Waiting for cluster operators to finish installation. Waited $count minutes. Will wait up to 30 minutes."
    sleep 60
    count=$(( $count + 1 ))
    if (( $count > 60 )); then
        log-error "Timeout waiting for cluster operators to be available"
        exit 1;    
    fi
done
log-info "INFO: All OpenShift cluster operators available"

######
# Get ACR credentials
log-info "Getting credentials for container registry $ACR_REGISTRY"
ACR_USERNAME=$(az acr credential show -n $ACR_REGISTRY --query 'username' -o tsv)
if (( $? != 0 )); then
    log-error "Unable to obtain username for $ACR_REGISTRY"
    exit 1
fi

ACR_PASSWORD=$(az acr credential show -n $ACR_REGISTRY --query 'passwords[0].value' -o tsv)
if (( $? != 0 )); then
    log-error "Unable to obtain password for $ACR_REGISTRY"
    exit 1
fi

#######
# Create namespace if it does not already exist
${BIN_DIR}/oc get namespace $NAMESPACE > /dev/null 2>&1
if (( $? != 0 )); then
    log-info "Creating namespace $NAMESPACE"
    ${BIN_DIR}/oc create namespace $NAMESPACE
else
    log-info "Namespace $NAMESPACE already exists"
fi

######
# Create the OpenShift secret for the container registry
${BIN_DIR}/oc get secret -n $NAMESPACE ${SECRET_NAME} > /dev/null 2>&1
if (( $? != 0 )); then
    log-info "Creating secret in Openshift for ACR $ACR_REGISTRY in namespace $NAMESPACE"
    ${BIN_DIR}/oc create secret docker-registry \
        --namespace ${NAMESPACE} \
        --docker-server=${ACR_REGISTRY}.azurecr.io \
        --docker-username=${ACR_USERNAME} \
        --docker-password=${ACR_PASSWORD} \
        --docker-email=unused \
        ${SECRET_NAME}
else
    log-info "OpenShift secret ${SECRET_NAME} in namespace $NAMESPACE already exists"
fi

#######
# Link the secret to the service account
log-info "Linking ACR secret to the default service account"
${BIN_DIR}/oc secrets link default -n $NAMESPACE ${SECRET_NAME} > /dev/null 2>&1
if (( $? != 0 )); then
    log-error "Unable to link secret to default service account"
    exit 1
fi