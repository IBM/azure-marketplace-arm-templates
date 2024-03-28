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
if [[ -z $STORAGE_ACCOUNT_NAME ]]; then ENV_VAR_NOT_SET="STORAGE_ACCOUNT_NAME"; fi
if [[ -z $FILE_TYPE ]]; then ENV_VAR_NOT_SET="FILE_TYPE"; fi
if [[ -z $SC_NAME ]]; then ENV_VAR_NOT_SET="SC_NAME"; fi

if [[ -n $ENV_VAR_NOT_SET ]]; then
    log-error "ERROR: Mandatory environment variable $ENV_VAR_NOT_SET not set. Please set and retry."
    exit 1
fi

#######
# Set defaults
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
    log-output "INFO: Waiting for cluster operators to finish installation. Waited $count minutes. Will wait up to 30 minutes."
    sleep 60
    count=$(( $count + 1 ))
    if (( $count > 60 )); then
        log-output "ERROR: Timeout waiting for cluster operators to be available"
        exit 1;    
    fi
done
log-output "INFO: All OpenShift cluster operators available"

#####
# Create storage class
${BIN_DIR}/oc get sc $SC_NAME 1> /dev/null 2> /dev/null
if (( $? != 0 )); then
    log-info "Creating Azure file storage"
    cat << EOF | ${BIN_DIR}/oc create -f - 1> /dev/null 2> /dev/null
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: $SC_NAME
provisioner: kubernetes.io/azure-file
mountOptions:
  - dir_mode=0777
  - file_mode=0777
  - uid=0
  - gid=0
  - mfsymlinks
  - cache=strict
  - actimeo=30
  - noperm
parameters:
  location: $LOCATION
  secretNamespace: kube-system
  skuName: $FILE_TYPE
  storageAccount: $STORAGE_ACCOUNT_NAME
  resourceGroup: $RESOURCE_GROUP
reclaimPolicy: Delete
volumeBindingMode: Immediate
EOF

    if (( $? != 0 )) ; then
        log-error "Unable to create Azure file storage class"
        exit 1
    else
        log-info "Successfully created Azure file storage class"
    fi
else
    log-info "Azure file storage already exists"
fi