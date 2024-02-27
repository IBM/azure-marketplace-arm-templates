#!/bin/bash

source common.sh

export OUTPUT_DIR="/mnt/azscripts/azscriptoutput"
export OUTPUT_FILE="sip-script-output-$(date -u +'%Y-%m-%d-%H%M%S').log"
log-info "Script started" 

# Check required parameters
if [[ -z $RESOURCE_GROUP ]]; then log-error "RESOURCE_GROUP not defined"; exit 1; fi
if [[ -z $IBM_ENTITLEMENT_KEY ]]; then log-error "IBM_ENTITLEMENT_KEY not defined"; exit 1; fi

# Set default values
if [[ -z $TMP_DIR ]]; then TMP_DIR="$(pwd)"; fi
if [[ -z $WORKSPACE_DIR ]]; then WORKSPACE_DIR="$TMP_DIR"; fi
if [[ -z $BIN_DIR ]]; then BIN_DIR="/usr/local/bin"; fi
if [[ -z $OMS_GW_OPERATOR ]]; then OMS_GW_OPERATOR="cp.icr.io/cpopen/ibm-oms-gateway-operator-catalog:v1.0"; fi
if [[ -z $SIP_OPERATOR ]]; then SIP_OPERATOR="cp.icr.io/cpopen/ibm-oms-sip-operator-catalog:v1.0"; fi
if [[ -z $OPERATOR_NAMESPACE ]]; then OPERATOR_NAMESPACE="ibm-operators"; fi
if [[ -z $SIP_NAMESPACE ]]; then SIP_NAMESPACE="sip"; fi
if [[ -z $BASE_URI ]]; then BASE_URI="https://raw.githubusercontent.com/IBM/azure-marketplace-arm-templates"; fi
if [[ -z $BRANCH ]]; then BRANCH="main"; fi
if [[ -z $IMAGE_LIST_RH_FILENAME ]]; then IMAGE_LIST_RH_FILENAME="image-list-rh"; fi
if [[ -z $IMAGE_LIST_SIP_FILENAME ]]; then IMAGE_LIST_SIP_FILENAME="image-list-sip"; fi
if [[ -z $IMAGE_LIST_RH_URL ]]; then IMAGE_LIST_RH_URL="${BASE_URI}/${BRANCH}/sterling/scripts/common/${IMAGE_LIST_RH_FILENAME}"; fi
if [[ -z $IMAGE_LIST_SIP_URL ]]; then IMAGE_LIST_SIP_URL="${BASE_URI}/${BRANCH}/sterling/scripts/common/${IMAGE_LIST_SIP_FILENAME}"; fi
if [[ -z $SC_NAME ]]; then SC_NAME="azurefile"; fi
if [[ -z $PVC_NAME ]]; then PVC_NAME="sip1-pvc"; fi

# Download the image lists
if [[ -f ${WORKSPACE_DIR}/${IMAGE_LIST_RH_FILENAME} ]]; then
    log-info "Red Hat image list already exists"
else
    wget -q --spider $IMAGE_LIST_RH_URL
    if (( $? != 0 )); then
        log-error "Red Hat image list not found at $IMAGE_LIST_RH_URL"
        exit 1
    else
        log-info "Downloading Red Hat image list"
        wget -q -P $WORKSPACE_DIR $IMAGE_LIST_RH_URL
        if (( $? != 0 )); then
            log-error "Unable to download Red Hat image list from ${IMAGE_LIST_RH_URL}"
            exit 1
        else
            log-info "Successfully download Red Hat image list"
        fi
    fi
fi

if [[ -f ${WORKSPACE_DIR}/${IMAGE_LIST_SIP_FILENAME} ]]; then
    log-info "SIP image list already exists"
else
    wget -q --spider $IMAGE_LIST_SIP_URL 
    if (( $? != 0 )); then
        log-error "SIP image list not found at $IMAGE_LIST_SIP_URL"
        exit 1
    else
        log-info "Downloading SIP image list"
        wget -q -P $WORKSPACE_DIR $IMAGE_LIST_SIP_URL 
        if (( $? != 0 )); then
            log-error "Unable to download SIP image list from ${IMAGE_LIST_SIP_URL}"
            exit 1
        else
            log-info "Successfully download SIP image list"
        fi
    fi
fi

# Install the az cli if it is not already installed
if [[ -z $(which az) ]]; then
    log-info "Installing the az cli"
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
else
    log-info "The az cli is already installed"
fi

# Log in with the az cli if not already
az account show > /dev/null 2>&1
if (( $? != 0 )); then
    # Login with service principal details
    log-info "Logging into the Azure CLI"
    az login --identity
else
    log-info "Using existing Azure CLI login"
fi

# Install the kubectl CLI tools if not installed
if [[ -z $(which kubectl) ]] || [[ -z $(which kubelogin) ]]; then
    log-info "Installing kubectl and kubelogin CLI tools"
    if [[ $(whoami) == "root" ]]; then
        az aks install-cli
    else
        sudo az aks install-cli
    fi
else
    log-info "kubectl and kubelogin CLI tools already installed"
fi

# Install the operatorSDK if not already
if [[ -z $(which operator-sdk) ]]; then
    log-info "Installing the Oerator-SDK CLI tool"
    export ARCH=$(case $(uname -m) in x86_64) echo -n amd64 ;; aarch64) echo -n arm64 ;; *) echo -n $(uname -m) ;; esac)
    export OS=$(uname | awk '{print tolower($0)}')
    export OPERATOR_SDK_DL_URL=https://github.com/operator-framework/operator-sdk/releases/download/v1.32.0

    curl -LO ${OPERATOR_SDK_DL_URL}/operator-sdk_${OS}_${ARCH}

    if [[ $(whoami) == "root" ]]; then
        chmod +x operator-sdk_${OS}_${ARCH} && mv operator-sdk_${OS}_${ARCH} ${BIN_DIR}/operator-sdk
    else
        chmod +x operator-sdk_${OS}_${ARCH} && sudo mv operator-sdk_${OS}_${ARCH} ${BIN_DIR}/operator-sdk
    fi
else
    log-info "The Operator-SDK CLI tool is already installed"
fi

# Get the Azure Container Registry details
if [[ -z $ACR_NAME ]]; then 
    log-info "Getting list of Azure Container Registries"
    ACRS=( $(az acr list -g $RESOURCE_GROUP --query '[].loginServer' -o tsv) )
    if [ ${#ACRS[@]} -gt 1 ]; then
        log-error "More than one ACR visible. Please specify desired ACR in environment parameter"
        exit 1
    else
        ACR_NAME="${ACRS[0]}"
    fi
fi
log-info "Azure container registry is set to $ACR_NAME"
# log-info "Logging into the Azure Container Registry $ACR_NAME in resource group $RESOURCE_GROUP"
# az acr login --name $ACR_NAME


# Log into the AKS cluster
if [[ -z $AKS_CLUSTER ]]; then 
    AKS_CLUSTERS=( $(az aks list -g $RESOURCE_GROUP --query '[].name' -o tsv) )
    if [ ${#AKS_CLUSTERS[@]} -gt 1 ]; then
        log-error "More than one AKS cluster visible. Please specify desired cluster in environment parameter"
        exit 1
    else
        AKS_CLUSTER="${AKS_CLUSTERS[0]}"
    fi
fi
log-info "Logging into AKS Cluster ${AKS_CLUSTER} in resource group $RESOURCE_GROUP"
az aks get-credentials -n $AKS_CLUSTER -g $RESOURCE_GROUP

# Add OLM to the cluster
operator-sdk olm install

# Create the operator namespace
if [[ -z $(kubectl get ns | grep ${OPERATOR_NAMESPACE} ) ]]; then
    log-info "Creating namespace ${OPERATOR_NAMESPACE}"
    kubectl create namespace ${OPERATOR_NAMESPACE}
    if (( $? != 0 )); then
        log-error "Unable to create namespace $OPERATOR_NAMESPACE"
        exit 1
    else
        log-info "Successfully created namespace $OPERATOR_NAMESPACE"
    fi
else
    log-info "Namespace ${OPERATOR_NAMESPACE} already exists"
fi

# Create the OMS Gateway Operator catalog source
if [[ -z $(kubectl get catalogsource -n ${OPERATOR_NAMESPACE} | grep ibm-oms-gateway-catalog) ]]; then
    log-info "Creating Catalog Source for ibm-oms-gateway-catalog"
    cat << EOF | kubectl create -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-oms-gateway-catalog
  namespace: ${OPERATOR_NAMESPACE}
spec:
  displayName: IBM OMS Gateway Operator Catalog
  image: '${OMS_GW_OPERATOR}' 
  publisher: IBM
  sourceType: grpc 
  updateStrategy:
    registryPoll:
      interval: 10m0s
EOF
    if (( $? != 0 )); then
        log-error "Unable to create catalog source for ibm-oms-gateway-catalog"
        exit 1
    else
        log-info "Created catalog source for ibm-oms-gateway-catalog"
    fi
else
    log-info "Catalog source for ibm-oms-gateway-catalog already exists"
fi

# Create the SIP Operator Catalog Source
if [[ -z $(kubectl get catalogsource -n ${OPERATOR_NAMESPACE} | grep ibm-sip-catalog) ]]; then
    log-info "Creating Catalog Source for ibm-sip-catalog"
    cat << EOF | kubectl create -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-sip-catalog
  namespace: ${OPERATOR_NAMESPACE}
spec:
  displayName: IBM SIP Operator Catalog
  image: '${SIP_OPERATOR}' 
  publisher: IBM
  sourceType: grpc 
  updateStrategy:
    registryPoll:
      interval: 10m0s
EOF
    if (( $? != 0 )); then
        log-error "Unable to create catalog source for ibm-sip-catalog"
        exit 1
    else
        log-info "Created catalog source for ibm-sip-catalog"
    fi
else
    log-info "Catalog source for ibm-sip-catalog already exists"
fi

# Create the operator group
if [[ -z $(kubectl get operatorgroup -n ${OPERATOR_NAMESPACE} | grep sip-operator-global) ]]; then
    log-info "Creating operator group sip-operator-global in namespace ${OPERATOR_NAMESPACE}"
    cat << EOF | kubectl create -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: sip-operator-global
  namespace: ${OPERATOR_NAMESPACE}
spec: {}
EOF
    if (( $? != 0 )); then
        log-error "Unable to create operator group sip-operator-global in namespace ${OPERATOR_NAMESPACE}"
        exit 1
    else
        log-info "Created operator group sip-operator-global in namespace ${OPERATOR_NAMESPACE}"
    fi
else
    log-info "Operator group sip-operator-global already exists in namespace ${OPERATOR_NAMESPACE}"
fi

# Create the OMS Gateway operator
if [[ -z $(kubectl get subscription -n ${OPERATOR_NAMESPACE} | grep oms-gateway-subscription) ]]; then 
    log-info "Creating subscription oms-gateway-subscription in namespace ${OPERATOR_NAMESPACE}"
    cat << EOF | kubectl create -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: oms-gateway-subscription
  namespace: ${OPERATOR_NAMESPACE}
spec:
  channel: v1.0
  installPlanApproval: Automatic
  name: ibm-oms-gateway
  source: ibm-oms-gateway-catalog
  sourceNamespace: ${OPERATOR_NAMESPACE}
EOF
    if (( $? != 0 )); then
        log-error "Unable to create subscription oms-gateway-subscription in namespace ${OPERATOR_NAMESPACE}"
        exit 1
    else
        log-info "Created subscription oms-gateway-subscription in namespace ${OPERATOR_NAMESPACE}"
    fi
else
    log-info "Subscription oms-gateway-subscription already exists in namespace ${OPERATOR_NAMESPACE}"
fi

# Create the SIP operator
if [[ -z $(kubectl get subscription -n ${OPERATOR_NAMESPACE} | grep sip-subscription) ]]; then
    log-info "Creating subscription sip-subscription in namespace ${OPERATOR_NAMESPACE}"
    cat << EOF | kubectl create -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: sip-subscription
  namespace: ${OPERATOR_NAMESPACE}
spec:
  channel: v1.0
  installPlanApproval: Automatic
  name: ibm-sip
  source: ibm-sip-catalog
  sourceNamespace: ${OPERATOR_NAMESPACE}
EOF
    if (( $? != 0 )); then
        log-error "Unable to create subscription sip-subscription in namespace ${OPERATOR_NAMESPACE}"
        exit 1
    else
        log-info "Created subscription sip-subscription in namespace ${OPERATOR_NAMESPACE}"
    fi
else
    log-info "Subscription sip-subscription already exists in namespace ${OPERATOR_NAMESPACE}"
fi

# Create the operand namespace
if [[ -z $(kubectl get namespace | grep ${SIP_NAMESPACE}) ]]; then
    log-info "Creating namespace ${SIP_NAMESPACE}"
    kubectl create namespace $SIP_NAMESPACE
    if (( $? != 0 )); then
        log-error "Unable to create namespace $SIP_NAMESPACE"
        exit 1
    else
        log-info "Successfully created namespace $SIP_NAMESPACE"
    fi
else
    log-info "Namespace $SIP_NAMESPACE already exists"
fi

# Upload images to the Azure Container Registry
log-info "Importing required Red Hat images to the Azure Container Registry"
while read image; do
    log-info "Importing ubi8/$image"
    az acr import \
        --name $ACR_NAME \
        --source registry.access.redhat.com/ubi8/$image \
        --image ubi8/$image
    if (( $? != 0 )); then
        log-error "Unable to import image ubi8/$image"
        exit 1
    else
        log-info "Successfully imported image ubi8/$image"
    fi
done < ${WORKSPACE_DIR}/${IMAGE_LIST_RH_FILENAME}

log-info "Importing required SIP images to the Azure Container Registry"
while read image; do
    log-info "Importing cp/ibm-oms-enterprise/$image"
    az acr import \
        --name $ACR_NAME \
        --source cp.icr.io/cp/ibm-oms-enterprise/$image \
        --image cp/ibm-oms-enterprise/$image \
        --username cp \
        --password $IBM_ENTITLEMENT_KEY
    if (( $? != 0 )); then
        log-error "Unable to import image cp/ibm-oms-enterprise/$image"
        exit 1
    else
        log-info "Successfully imported image cp/ibm-oms-enterprise/$image"
    fi
done < ${WORKSPACE_DIR}/${IMAGE_LIST_SIP_FILENAME}

#########
# Create JWT issuer cert

# Deploy SIP instance
if [[ -z $(kubectl get sipenvironment -n $SIP_NAMESPACE | grep sip ) ]]; then
    if [[ $LICENSE == "accept" ]]; then
        if [[ -z $(kubectl get pvc -n $SIP_NAMESPACE) | grep $PVC_NAME ]]
        log-info "Creating the persistent volume $PVC_NAME in namespace $SIP_NAMESPACE"
        

        log-info "Creating SIP instance in namespace $SIP_NAMESPACE"
        cat << EOF | kubectl apply -f -
apiVersion: apps.sip.ibm.com/v1beta1
kind: SIPEnvironment
metadata:
  name: sip
  namespace: $NAMESPACE
  annotations:
    internal.sip.ibm.com/skip-ibm-entitlement-key-check: 'yes'
spec:
  license:
    accept: true
  secret: sip-secret
  serviceAccount: default
  upgradeStrategy: RollingUpdate
  # This networkPolicy is most open and hence least secure. You have been warned!
  networkPolicy:
    podSelector:
      matchLabels:
        none: none
    policyTypes:
      - Ingress
  ivService:
    serviceGroup: dev
  promisingService:
    serviceGroup: dev
  utilityService:
    serviceGroup: dev
  apiDocsService: {}    
  omsGateway:
    issuerSecret: jwt-configuration
    replicas: 1
    cors:
      allowedOrigins: '*'
  externalServices:
    cassandra:
      createDevInstance:
        resources:
          limits:
            cpu: '3'
            memory: 8000Mi
          requests:
            cpu: '1'
            memory: 5000Mi
      keyspace: inventory_visibility_ks
    elasticSearch:
      createDevInstance: {}
    kafka:
      createDevInstance: {}
  common:
    ingress:
      host: $FQDN
      ssl:
       enabled: true
       identitySecretName: ingress-cert
  image:
    imagePullSecrets:
    - name: ibm-entitlement-key
    - name: acr-secret
    repository: $ACR_SERVER/cp/ibm-oms-enterprise
    tag: $SIP_VERSION
  storage:
    accessMode: ReadWriteMany
    capacity: 10Gi
    name: $PVC_NAME
    storageClassName: $SC_NAME
EOF
        if (( $? != 0 )); then
            log-error "Unable to create SIP instance in namespace $SIP_NAMESPACE"
            exit 1
        else
            # Wait for instance to finish creation

            ###########
            log-info "Successfully created SIP instance in namespace $SIP_NAMESPACE"
        fi
    else
        log-info "License not accepted. Instance not created"
    fi
else
    log-info "SIP instance already exists in namespace $SIP_NAMESPACE"
fi