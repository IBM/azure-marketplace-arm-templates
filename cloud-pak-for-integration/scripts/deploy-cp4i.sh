#!/bin/bash

source common.sh
source default-values.sh

OUTPUT_FILE="cp4i-script-output-$(date -u +'%Y-%m-%d-%H%M%S').log"
log-info "Script started" 

#######
# Login to Azure CLI
az account show > /dev/null 2>&1
if (( $? != 0 )); then
    # Login with managed identity
    az login --identity
else
    log-info "Using existing Azure CLI login"
fi

#######
# Get OpenShift distribution and check environment variables
ENV_CHECK=$(check-env-vars $OCP_DIST)
if [[ $ENV_CHECK ]]; then
    log-error "Missing environment variable. Check logs for details. Exiting."
    exit 1
fi

#######
# Import relevant CP4I version settings
case $VERSION in
    2022.2.1)   
        source version-2022-2-1.sh
        ;;
    *)         
        log-error "Unknown version $VERSION"
        exit 1
        ;;
esac

######
# Create working directories
mkdir -p ${WORKSPACE_DIR}
mkdir -p ${TMP_DIR}

#######
# Download and install CLI's if they do not already exist
if [[ ! -f ${BIN_DIR}/oc ]] || [[ ! -f ${BIN_DIR}/kubectl ]]; then
    cli-download $BIN_DIR $TMP_DIR
fi

######
# Get the cluster credentials if IPI with key vault
if [[ $OCP_DIST = "IPI" ]] && [[ -z $OCP_PASSWORD ]] && [[ $VAULT_NAME ]]; then
  OCP_PASSWORD=$(az keyvault secret show -n "$SECRET_NAME" --vault-name $VAULT_NAME --query 'value' -o tsv)
  if (( $? != 0 )); then
    log-error "Unable to retrieve secret $SECRET_NAME from $VAULT_NAME"
    exit 1
  else
    log-info "Successfully retrieved cluster password from $SECRET_NAME in $VAULT_NAME"
  fi
fi

######
# Log the scripts settings
output_cp4i_settings $OCP_DIST


#####
# Wait for cluster operators to be available and login to cluster
if [[ $OCP_DIST == "ARO" ]]; then
    oc-login-aro $ARO_CLUSTER $BIN_DIR
    wait-for-cluster-operators-aro
else
    wait-for-cluster-operators-ipi $API_SERVER $OCP_USERNAME $OCP_PASSWORD $BIN_DIR
    oc-login-ipi $API_SERVER $OCP_USERNAME $OCP_PASSWORD $BIN_DIR
fi

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

    # Output Platform Navigator console URL
    CP4I_CONSOLE=$(${BIN_DIR}/oc get route cp4i-navigator-pn -n cp4i -o jsonpath='https://{.spec.host}{"\n"}')
    jq -n -c \
      --arg cp4iConsole $CP4I_CONSOLE \
      '{"cp4iDetails": {"cp4iConsoleURL": $cp4iConsole}}' \
      > $AZ_SCRIPTS_OUTPUT_PATH

else
    log-info "License not accepted. Please manually install desired components"
fi
