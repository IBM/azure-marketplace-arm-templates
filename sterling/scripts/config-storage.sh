#!/bin/bash
#######
#
# This script will configure the Azure file storage in an ARO cluster
#
#######

source common.sh

OUTPUT_FILE="storage-config-output-$(date -u +'%Y-%m-%d-%H%M%S').log"
log-info "Script started" 

######
# Check environment variables
ENV_VAR_NOT_SET=""
if [[ -z $ARO_CLUSTER ]]; then ENV_VAR_NOT_SET="ARO_CLUSTER"; fi
if [[ -z $RESOURCE_GROUP ]]; then ENV_VAR_NOT_SET="RESOURCE_GROUP"; fi
if [[ -z $STORAGE_ACCOUNT_NAME ]]; then ENV_VAR_NOT_SET="STORAGE_ACCOUNT_NAME"; fi
if [[ -z $FILE_TYPE ]]; then ENV_VAR_NOT_SET="FILE_TYPE"; fi
if [[ -z $SC_NAME ]]; then ENV_VAR_NOT_SET="SC_NAME"; fi

if [[ -n $ENV_VAR_NOT_SET ]]; then
    log-info "ERROR: Mandatory environment variable $ENV_VAR_NOT_SET not set. Please set and retry."
    exit 1
fi

#######
# Set defaults (can be overriden with environment variables)
if [[ -z $CLIENT_ID ]]; then CLIENT_ID=""; fi
if [[ -z $CLIENT_SECRET ]]; then CLIENT_SECRET=""; fi
if [[ -z $TENANT_ID ]]; then TENANT_ID=""; fi
if [[ -z $SUBSCRIPTION_ID ]]; then SUBSCRIPTION_ID=""; fi
if [[ -z $WORKSPACE_DIR ]]; then WORKSPACE_DIR="/workspace"; fi
if [[ -z $BIN_DIR ]]; then export BIN_DIR="/usr/local/bin"; fi
if [[ -z $TMP_DIR ]]; then TMP_DIR="${WORKSPACE_DIR}/tmp"; fi
if [[ -z $LOCATION ]]; then LOCATION="$(az group show --resource-group $RESOURCE_GROUP --query location -o tsv)"; fi


# Output parameters to log file before proceeding
log-info "ARO Cluster is $ARO_CLUSTER"
log-info "RESOURCE_GRUP is $RESOURCE_GROUP"
log-info "STORAGE_ACCOUNT_NAME is $STORAGE_ACCOUNT_NAME"
log-info "FILE TYPE is $FILE_TYPE"
log-info "SC_NAME is $SC_NAME"
log-info "WORKSPACE_DIR is $WORKSPACE_DIR"
log-info "TMP_DIR is $TMP_DIR"
log-info "BIN_DIR is $BIN_DIR"


######
# Create working directories
mkdir -p ${WORKSPACE_DIR}
mkdir -p ${TMP_DIR}

#####
# Download OC and kubectl
if [[ ! -f ${BIN_DIR}/oc ]] || [[ ! -f ${BIN_DIR}/kubectl ]]; then
    cli-download $BIN_DIR $TMP_DIR $OC_VERSION
fi

#######
# Login to Azure CLI
az account show > /dev/null 2>&1
if (( $? != 0 )); then
    # Login with service principal details
    az-login $CLIENT_ID $CLIENT_SECRET $TENANT_ID $SUBSCRIPTION_ID
else
    log-info "Using existing Azure CLI login"
fi

#####
# Wait for cluster operators to be available
wait_for_cluster_operators $ARO_CLUSTER $RESOURCE_GROUP $BIN_DIR

#######
# Login to cluster
oc-login $ARO_CLUSTER $BIN_DIR $RESOURCE_GROUP

#####
# Set ARO cluster permissions
if [[ $(${BIN_DIR}/oc get clusterrole | grep azure-secret-reader) ]]; then
    log-info "Using existing cluster role"
else
    log-info "creating cluster role for Azure file storage"
    if error=$(${BIN_DIR}/oc create clusterrole azure-secret-reader --verb=create,get --resource=secrets 2>&1) ; then
        log-info "Successfully created cluster role for storage"
    else
        log-error "Unable to create cluster storage role with error $error"
        exit 1
    fi
    if error=$(${BIN_DIR}/oc adm policy add-cluster-role-to-user azure-secret-reader system:serviceaccount:kube-system:persistent-volume-binder 2>&1) ; then
        log-info "Successfully created policy for cluster role"
    else
        log-error "Unable to create policy for cluster role with error $error"
        exit 1
    fi
fi

#####
# Create storage class
if [[ -z $(${BIN_DIR}/oc get sc | grep $SC_NAME) ]]; then
    log-info "Creating Azure file storage"
    cleanup_file ${WORKSPACE_DIR}/azure-storageclass-azure-file.yaml
    cat << EOF >> ${WORKSPACE_DIR}/azure-storageclass-azure-file.yaml
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

    if error=$(${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/azure-storageclass-azure-file.yaml 2>&1) ; then
        log-info "Successfully created Azure file storage class"
    else
        log-error "Unable to create Azure file storage class with error $error"
        exit 1
    fi
else
    log-info "Azure file storage already exists"
fi


