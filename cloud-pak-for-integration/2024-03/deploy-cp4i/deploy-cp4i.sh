#!/bin/bash
#################################################################
#
# Script to install IBM Cloud Pak for Integration onto Azure.
#
# Instructions:
#   Set the OpenShift distribution
#   export OCP_DIST="IPI"    # For Red Hat OpenShift IPI (unmanaged)
#   export OCP_DIST="ARO"    # For Azure Red Hat OpenShift (ARO - managed)

source common.sh
source default-values.sh

OUTPUT_FILE="cp4i-script-output-$(date -u +'%Y-%m-%d-%H%M%S').log"
log-info "Script started" 

######
# Create working directories
mkdir -p ${WORKSPACE_DIR}
mkdir -p ${TMP_DIR}

#######
# Login to Azure CLI
az account show > /dev/null 2>&1
if (( $? != 0 )); then
    # Login with managed identity
    az login --identity
else
    log-info "Using existing Azure CLI login"
fi

########
# If OCP_DIST not set, predict based on other variables
if [[ -z $OCP_DIST ]]; then
  log-info "OCP_DIST not set. Predicting OCP type"
  if [[ -z $API_SERVER ]] && [[ $ARO_CLUSTER ]]; then
    OCP_DICT="ARO"
  else
    OCP_DIST="IPI"
  fi
  log-info "OCP_DIST predicted to be $OCP_DIST"
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

# Set the supplied version or use the default
if [[ -z $VERSION ]]; then
  log-info "No version specified. Will default to $DEFAULT_VERSION"
  VERSION="$DEFAULT_VERSION"
else
  log-info "Will deploy IBM Cloud Pak for Integration version $VERSION"
fi

# Set the supplied license or use the default
if [[ -z $LICENSE_ID ]]; then
  log-info "No license ID specified. Will default to $DEFAULT_LICENSE_ID"
  LICENSE_ID="$DEFAULT_LICENSE_ID"
else
  log-info "Will deploy IBM Cloud Pak for Integration version $LICENSE_ID"
fi

# Check that the version spec file exists and download
VERSION_URL="${VERSION_URI}/${BRANCH}/${VERSION_PATH}/specs-${VERSION}.json"
if [[ -f ${WORKSPACE_DIR}/specs-${VERSION}.json ]]; then
  log-info "Version file specs-${VERSION}.json exists"
else
  wget -q --spider $VERSION_URL
  if (( $? != 0 )); then
    log-error "Version specification file not found at $VERSION_URL"
    exit 1
  else
    log-info "Importing version specification file"
    wget -q -P $WORKSPACE_DIR $VERSION_URL
    if (( $? != 0 )); then
      log-error "Unable to download version file $VERSION_URL"
      exit 1
    else
      log-info "Successfully downloaded version file $VERSION_URL"
    fi
  fi
fi
SOURCE_FILE="${WORKSPACE_DIR}/specs-${VERSION}.json"

#######
# Download and install CLI's if they do not already exist
if [[ ! -f ${BIN_DIR}/oc ]]; then
  log-info "Installing oc binary"
  cli-download $BIN_DIR $TMP_DIR
else
  log-info "Using existing oc binary"
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
cat $SOURCE_FILE | jq -r '.catalogSources[].name' | while read catalog; 
do
    if [[ -z $(${BIN_DIR}/oc get catalogsource -n openshift-marketplace | grep $catalog) ]]; then
        log-info "Installing catalog source for $catalog"
        cat << EOF  | ${BIN_DIR}/oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: $catalog
  namespace: openshift-marketplace
spec:
  displayName: "$(cat $SOURCE_FILE | jq --arg CATALOG $catalog -r '.catalogSources[] | select(.name==$CATALOG) | .displayName')"
  image: $(cat $SOURCE_FILE | jq --arg CATALOG $catalog -r '.catalogSources[] | select(.name==$CATALOG) | .image')
  publisher: $(cat $SOURCE_FILE | jq --arg CATALOG $catalog -r '.catalogSources[] | select(.name==$CATALOG) | .publisher')
  sourceType: $(cat $SOURCE_FILE | jq --arg CATALOG $catalog -r '.catalogSources[] | select(.name==$CATALOG) | .sourceType')
  updateStrategy:
    registryPoll:
      interval: $(cat $SOURCE_FILE | jq --arg CATALOG $catalog -r '.catalogSources[] | select(.name==$CATALOG) | .registryPollInterval')
EOF

        if (( $? != 0 )); then
            log-info "Unable to create catalog source for $catalog"
            exit 1
        else
            log-info "Successfully created catalog source for $catalog"
        fi
    else
        log-info "Catalog source $catalog is already installed. Checking readiness"
    fi
    wait_for_catalog $catalog
    log-info "Catalog source $catalog is ready"
done

if (( $? != 0 )); then
  exit 1
fi

#######
# Create operator group if not using cluster scope
if [[ $CLUSTER_SCOPED != "true" ]]; then
    if [[ -z $(${BIN_DIR}/oc get operatorgroups -n ${NAMESPACE} 2> /dev/null | grep $NAMESPACE-og ) ]]; then
        log-info "Creating operator group for namespace ${NAMESPACE}"
        cat << EOF | ${BIN_DIR}/oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ${NAMESPACE}-og
  namespace: ${NAMESPACE}
spec:
  targetNamespaces:
    - ${NAMESPACE}
EOF

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
cat $SOURCE_FILE | jq -r '.subscriptions[].name' | while read subscription; 
do
  METADATA_NAME="$(cat $SOURCE_FILE | jq -r --arg SUBSCRIPTION "$subscription" '.subscriptions[] | select(.name==$SUBSCRIPTION) | .metadata.name')"
  PACKAGE="$(cat $SOURCE_FILE | jq -r --arg SUBSCRIPTION "$subscription" '.subscriptions[] | select(.name==$SUBSCRIPTION) | .spec.name')"
  if [[ -z $(${BIN_DIR}/oc get subscription -n $NAMESPACE $METADATA_NAME 2> /dev/null | grep " $PACKAGE " ) ]]; then 
    if [[ $CLUSTER_SCOPED != "true" ]]; then
      log-info "Creating subscription for $subscription in namespace ${NAMESPACE}"
      cat << EOF | ${BIN_DIR}/oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ${METADATA_NAME}
  namespace: ${NAMESPACE}
spec:
  installPlanApproval: $(cat $SOURCE_FILE | jq -r --arg SUBSCRIPTION "$subscription" '.subscriptions[] | select(.name==$SUBSCRIPTION) | .spec.installPlanApproval')
  name: $(cat $SOURCE_FILE | jq -r --arg SUBSCRIPTION "$subscription" '.subscriptions[] | select(.name==$SUBSCRIPTION) | .spec.name')
  source: $(cat $SOURCE_FILE | jq -r --arg SUBSCRIPTION "$subscription" '.subscriptions[] | select(.name==$SUBSCRIPTION) | .spec.source')
  sourceNamespace: openshift-marketplace
  channel: $(cat $SOURCE_FILE | jq -r --arg SUBSCRIPTION "$subscription" '.subscriptions[] | select(.name==$SUBSCRIPTION) | .spec.channel')
EOF

      if (( $? != 0 )); then
        log-error "Unable to create $subscription subscription in namespace ${NAMESPACE}"
        exit 1
      else
        log-info "Created subscription $subscription in namespace ${NAMESPACE}"
      fi
    else
      log-info "Creating subscription for $subscription (cluster scoped)"
      cat << EOF | ${BIN_DIR}/oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ${METADATA_NAME}
spec:
  installPlanApproval: $(cat $SOURCE_FILE | jq -r --arg SUBSCRIPTION "$subscription" '.subscriptions[] | select(.name==$SUBSCRIPTION) | .spec.installPlanApproval')
  name: $(cat $SOURCE_FILE | jq -r --arg SUBSCRIPTION "$subscription" '.subscriptions[] | select(.name==$SUBSCRIPTION) | .spec.name')
  source: $(cat $SOURCE_FILE | jq -r --arg SUBSCRIPTION "$subscription" '.subscriptions[] | select(.name==$SUBSCRIPTION) | .spec.source')
  sourceNamespace: openshift-marketplace
  channel: $(cat $SOURCE_FILE | jq -r --arg SUBSCRIPTION "$subscription" '.subscriptions[] | select(.name==$SUBSCRIPTION) | .spec.channel')
EOF

      if (( $? != 0 )); then
        log-error "Unable to create $subscription subscription"
        exit 1
      else
        log-info "Created subscription $subscription"
      fi
    fi
  else
    log-info "Subscription already exists for $subscription. Checking readiness"
  fi
  sleep 10
  wait_for_subscription ${NAMESPACE} $METADATA_NAME 15
  log-info "$subscription subscription is ready"
done

if (( $? != 0 )); then
  exit 1
fi


######
# Create platform navigator instance
if [[ $LICENSE == "accept" ]]; then
    if [[ -z $(${BIN_DIR}/oc get platformnavigator -n ${INSTANCE_NAMESPACE} 2> /dev/null ) ]]; then
        log-info "Creating Platform Navigator instance"

        # Check that the PN instance template file exists and download
        PN_INSTANCE_NAME="$(cat $SOURCE_FILE | jq -r '.defaults.pnInstanceYaml')"
        PN_INSTANCE_YAML_URL="${VERSION_URI}/${BRANCH}/${VERSION_PATH}/${PN_INSTANCE_NAME}"
        wget -q --spider ${PN_INSTANCE_YAML_URL}
        if (( $? != 0 )); then
          log-error "Platform Navigator template not found at ${PN_INSTANCE_YAML_URL}"
          exit 1
        else
          log-info "Importing version specification file"
          # Remove any existing file before download
          if [[ -f ${WORKSPACE_DIR}/${PN_INSTANCE_NAME} ]]; then rm ${WORKSPACE_DIR}/${PN_INSTANCE_NAME}; fi
          wget -q -P $WORKSPACE_DIR ${PN_INSTANCE_YAML_URL} 
          if (( $? != 0 )); then
            log-error "Unable to download Platform Navigator template file ${PN_INSTANCE_YAML_URL}"
            exit 1
          else
            log-info "Successfully downloaded Platform Navigator template file ${PN_INSTANCE_YAML_URL}"
          fi
        fi
        PN_TEMPLATE_FILE="${WORKSPACE_DIR}/${PN_INSTANCE_NAME}"

        envsubst < ${PN_TEMPLATE_FILE} | oc apply -f -

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

    INSTANCE_NAME="$(${BIN_DIR}/oc get platformnavigator -n ${INSTANCE_NAMESPACE} -o json | jq -r '.items[0].metadata.name')"

    count=0
    while [[ $(oc get PlatformNavigator -n ${INSTANCE_NAMESPACE} ${INSTANCE_NAME} -o json | jq -r '.status.conditions[] | select(.type=="Ready").status') != "True" ]]; do
        log-info "Waiting for Platform Navigator instance ${INSTANCE_NAME} to be ready. Waited $count minutes. Will wait up to 90 minutes."
        sleep 60
        count=$(( $count + 1 ))
        if (( $count > 90)); then    # Timeout set to 90 minutes
            log-error "Timout waiting for ${INSTANCE_NAME} in namespace ${INSTANCE_NAMESPACE} to be ready"
            exit 1
        fi
    done

    log-info "Instance started"

    # Output Platform Navigator console URL
    CP4I_CONSOLE=$(${BIN_DIR}/oc get route ${INSTANCE_NAME}-pn -n ${INSTANCE_NAMESPACE} -o jsonpath='https://{.spec.host}{"\n"}')
    jq -n -c \
      --arg cp4iConsole $CP4I_CONSOLE \
      '{"cp4iDetails": {"cp4iConsoleURL": $cp4iConsole}}' \
      > $AZ_SCRIPTS_OUTPUT_PATH

else
    log-info "License not accepted. Please manually install desired components"
fi

log-info "Deployment script completed"
