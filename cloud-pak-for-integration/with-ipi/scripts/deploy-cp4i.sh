#!/bin/bash

source common.sh

OUTPUT_FILE="cp4i-script-output-$(date -u +'%Y-%m-%d-%H%M%S').log"
log-info "Script started" 

#######
# Login to Azure CLI
az account show > /dev/null 2>&1
if (( $? != 0 )); then
    # Login with service principal details
    az login --identity
else
    log-info "Using existing Azure CLI login"
fi

######
# Check environment variables
ENV_VAR_NOT_SET=""

if [[ -z $API_SERVER ]]; then ENV_VAR_NOT_SET="API_SERVER"; fi
if [[ -z $VAULT_NAME ]]; then 
  if [[ -z $OCP_PASSWORD ]]; then ENV_VAR_NOT_SET="OCP_PASSWORD"; fi
elif [[ -z $SECRET_NAME ]]; then
  ENV_VAR_NOT_SET="SECRET_NAME"
else
  log-info "Will use $VAULT_NAME to retrieve secrets"
fi

if [[ -n $ENV_VAR_NOT_SET ]]; then
    log-error "$ENV_VAR_NOT_SET not set. Please set and retry."
    exit 1
fi

########
# Get the cluster credentials from the key vault if necessary
if [[ -z $OCP_PASSWORD ]] && [[ $VAULT_NAME ]]; then
  OCP_PASSWORD=$(az keyvault secret show -n "$SECRET_NAME" --vault-name $VAULT_NAME --query 'value' -o tsv)
  if (( $? != 0 )); then
    log-error "Unable to retrieve secret $SECRET_NAME from $VAULT_NAME"
    exit 1
  else
    log-info "Successfully retrieved cluster password from $SECRET_NAME in $VAULT_NAME"
  fi
fi

######
# Set defaults
if [[ -z $OCP_USERNAME ]]; then OCP_USERNAME="kubeadmin"; fi
if [[ -z $LICENSE ]]; then LICENSE="decline"; fi
if [[ -z $CLIENT_ID ]]; then CLIENT_ID=""; fi
if [[ -z $CLIENT_SECRET ]]; then CLIENT_SECRET=""; fi
if [[ -z $TENANT_ID ]]; then TENANT_ID=""; fi
if [[ -z $SUBSCRIPTION_ID ]]; then SUBSCRIPTION_ID=""; fi
if [[ -z $WORKSPACE_DIR ]]; then WORKSPACE_DIR="/workspace"; fi
if [[ -z $BIN_DIR ]]; then export BIN_DIR="/usr/local/bin"; fi
if [[ -z $TMP_DIR ]]; then TMP_DIR="${WORKSPACE_DIR}/tmp"; fi
if [[ -z $NAMESPACE ]]; then export NAMESPACE="cp4i"; fi
if [[ -z $CLUSTER_SCOPED ]]; then CLUSTER_SCOPED="false"; fi
if [[ -z $REPLICAS ]]; then REPLICAS="1"; fi
if [[ -z $STORAGE_CLASS ]]; then STORAGE_CLASS="ocs-storagecluster-cephfs"; fi
if [[ -z $INSTANCE_NAMESPACE ]]; then export INSTANCE_NAMESPACE=$NAMESPACE; fi
if [[ -z $VERSION ]]; then export VERSION="2022.2.1"; fi
if [[ -z $LICENSE_ID ]]; then export LICENSE_ID="L-RJON-CD3JKX"; fi
if [[ -z $OCP_VERSION ]]; then OCP_VERSION="stable"; fi    # This will download the latest stable client version

# Log values set
log-info "OCP IPI Cluster API is set to : $API_SERVER"
log-info "OCP Username is set to : $OCP_USERNAME"
if [[ -z $OCP_PASSWORD ]]; then log-info "OCP Password is set"; fi
log-info "License acceptance is set to : $LICENSE"
log-info "Software version is set to : $VERSION"
log-info "Software license is set to : $LICENSE_ID"
log-info "Namespace is set to : $NAMESPACE"
log-info "Instance namespace is set to : $INSTANCE_NAMESPACE"
log-info "Storage class for instance is set to : $STORAGE_CLASS"
log-info "Replicas for instance is set to : $REPLICAS"
log-info "Operator cluster scoped is : $CLUSTER_SCOPED"
log-info "Workspace directory is set to : $WORKSPACE_DIR"
log-info "Binary directory is set to : $BIN_DIR"
log-info "Temp directory is set to : $TMP_DIR"

# Catalog and operator details

# Platform UI + Common Services
PN_CASE_VERSION="1.7.10"
PN_CATALOG_IMAGE="icr.io/cpopen/ibm-integration-platform-navigator-catalog@sha256:3435a5d0e2375d0524bd3baaa0dad772280efe6cacc13665ac8b2760ad3ebb35"
PN_OPERATOR_CHANNEL="v6.0"
CS_CASE_VERSION="1.15.12"
CS_CATALOG_IMAGE="icr.io/cpopen/ibm-common-service-catalog@sha256:fbf8ef961f3ff3c98ca4687f5586741ea97085ab5b78691baa056a5d581eecf5"
CS_OPERATOR_CHANNEL="v3"

# APIC
APIC_CASE_VERSION="4.0.4"
APIC_CATALOG_IMAGE="icr.io/cpopen/ibm-apiconnect-catalog@sha256:a89b72f4794b74caec423059d0551660951c9d772d9892789d3bdf0407c3f61a"
APIC_OPERATOR_CHANNEL="v3.3"

# App Connect
APPCONNECT_CASE_VERSION="5.0.7"
APPCONNECT_CATALOG_IMAGE="icr.io/cpopen/appconnect-operator-catalog@sha256:ccb9190be75128376f64161dccfb6d64915b63207206c9b74d05611ab88125ce"
APPCONNECT_OPERATOR_CHANNEL="v5.0-lts"

# Aspera + Redis
ASPERA_CASE_VERSION="1.5.8"
ASPERA_CATALOG_IMAGE="icr.io/cpopen/aspera-hsts-catalog@sha256:ba2b97642692c627382e738328ec5e4b566555dcace34d68d0471439c1efc548"
ASPERA_OPERATOR_CHANNEL="v1.5"
REDIS_CASE_VERSION="1.6.6"
REDIS_CATALOG_IMAGE="icr.io/cpopen/ibm-cloud-databases-redis-catalog@sha256:fddf96636005a9c276aec061a3b514036ce6d79bd91fd7e242126b2f52394a78"
#REDIS_OPERATOR_CHANNEL=""  

# Event Streams
ES_CASE_VERSION="3.2.0"
ES_CATALOG_IMAGE="icr.io/cpopen/ibm-eventstreams-catalog@sha256:ac87cfecba0635a67c7d9b6c453c752cba9b631ffdd340223e547809491eb708"
ES_OPERATOR_CHANNEL="v3.2"

# Operations Dashboard
OD_CASE_VERSION="2.6.11"
OD_CATALOG_IMAGE="icr.io/cpopen/ibm-integration-operations-dashboard-catalog@sha256:756c4e3aa31c9ee9641dcdac89566d8f3a78987160d75ab010a7e0eadb91a873"
OD_OPERATOR_CHANNEL="v2.6-lts"

# Automation Assets
AA_CASE_VERSION="1.5.9"
AA_CATALOG_IMAGE="icr.io/cpopen/ibm-integration-asset-repository-catalog@sha256:1af42da7f7c8b12818d242108b4db6f87862504f1c57789213539a98720b0fed"
AA_OPERATOR_CHANNEL="v1.5"

# DataPower
DATAPOWER_CASE_VERSION="1.6.7"
DATAPOWER_CATALOG_IMAGE="icr.io/cpopen/datapower-operator-catalog@sha256:1b3e967cfa0c4615ad183ba0f19cca5f64fbad9eb833ee5dad9b480b38d80010"
DATAPOWER_OPERATOR_CHANNEL="v1.6"

# MQ
MQ_CASE_VERSION="2.0.12"
MQ_CATALOG_IMAGE="icr.io/cpopen/ibm-mq-operator-catalog@sha256:ea21ed79f877458392ac160a358f72a4b33c755220f5d9eaccfdb89ab2232a3b"
MQ_OPERATOR_CHANNEL="v2.0"

######
# Create working directories
mkdir -p ${WORKSPACE_DIR}
mkdir -p ${TMP_DIR}

#######
# Download and install CLI's if they do not already exist
if [[ ! -f ${BIN_DIR}/oc ]] || [[ ! -f ${BIN_DIR}/kubectl ]]; then
    cli-download $BIN_DIR $TMP_DIR $OCP_VERSION
fi

#####
# Wait for cluster operators to be available
wait_for_cluster_operators $API_SERVER $OCP_USERNAME $OCP_PASSWORD $BIN_DIR

#######
# Login to cluster
oc-login $API_SERVER $OCP_USERNAME $OCP_PASSWORD $BIN_DIR

######
# Create namespace if it does not exist
if [[ -z $(${BIN_DIR}/oc get namespaces | grep ${NAMESPACE}) ]]; then
    log-info "Creating namespace ${NAMESPACE}"
    ${BIN_DIR}/oc create namespace $NAMESPACE

    if (( $? != 0 )); then
      log-error "Unable to create new namespace $NAMESPACE"
      exit 1
    else
      log-info "Successfully created namespace $NAMESPACE"
    fi
else
    log-info "Using existing namespace $NAMESPACE"
fi

#######
# Create entitlement key secret for image pull if required
if [[ -z $IBM_ENTITLEMENT_KEY ]]; then
    log-info "Now setting IBM Entitlement key"
    if [[ $LICENSE == "accept" ]]; then
        log-error "License accepted but entitlement key not provided"
        exit 1
    fi
else
    if [[ -z $(${BIN_DIR}/oc get secret -n ${NAMESPACE} | grep ibm-entitlement-key) ]]; then
        log-info "Creating entitlement key secret"
        ${BIN_DIR}/oc create secret docker-registry ibm-entitlement-key --docker-server=cp.icr.io --docker-username=cp --docker-password=$IBM_ENTITLEMENT_KEY -n $NAMESPACE

        if (( $? != 0 )); then
          log-error "Unable to create entitlement key secret"
          exit 1
        else
          log-info "Successfully created entitlement key secret"
        fi
    else
        log-info "Using existing entitlement key secret"
    fi
fi

######
# Install catalog sources
if [[ -z $(${BIN_DIR}/oc get catalogsource -n openshift-marketplace | grep ibm-apiconnect-catalog) ]]; then
    log-info "Installing IBM API Connect catalog source"
    if [[ -f ${WORKSPACE_DIR}/api-connect-catalogsource.yaml ]]; then rm ${WORKSPACE_DIR}/api-connect-catalogsource.yaml; fi
    cat << EOF >> ${WORKSPACE_DIR}/api-connect-catalogsource.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-apiconnect-catalog
  namespace: openshift-marketplace
spec:
  displayName: "APIC from CASE ${APIC_CASE_VERSION}"
  image: ${APIC_CATALOG_IMAGE}
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 45m
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/api-connect-catalogsource.yaml

    if (( $? != 0 )); then
      log-error "Unable to create IBM API Connect catalog source"
      exit 1
    else
      log-info "Successfully created IBM API Connect catalog source"
    fi
else
    log-info "IBM API Connect catalog source already installed"
fi

wait_for_catalog ibm-apiconnect-catalog
log-info "Catalog source ibm-apiconnect-catalog is ready"

if [[ -z $(${BIN_DIR}/oc get catalogsource -n openshift-marketplace | grep ibm-appconnect-catalog) ]]; then
    log-info "Installed IBM App Connect catalog source"
    if [[ -f ${WORKSPACE_DIR}/app-connect-catalogsource.yaml ]]; then rm ${WORKSPACE_DIR}/app-connect-catalogsource.yaml; fi
    cat << EOF >> ${WORKSPACE_DIR}/app-connect-catalogsource.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-appconnect-catalog
  namespace: openshift-marketplace
spec:
  displayName: "App Connect from CASE ${APPCONNECT_CASE_VERSION}"
  image: ${APPCONNECT_CATALOG_IMAGE}
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 45m
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/app-connect-catalogsource.yaml

    if (( $? != 0 )); then
      log-error "Unable to create IBM App Connect catalog source"
      exit 1
    else
      log-info "Successfully created IBM App Connect catalog source"
    fi
else
    log-info "IBM App Connect catalog source already installed"
fi

wait_for_catalog ibm-appconnect-catalog
log-info "Catalog source ibm-appconnect-catalog is ready"

if [[ -z $(${BIN_DIR}/oc get catalogsource -n openshift-marketplace | grep ibm-aspera-hsts-operator-catalog) ]]; then
    log-info "Installed IBM Aspera catalog source"
    if [[ -f ${WORKSPACE_DIR}/aspera-catalogsource.yaml ]]; then rm ${WORKSPACE_DIR}/aspera-catalogsource.yaml; fi
    cat << EOF >> ${WORKSPACE_DIR}/aspera-catalogsource.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-aspera-hsts-operator-catalog
  namespace: openshift-marketplace
spec:
  displayName: "Aspera from CASE ${ASPERA_CASE_VERSION}"
  image: ${ASPERA_CATALOG_IMAGE}
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 45m
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/aspera-catalogsource.yaml

    if (( $? != 0 )); then
      log-error "Unable to create IBM Aspera catalog source"
      exit 1
    else
      log-info "Successfully created IBM Aspera catalog source"
    fi
else
    log-info "IBM Aspera catalog source already installed"
fi

wait_for_catalog ibm-aspera-hsts-operator-catalog
log-info "Catalog source ibm-aspera-hsts-operator-catalog is ready"

if [[ -z $(${BIN_DIR}/oc get catalogsource -n openshift-marketplace | grep ibm-cloud-databases-redis-catalog) ]]; then
    log-info "Installed IBM Cloud databases Redis catalog source"
    if [[ -f ${WORKSPACE_DIR}/redis-catalogsource.yaml ]]; then rm ${WORKSPACE_DIR}/redis-catalogsource.yaml; fi
    cat << EOF >> ${WORKSPACE_DIR}/redis-catalogsource.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-cloud-databases-redis-catalog
  namespace: openshift-marketplace
spec:
  displayName: "Redis from CASE ${REDIS_CASE_VERSION}"
  image: ${REDIS_CATALOG_IMAGE}
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 45m
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/redis-catalogsource.yaml

    if (( $? != 0 )); then
      log-error "Unable to create IBM Cloud databases Redis catalog source"
      exit 1
    else
      log-info "Successfully created IBM Cloud databases Redis catalog source"
    fi
else
    log-info "IBM Cloud databases Redis catalog source already installed"
fi

wait_for_catalog ibm-cloud-databases-redis-catalog
log-info "Catalog source ibm-cloud-databases-redis-catalog is ready"

if [[ -z $(${BIN_DIR}/oc get catalogsource -n openshift-marketplace | grep ibm-common-service-catalog) ]]; then
    log-info "Installing IBM Common services catalog source"
    if [[ -f ${WORKSPACE_DIR}/common-svcs-catalogsource.yaml ]]; then rm ${WORKSPACE_DIR}/common-svcs-catalogsource.yaml; fi
    cat << EOF >> ${WORKSPACE_DIR}/common-svcs-catalogsource.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-common-service-catalog
  namespace: openshift-marketplace
spec:
  displayName: "IBM Foundation Services from CASE ${CS_CASE_VERSION}"
  image: ${CS_CATALOG_IMAGE}
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 45m
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/common-svcs-catalogsource.yaml

    if (( $? != 0 )); then
      log-error "Unable to create IBM Common services catalog source"
      exit 1
    else
      log-info "Successfully created IBM Common services catalog source"
    fi
else
    log-info "IBM common services catalog source already installed"
fi

wait_for_catalog ibm-common-service-catalog
log-info "Catalog source ibm-common-service-catalog is ready"

if [[ -z $(${BIN_DIR}/oc get catalogsource -n openshift-marketplace | grep ibm-datapower-operator-catalog) ]]; then
    log-info "Installing IBM DataPower catalog source"
    if [[ -f ${WORKSPACE_DIR}/data-power-catalogsource.yaml ]]; then rm ${WORKSPACE_DIR}/data-power-catalogsource.yaml; fi
    cat << EOF >> ${WORKSPACE_DIR}/data-power-catalogsource.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-datapower-operator-catalog
  namespace: openshift-marketplace
spec:
  displayName: "DataPower from CASE ${DATAPOWER_CASE_VERSION}"
  image: ${DATAPOWER_CATALOG_IMAGE}
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 45m
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/data-power-catalogsource.yaml

    if (( $? != 0 )); then
      log-error "Unable to create IBM DataPower catalog source"
      exit 1
    else
      log-info "Successfully created IBM DataPower catalog source"
    fi
else
    log-info "IBM DataPower catalog source already installed"
fi

wait_for_catalog ibm-datapower-operator-catalog
log-info "Catalog source ibm-datapower-operator-catalog is ready"

if [[ -z $(${BIN_DIR}/oc get catalogsource -n openshift-marketplace | grep ibm-eventstreams-catalog) ]]; then
    log-info "Installing IBM Event Streams catalog source"
    if [[ -f ${WORKSPACE_DIR}/event-streams-catalogsource.yaml ]]; then rm ${WORKSPACE_DIR}/event-streams-catalogsource.yaml; fi
    cat << EOF >> ${WORKSPACE_DIR}/event-streams-catalogsource.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-eventstreams-catalog
  namespace: openshift-marketplace
spec:
  displayName: "Event Streams from CASE ${ES_CASE_VERSION}"
  image: ${ES_CATALOG_IMAGE}
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 45m
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/event-streams-catalogsource.yaml

    if (( $? != 0 )); then
      log-error "Unable to create IBM Event Streams catalog source"
      exit 1
    else
      log-info "Successfully created IBM Event Streams catalog source"
    fi
else
    log-info "IBM Event Streams catalog source already exists"
fi

wait_for_catalog ibm-eventstreams-catalog
log-info "Catalog source ibm-eventstreams-catalog is ready"

if [[ -z $(${BIN_DIR}/oc get catalogsource -n openshift-marketplace | grep ibm-integration-asset-repository-catalog) ]]; then
    log-info "Installing IBM Integration Asset Repository catalog source"
    if [[ -f ${WORKSPACE_DIR}/asset-repo-catalogsource.yaml ]]; then rm ${WORKSPACE_DIR}/asset-repo-catalogsource.yaml; fi
    cat << EOF >> ${WORKSPACE_DIR}/asset-repo-catalogsource.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-integration-asset-repository-catalog
  namespace: openshift-marketplace
spec:
  displayName: "Automation Assets from CASE ${AA_CASE_VERSION}"
  image: ${AA_CATALOG_IMAGE}
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 45m
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/asset-repo-catalogsource.yaml

    if (( $? != 0 )); then
      log-error "Unable to create IBM Integration Asset Repository catalog source"
      exit 1
    else
      log-info "Successfully created IBM Integration Asset Repository catalog source"
    fi
else
    log-info "IBM Integration Asset Repository catalog source already installed"
fi

wait_for_catalog ibm-integration-asset-repository-catalog
log-info "Catalog source ibm-integration-asset-repository-catalog is ready"

if [[ -z $(${BIN_DIR}/oc get catalogsource -n openshift-marketplace | grep ibm-integration-operations-dashboard-catalog) ]]; then
    log-info "Installing IBM Integration Operations Dashboard catalog source"
    if [[ -f ${WORKSPACE_DIR}/ops-dashboard-catalogsource.yaml ]]; then rm ${WORKSPACE_DIR}/ops-dashboard-catalogsource.yaml; fi
    cat << EOF >> ${WORKSPACE_DIR}/ops-dashboard-catalogsource.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-integration-operations-dashboard-catalog
  namespace: openshift-marketplace
spec:
  displayName: "Operations Dashboard from CASE ${OD_CASE_VERSION}"
  image: ${OD_CATALOG_IMAGE}
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 45m
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/ops-dashboard-catalogsource.yaml

    if (( $? != 0 )); then
      log-error "Unable to create IBM Integration Operations Dashboard catalog source"
      exit 1
    else
      log-info "Successfully created IBM Integration Operations Dashboard catalog source"
    fi
else
    log-info "IBM Integration Operations Dashboard catalog source already installed"
fi

wait_for_catalog ibm-integration-operations-dashboard-catalog
log-info "Catalog source ibm-integration-operations-dashboard-catalog is ready"

if [[ -z $(${BIN_DIR}/oc get catalogsource -n openshift-marketplace | grep ibm-integration-platform-navigator-catalog) ]]; then
    log-info "Installing IBM Integration Platform Navigator catalog source"
    if [[ -f platform-navigator-catalogsource.yaml ]]; then rm platform-navigator-catalogsource.yaml; fi
    cat << EOF >> ${WORKSPACE_DIR}/platform-navigator-catalogsource.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-integration-platform-navigator-catalog
  namespace: openshift-marketplace
spec:
  displayName: "CP4I from CASE ${PN_CASE_VERSION}"
  image: ${PN_CATALOG_IMAGE}
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 45m
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/platform-navigator-catalogsource.yaml

    if (( $? != 0 )); then
      log-error "Unable to create IBM Integration Platform Navigator catalog source"
      exit 1
    else
      log-info "Successfully created IBM Integration Platform Navigator catalog source"
    fi
else
    log-info "IBM Integration Platform Navigator catalog source already installed"
fi

wait_for_catalog ibm-integration-platform-navigator-catalog
log-info "Catalog source ibm-integration-platform-navigator-catalog is ready"

if [[ -z $(${BIN_DIR}/oc get catalogsource -n openshift-marketplace | grep ibm-mq-operator-catalog) ]]; then
    log-info "Installing IBM MQ Operator catalog source"
    if [[ -f ${WORKSPACE_DIR}/mq-catalogsource.yaml ]]; then rm ${WORKSPACE_DIR}/mq-catalogsource.yaml; fi
    cat << EOF >> ${WORKSPACE_DIR}/mq-catalogsource.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-mq-operator-catalog
  namespace: openshift-marketplace
spec:
  displayName: "MQ from CASE ${MQ_CASE_VERSION}"
  image: ${MQ_CATALOG_IMAGE}
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 45m
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/mq-catalogsource.yaml

    if (( $? != 0 )); then
      log-error "Unable to create IBM MQ Operator catalog source"
      exit 1
    else
      log-info "Successfully created IBM MQ Operator catalog source"
    fi
else
    log-info "IBM MQ catalog source already installed"
fi

wait_for_catalog ibm-mq-operator-catalog
log-info "Catalog source ibm-mq-operator-catalog is ready"

#######
# Create operator group if not using cluster scope
if [[ $CLUSTER_SCOPED != "true" ]]; then
    if [[ -z $(${BIN_DIR}/oc get operatorgroups -n ${NAMESPACE} | grep $NAMESPACE-og ) ]]; then
        log-info "Creating operator group for namespace ${NAMESPACE}"
        if [[ -f ${WORKSPACE_DIR}/operator-group.yaml ]]; then rm ${WORKSPACE_DIR}/operator-group.yaml; fi
        cat << EOF >> ${WORKSPACE_DIR}/operator-group.yaml
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ${NAMESPACE}-og
  namespace: ${NAMESPACE}
spec:
  targetNamespaces:
    - ${NAMESPACE}
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/operator-group.yaml

    if (( $? != 0 )); then
      log-error "Unable to create operator group"
      exit 1
    else
      log-info "Successfully created operator group"
    fi

    else
        log-info "Using existing operator group"
    fi
fi

######
# Create subscriptions

# IBM Common Services operator
if [[ -z $(${BIN_DIR}/oc get subscriptions -n ${NAMESPACE} | grep ibm-common-service-operator-ibm-common-service-catalog-openshift-marketplace) ]]; then
    log-info "Creating subscription for IBM Common Services"
    if [[ -f ${WORKSPACE_DIR}/common-services-sub.yaml ]]; then rm ${WORKSPACE_DIR}/common-services-sub.yaml; fi
    cat << EOF >> ${WORKSPACE_DIR}/common-services-sub.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-common-service-operator-ibm-common-service-catalog-openshift-marketplace
spec:
  installPlanApproval: Automatic
  name: ibm-common-service-operator
  source: ibm-common-service-catalog
  sourceNamespace: openshift-marketplace
  channel: ${CS_OPERATOR_CHANNEL}
EOF
    ${BIN_DIR}/oc create -n ${NAMESPACE} -f ${WORKSPACE_DIR}/common-services-sub.yaml

    if (( $? != 0 )); then
      log-error "Unable to create IBM Common Services subscription"
      exit 1
    else
      log-info "Successfully created IBM Common Services subscription"
    fi
else
    log-info "IBM Common Services subscription already exists"
fi

wait_for_subscription ${NAMESPACE} ibm-common-service-operator-ibm-common-service-catalog-openshift-marketplace 15
log-info "IBM Common Services subscription ready"

# IBM Cloud Redis Databases
if [[ -z $(${BIN_DIR}/oc get subscriptions -n ${NAMESPACE} | grep ibm-cloud-databases-redis-operator-ibm-cloud-databases-redis-catalog-openshift-marketplace) ]]; then
    log-info "Creating subscription for IBM Cloud Redis databases"
    if [[ -f ${WORKSPACE_DIR}/ibm-cloud-redis-subscription.yaml ]]; then rm ${WORKSPACE_DIR}/ibm-cloud-redis-subscription.yaml; fi
    cat << EOF >> ${WORKSPACE_DIR}/ibm-cloud-redis-subscription.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-cloud-databases-redis-operator-ibm-cloud-databases-redis-catalog-openshift-marketplace
spec:
  installPlanApproval: Automatic
  name: ibm-cloud-databases-redis-operator
  source: ibm-cloud-databases-redis-catalog
  sourceNamespace: openshift-marketplace
EOF
    ${BIN_DIR}/oc create -n ${NAMESPACE} -f ${WORKSPACE_DIR}/ibm-cloud-redis-subscription.yaml

    if (( $? != 0 )); then
      log-error "Unable to create IBM Cloud Redis databases subscription"
      exit 1
    else
      log-info "Successfully created IBM Cloud Redis databases subscription"
    fi
else
    log-info "IBM Cloud Redis databases subscription already exists"
fi

wait_for_subscription ${NAMESPACE} ibm-cloud-databases-redis-operator-ibm-cloud-databases-redis-catalog-openshift-marketplace 15
log-info "IBM Cloud Redis databases subscription ready"

# Platform Navigator subscription
if [[ -z $(${BIN_DIR}/oc get subscriptions -n ${NAMESPACE} | grep ibm-integration-platform-navigator-ibm-integration-platform-navigator-catalog-openshift-marketplace) ]]; then
    log-info "Creating subscription for IBM Integration Platform Navigator"
    if [[ -f ${WORKSPACE_DIR}/platform-navigator-subscription.yaml ]]; then rm ${WORKSPACE_DIR}/platform-navigator-subscription.yaml; fi
    cat << EOF >> ${WORKSPACE_DIR}/platform-navigator-subscription.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-integration-platform-navigator-ibm-integration-platform-navigator-catalog-openshift-marketplace
spec:
  installPlanApproval: Automatic
  name: ibm-integration-platform-navigator
  source: ibm-integration-platform-navigator-catalog
  sourceNamespace: openshift-marketplace
  channel: ${PN_OPERATOR_CHANNEL}
EOF
    ${BIN_DIR}/oc create -n ${NAMESPACE} -f ${WORKSPACE_DIR}/platform-navigator-subscription.yaml

    if (( $? != 0 )); then
      log-error "Unable to create IBM Integration Platform Navigator subscription"
      exit 1
    else
      log-info "Successfully created IBM Integration Platform Navigator subscription"
    fi
else
    log-info "IBM Integration Platform Navigator subscription already exists"
fi

wait_for_subscription ${NAMESPACE} ibm-integration-platform-navigator-ibm-integration-platform-navigator-catalog-openshift-marketplace 15
log-info "IBM Integration Platform Navigator subscription ready"

# Aspera
if [[ -z $(${BIN_DIR}/oc get subscriptions -n ${NAMESPACE} | grep aspera-hsts-operator-ibm-aspera-hsts-operator-catalog-openshift-marketplace) ]]; then
    log-info "Creating subscription for IBM Aspera"
    if [[ -f ${WORKSPACE_DIR}/aspera-subscription.yaml ]]; then rm ${WORKSPACE_DIR}/aspera-subscription.yaml; fi
    cat << EOF >> ${WORKSPACE_DIR}/aspera-subscription.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: aspera-hsts-operator-ibm-aspera-hsts-operator-catalog-openshift-marketplace
spec:
  installPlanApproval: Automatic
  name: aspera-hsts-operator
  source: ibm-aspera-hsts-operator-catalog
  sourceNamespace: openshift-marketplace
  channel: ${ASPERA_OPERATOR_CHANNEL}
EOF
    ${BIN_DIR}/oc create -n ${NAMESPACE} -f ${WORKSPACE_DIR}/aspera-subscription.yaml

    if (( $? != 0 )); then
      log-error "Unable to create IBM Aspera subscription"
      exit 1
    else
      log-info "Successfully created IBM Aspera subscription"
    fi
else
    log-info "IBM Aspera subscription already exists"
fi

wait_for_subscription ${NAMESPACE} aspera-hsts-operator-ibm-aspera-hsts-operator-catalog-openshift-marketplace 15
log-info "IBM Aspera subscription ready"

# App Connection
if [[ -z $(${BIN_DIR}/oc get subscriptions -n ${NAMESPACE} | grep ibm-appconnect-ibm-appconnect-catalog-openshift-marketplace) ]]; then
    log-info "Creating subscription for IBM App Connect"
    if [[ -f ${WORKSPACE_DIR}/app-connect-subscription.yaml ]]; then rm ${WORKSPACE_DIR}/app-connect-subscription.yaml; fi
    cat << EOF >> ${WORKSPACE_DIR}/app-connect-subscription.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-appconnect-ibm-appconnect-catalog-openshift-marketplace
spec:
  installPlanApproval: Automatic
  name: ibm-appconnect
  source: ibm-appconnect-catalog
  sourceNamespace: openshift-marketplace
  channel: ${APPCONNECT_OPERATOR_CHANNEL}
EOF
    ${BIN_DIR}/oc create -n ${NAMESPACE} -f ${WORKSPACE_DIR}/app-connect-subscription.yaml

    if (( $? != 0 )); then
      log-error "Unable to create IBM App Connect subscription"
      exit 1
    else
      log-info "Successfully created IBM App Connect subscription"
    fi
else
    log-info "IBM App Connect Subscription already exists"
fi

wait_for_subscription ${NAMESPACE} ibm-appconnect-ibm-appconnect-catalog-openshift-marketplace 15
log-info "IBM App Connect subscription ready"

# Eventstreams
if [[ -z $(${BIN_DIR}/oc get subscriptions -n ${NAMESPACE} | grep ibm-eventstreams-ibm-eventstreams-catalog-openshift-marketplace) ]]; then
    log-info "Creating IBM Event Streams subscription"
    if [[ -f ${WORKSPACE_DIR}/event-streams-subscription.yaml ]]; then rm ${WORKSPACE_DIR}/event-streams-subscription.yaml; fi
    cat << EOF >> ${WORKSPACE_DIR}/event-streams-subscription.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-eventstreams-ibm-eventstreams-catalog-openshift-marketplace
spec:
  installPlanApproval: Automatic
  name: ibm-eventstreams
  source: ibm-eventstreams-catalog
  sourceNamespace: openshift-marketplace
  channel: ${ES_OPERATOR_CHANNEL}
EOF
    ${BIN_DIR}/oc create -n ${NAMESPACE} -f ${WORKSPACE_DIR}/event-streams-subscription.yaml

    if (( $? != 0 )); then
      log-error "Unable to create IBM Event Streams subscription"
      exit 1
    else
      log-info "Successfully created IBM Event Streams subscription"
    fi
else
    log-info "IBM Event Streams subscription already exists"
fi

wait_for_subscription ${NAMESPACE} ibm-eventstreams-ibm-eventstreams-catalog-openshift-marketplace 15
log-info "IBM Event Streams subscription ready"

# MQ
if [[ -z $(${BIN_DIR}/oc get subscriptions -n ${NAMESPACE} | grep ibm-mq-ibm-mq-operator-catalog-openshift-marketplace) ]]; then
    log-info "Creating subscription for IBM MQ"
    if [[ -f ${WORKSPACE_DIR}/mq-subscription.yaml ]]; then rm ${WORKSPACE_DIR}/mq-subscription.yaml; fi
    cat << EOF >> ${WORKSPACE_DIR}/mq-subscription.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-mq-ibm-mq-operator-catalog-openshift-marketplace
spec:
  installPlanApproval: Automatic
  name: ibm-mq
  source: ibm-mq-operator-catalog
  sourceNamespace: openshift-marketplace
  channel: ${MQ_OPERATOR_CHANNEL}
EOF
    ${BIN_DIR}/oc create -n ${NAMESPACE} -f ${WORKSPACE_DIR}/mq-subscription.yaml

    if (( $? != 0 )); then
      log-error "Unable to create IBM MQ subscription"
      exit 1
    else
      log-info "Successfully created IBM MQ subscription"
    fi
else
    log-info "IBM MQ subscription already exists"
fi

wait_for_subscription ${NAMESPACE} ibm-mq-ibm-mq-operator-catalog-openshift-marketplace 15
log-info "IBM MQ subscription ready"

# Asset Repo
if [[ -z $(${BIN_DIR}/oc get subscriptions -n ${NAMESPACE} | grep ibm-integration-asset-repository-ibm-integration-asset-repository-catalog-openshift-marketplace) ]]; then
    log-info "Creating subscription for IBM Integration Asset Repository"
    if [[ -f ${WORKSPACE_DIR}/asset-repo-subscription.yaml ]]; then rm ${WORKSPACE_DIR}/asset-repo-subscription.yaml; fi
    cat << EOF >> ${WORKSPACE_DIR}/asset-repo-subscription.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-integration-asset-repository-ibm-integration-asset-repository-catalog-openshift-marketplace
spec:
  installPlanApproval: Automatic
  name: ibm-integration-asset-repository
  source: ibm-integration-asset-repository-catalog
  sourceNamespace: openshift-marketplace
  channel: ${AA_OPERATOR_CHANNEL}
EOF
    ${BIN_DIR}/oc create -n ${NAMESPACE} -f ${WORKSPACE_DIR}/asset-repo-subscription.yaml

    if (( $? != 0 )); then
      log-error "Unable to create IBM Integration Asset Repository subscription"
      exit 1
    else
      log-info "Successfully created IBM Integration Asset Repository subscription"
    fi
else
    log-info "IBM Integration Asset Repository subscription already exists"
fi

wait_for_subscription ${NAMESPACE} ibm-integration-asset-repository-ibm-integration-asset-repository-catalog-openshift-marketplace 15
log-info "IBM Integration Asset Repository subscription ready"

# DataPower
if [[ -z $(${BIN_DIR}/oc get subscriptions -n ${NAMESPACE} | grep datapower-operator-ibm-datapower-operator-catalog-openshift-marketplace) ]]; then
    log-info "Creating subscription for IBM DataPower"
    if [[ -f ${WORKSPACE_DIR}/data-power-subscription.yaml ]]; then rm ${WORKSPACE_DIR}/data-power-subscription.yaml; fi
    cat << EOF >> ${WORKSPACE_DIR}/data-power-subscription.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: datapower-operator-ibm-datapower-operator-catalog-openshift-marketplace
spec:
  installPlanApproval: Automatic
  name: datapower-operator
  source: ibm-datapower-operator-catalog
  sourceNamespace: openshift-marketplace
  channel: ${DATAPOWER_OPERATOR_CHANNEL}
EOF
    ${BIN_DIR}/oc create -n ${NAMESPACE} -f ${WORKSPACE_DIR}/data-power-subscription.yaml

    if (( $? != 0 )); then
      log-error "Unable to create IBM DataPower subscription"
      exit 1
    else
      log-info "Successfully created IBM DataPower subscription"
    fi
else
    log-info "IBM DataPower subscription already exists"
fi

wait_for_subscription ${NAMESPACE} datapower-operator-ibm-datapower-operator-catalog-openshift-marketplace 15
log-info "IBM DataPower subscription ready"

# API Connect
if [[ -z $(${BIN_DIR}/oc get subscriptions -n ${NAMESPACE} | grep ibm-apiconnect-ibm-apiconnect-catalog-openshift-marketplace) ]]; then
    log-info "Creating subscription for IBM API Connect"
    if [[ -f ${WORKSPACE_DIR}/api-connect-subscription.yaml ]]; then rm ${WORKSPACE_DIR}/api-connect-subscription.yaml; fi
    cat << EOF >> ${WORKSPACE_DIR}/api-connect-subscription.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-apiconnect-ibm-apiconnect-catalog-openshift-marketplace
spec:
  installPlanApproval: Automatic
  name: ibm-apiconnect
  source: ibm-apiconnect-catalog
  sourceNamespace: openshift-marketplace
  channel: ${APIC_OPERATOR_CHANNEL}
EOF
    ${BIN_DIR}/oc create -n ${NAMESPACE} -f ${WORKSPACE_DIR}/api-connect-subscription.yaml

    if (( $? != 0 )); then
      log-error "Unable to create IBM API Connect subscription"
      exit 1
    else
      log-info "Successfully created IBM API Connect subscription"
    fi
else
    log-info "IBM API Connect subscription already exists"
fi

wait_for_subscription ${NAMESPACE} ibm-apiconnect-ibm-apiconnect-catalog-openshift-marketplace 15
log-info "IBM API Connect subscription ready"

# Operations Dashboard
if [[ -z $(${BIN_DIR}/oc get subscriptions -n ${NAMESPACE} | grep ibm-integration-operations-dashboard-ibm-integration-operations-dashboard-catalog-openshift-marketplace) ]]; then
    log-info "Creating subscription for IBM Integration Operations Dashboard"
    if [[ -f ${WORKSPACE_DIR}/ops-dashboard-subscription.yaml ]]; then rm ${WORKSPACE_DIR}/ops-dashboard-subscription.yaml; fi
    cat << EOF >> ${WORKSPACE_DIR}/ops-dashboard-subscription.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-integration-operations-dashboard-ibm-integration-operations-dashboard-catalog-openshift-marketplace
spec:
  installPlanApproval: Automatic
  name: ibm-integration-operations-dashboard
  source: ibm-integration-operations-dashboard-catalog
  sourceNamespace: openshift-marketplace
  channel: ${OD_OPERATOR_CHANNEL}
EOF
    ${BIN_DIR}/oc create -n ${NAMESPACE} -f ${WORKSPACE_DIR}/ops-dashboard-subscription.yaml

    if (( $? != 0 )); then
      log-error "Unable to create IBM Integration Operations Dashboard subscription"
      exit 1
    else
      log-info "Successfully created IBM Integration Operations Dashboard subscription"
    fi
else
    log-info "IBM Integration Operations Dashboard already exists"
fi

wait_for_subscription ${NAMESPACE} ibm-integration-operations-dashboard-ibm-integration-operations-dashboard-catalog-openshift-marketplace 15
log-info "IBM Integration Operations Dashboard ready"


######
# Create platform navigator instance
if [[ $LICENSE == "accept" ]]; then
    if [[ -z $(${BIN_DIR}/oc get PlatformNavigator -n ${INSTANCE_NAMESPACE} | grep ${INSTANCE_NAMESPACE}-navigator ) ]]; then
        log-info "Creating Platform Navigator instance"
        if [[ -f ${WORKSPACE_DIR}/platform-navigator-instance.yaml ]]; then rm ${WORKSPACE_DIR}/platform-navigator-instance.yaml; fi
        cat << EOF >> ${WORKSPACE_DIR}/platform-navigator-instance.yaml
apiVersion: integration.ibm.com/v1beta1
kind: PlatformNavigator
metadata:
  name: ${INSTANCE_NAMESPACE}-navigator
  namespace: ${INSTANCE_NAMESPACE}
spec:
  requestIbmServices:
    licensing: true
  license:
    accept: true
    license: ${LICENSE_ID}
  mqDashboard: true
  replicas: ${REPLICAS}
  version: '${VERSION}'
  storage:
    class: ${STORAGE_CLASS}
EOF
        ${BIN_DIR}/oc create -n ${INSTANCE_NAMESPACE} -f ${WORKSPACE_DIR}/platform-navigator-instance.yaml

        if (( $? != 0 )); then
          log-error "Unable to create Platform Navigator instance"
          exit 1
        else
          log-info "Successfully created Platform Navigator instance"
        fi
    else
        log-info "Platform Navigator instance already exists for namespace ${INSTANCE_NAMESPACE}"
    fi

    # Sleep 30 seconds to let navigator get created before checking status
    sleep 30

    count=0
    while [[ $(oc get PlatformNavigator -n ${INSTANCE_NAMESPACE} ${INSTANCE_NAMESPACE}-navigator -o json | jq -r '.status.conditions[] | select(.type=="Ready").status') != "True" ]]; do
        log-info "Waiting for Platform Navigator instance to be ready. Waited $count minutes. Will wait up to 90 minutes."
        sleep 60
        count=$(( $count + 1 ))
        if (( $count > 90)); then    # Timeout set to 90 minutes
            log-error "Timout waiting for ${INSTANCE_NAMESPACE}-navigator to be ready"
            exit 1
        fi
    done

    log-info "Instance started"
else
    log-info "License not accepted. Please manually install desired components"
fi