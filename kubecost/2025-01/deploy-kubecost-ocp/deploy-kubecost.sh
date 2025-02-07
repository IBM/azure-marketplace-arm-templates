#!/bin/bash
#
# Script to install kubecost onto an OpenShift cluster.
# Designed to be run from an Azure CLI container
#
# Tested with image mcr.microsoft.com/azure-cli:2.60.0 and OpenShift CLI version 4.17

function log-output() {
    MSG=${1}

    if [[ -z $OUTPUT_DIR ]]; then
        OUTPUT_DIR="/mnt/azscripts/azscriptoutput"
    fi
    mkdir -p $OUTPUT_DIR

    if [[ -z $OUTPUT_FILE ]]; then
        OUTPUT_FILE="script-output.log"
    fi

    echo "$(date -u +"%Y-%m-%d %T") ${MSG}" >> ${OUTPUT_DIR}/${OUTPUT_FILE}
    echo ${MSG}
}

function log-info() {
    MSG=${1}

    log-output "INFO: $MSG"    
}

function log-error() {
    MSG=${1}

    log-output "ERROR: $MSG"
}

function oc-login() {
# Login to an OpenShift cluster. 
# Usage:
#        oc-login API_SERVER OCP_USERNAME OCP_PASSWORD BIN_DIR 
#

    if [[ -z ${1} ]] || [[ -z $API_SERVER ]]; then
        log-error "API_SERVER not passed to function oc-login"
        exit 1
    elif [[ ${1} != "" ]]; then
        API_SERVER=${1}
    fi

    if [[ -z ${2} ]] || [[ -z $OCP_USERNAME ]]; then
        log-error "OCP_USERNAME not passed to function oc-login"
        exit 1
    elif [[ ${2} != "" ]]; then
        OCP_USERNAME=${2}
    fi

    if [[ -z ${3} ]] || [[ -z $OCP_PASSWORD ]]; then
        log-error "OCP_PASSWORD not passed to function oc-login"
        exit 1
    elif [[ ${3} != "" ]]; then
        OCP_PASSWORD=${3}
    fi

    if [[ -z ${4} ]] || [[ -z $BIN_DIR ]]; then
        BIN_DIR="/usr/local/bin"
    elif [[ ${4} != "" ]]; then
        BIN_DIR="${4}"
    fi

    if ! ${BIN_DIR}/oc status 1> /dev/null 2> /dev/null; then
        log-info "Logging into OpenShift cluster $API_SERVER"

        # Below loop added to allow authentication service to start on new clusters
        count=0
        while ! ${BIN_DIR}/oc login $API_SERVER -u $OCP_USERNAME -p $OCP_PASSWORD --insecure-skip-tls-verify=true 1> /dev/null 2> /dev/null ; do
            log-info "Waiting to log into cluster. Waited $count minutes. Will wait up to 15 minutes."
            sleep 60
            count=$(( $count + 1 ))
            if (( $count > 15 )); then
                log-error "Timeout waiting to log into cluster"
                exit 1;    
            fi
        done
        log-info "Successfully logged into cluster $API_SERVER"
    else   
        CURRENT_SERVER=$(${BIN_DIR}/oc status | grep server | awk '{printf $6}' | sed -e 's#^https://##; s#/##')

        if [[ $CURRENT_SERVER == $API_SERVER ]]; then
            log-info "Already logged into cluster"
        else

            # Below loop added to allow authentication service to start on new clusters
            count=0
            while ! ${BIN_DIR}/oc login $API_SERVER -u $OCP_USERNAME -p $OCP_PASSWORD --insecure-skip-tls-verify=true > /dev/null 2>&1 ; do
                log-info "Waiting to log into cluster. Waited $count minutes. Will wait up to 15 minutes."
                sleep 60
                count=$(( $count + 1 ))
                if (( $count > 15 )); then
                    log-error "Timeout waiting to log into cluster"
                    exit 1;    
                fi
            done
            log-info "Successfully logged into cluster $API_SERVER"
        fi
    fi
}

function oc-download() {
# Download and install the Red Hat OpenShift oc cli tool 
# Usage:
#        oc-download BIN_DIR TMP_DIR OC_VERSION 
#
    
    if [[ -z ${1} ]]; then
        local BIN_DIR="/usr/local/bin"
    else
        local BIN_DIR=${1}
    fi

    if [[ -z ${2} ]]; then
        local TMP_DIR="/tmp"
    else
        local TMP_DIR=${2}
    fi

    if [[ -z ${3} ]] || [[ ${3}  == "4" ]] || [[ ${3} == "stable" ]]; then
        # Install the latest stable version. Using 4.12 to avoid issues with container compatibility.
        local OC_VERSION="stable-4.12"
        local OCP_RELEASE=12
    elif [[ ${VERSION} =~ [0-9][.][0-9]+[.][0-9]+ ]]; then
        # Install a specific version and patch level
        local OC_VERSION="${VERSION}"
        local OCP_RELEASE=$(( $(echo $VERSION | awk -F'.' '{print $2}') ))
    else
        # Install the latest stable subversion
        local OC_VERSION="stable-${3}"
        local OCP_RELEASE=$(( $(echo ${3} | awk -F'.' '{print $2}') ))
    fi

    local ARCH=$(uname -m)
    local OC_FILETYPE="linux"
    local OC_URL="https://mirror.openshift.com/pub/openshift-v4/${ARCH}/clients/ocp/${OC_VERSION}/openshift-client-${OC_FILETYPE}.tar.gz"

    if [[ -f ${BIN_DIR}/oc ]]; then
        log-info "Openshift client binary already installed"
    else
        log-info "Downloading and installing oc"
        wget -O $TMP_DIR/openshift-client.tgz $OC_URL

        if ! error=$(tar xzf ${TMP_DIR}/openshift-client.tgz -C ${TMP_DIR} oc 2>&1) ; then
            log-error "Unable to extract oc from tar file"
            log-error "$error"
            exit 1
        fi

        if ! error=$(mv ${TMP_DIR}/oc ${BIN_DIR}/oc 2>&1) ; then
            log-error "Unable to move oc to $BIN_DIR"
            log-error "$error"
            exit 1
        fi
    fi

}

function subscription_status() {
    SUB_NAMESPACE=${1}
    SUBSCRIPTION=${2}

    CSV=$(${BIN_DIR}/oc get subscription -n ${SUB_NAMESPACE} ${SUBSCRIPTION} -o json | jq -r '.status.currentCSV')
    if [[ "$CSV" == "null" ]]; then
        STATUS="PendingCSV"
    else
        STATUS=$(${BIN_DIR}/oc get csv -n ${SUB_NAMESPACE} ${CSV} -o json | jq -r '.status.phase')
    fi
    echo $STATUS
}

function wait_for_subscription() {
    SUB_NAMESPACE=${1}
    export SUBSCRIPTION=${2}
    
    # Set default timeout of 15 minutes
    if [[ -z ${3} ]]; then
        TIMEOUT=15
    else
        TIMEOUT=${3}
    fi

    export TIMEOUT_COUNT=$(( $TIMEOUT * 60 / 30 ))

    count=0;
    while [[ $(subscription_status $SUB_NAMESPACE $SUBSCRIPTION) != "Succeeded" ]]; do
        log-output "INFO: Waiting for subscription $SUBSCRIPTION to be ready. Waited $(( $count * 30 )) seconds. Will wait up to $(( $TIMEOUT_COUNT * 30 )) seconds."
        sleep 30
        count=$(( $count + 1 ))
        if (( $count > $TIMEOUT_COUNT )); then
            log-output "ERROR: Timeout exceeded waiting for subscription $SUBSCRIPTION to be ready"
            exit 1
        fi
    done
}

log-info "Script starting"

######
# Set defaults
if [[ -z $OCP_USERNAME ]]; then OCP_USERNAME="kubeadmin"; fi
if [[ -z $LICENSE ]]; then LICENSE="decline"; fi
if [[ -z $WORKSPACE_DIR ]]; then WORKSPACE_DIR="/mnt/azscripts/azscriptinput"; fi
if [[ -z $BIN_DIR ]]; then export BIN_DIR="/usr/local/bin"; fi
if [[ -z $TMP_DIR ]]; then TMP_DIR="${WORKSPACE_DIR}/tmp"; fi
if [[ -z $OC_VERSION ]]; then OC_VERSION="4.17"; fi    
if [[ -z $NAMESPACE ]]; then NAMESPACE="kubecost"; fi
if [[ -z $CLUSTER_NAME ]]; then CLUSTER_NAME="myCluster"; fi
if [[ -z $CHANNEL ]]; then CHANNEL=""; fi    # Will look up default from packagemanifest if not set
if [[ -z $CA_OPERAND ]]; then CA_OPERAND=""; fi    # Will look up the example cost analyzer from the packagemanifest if not set
if [[ -z $OPERAND_FILENAME ]]; then OPERAND_FILENAME="costanalyzer.json"; fi

######
# Check environment variables
ENV_VAR_NOT_SET=""

if [[ -z $API_SERVER ]]; then ENV_VAR_NOT_SET="API_SERVER"; fi
if [[ -z $OCP_PASSWORD ]]; then ENV_VAR_NOT_SET="OCP_PASSWORD"; fi

if [[ -n $ENV_VAR_NOT_SET ]]; then
    log-output "ERROR: $ENV_VAR_NOT_SET not set. Please set and retry."
    exit 1
fi

### Configure environment
# Create tmp directory
mkdir -p ${TMP_DIR}

# Install tools - oc
if [[ -f ${BIN_DIR}/oc ]]; then
    log-info "oc already installed"
else
    oc-download $BIN_DIR $TMP_DIR $OC_VERSION
fi

# Log into cluster
oc-login $API_SERVER $OCP_USERNAME $OCP_PASSWORD $BIN_DIR

# Get the default channel and available version from the package manifest in the catalog
if [[ -z $CHANNEL ]]; then
  log-info "Channel not set. Getting the default channel for the kubecost operator"
  CHANNEL=$(${BIN_DIR}/oc get packagemanifest -n openshift-marketplace kubecost-operator -o jsonpath='{.status.defaultChannel}{"\n"}')
  if [[ $? != 0 ]]; then
      log-error "Kubecost-operator package not found in package manifest in openshift-marketplace. Check Red Hat marketplace is available on cluster"
      exit 1
  fi
fi
log-info "Using Operator channel $CHANNEL"

log-info "Getting starting CSV"
STARTING_CSV=$(${BIN_DIR}/oc get packagemanifests -n openshift-marketplace kubecost-operator -o jsonpath="{.status.channels[?(.name==\"${CHANNEL}\")].entries[0].name}{\"\n\"}")
if [[ $? != 0 ]]; then
    log-error "Kubecost-operator package not found in package manifest in openshift-marketplace. Check Red Hat marketplace is available on cluster"
    exit 1
fi
log-info "Using starting CSV $STARTING_CSV"

# Get the default deployment 
if [[ -z $CA_OPERAND ]]; then
  log-info "Getting the example Cost Analyzer operand"
  # CA_OPERAND=$(${BIN_DIR}/oc get packagemanifest -n openshift-marketplace kubecost-operator -o jsonpath="{.status.channels[?(.name==\"${CHANNEL}\")].currentCSVDesc.annotations.alm-examples}" | jq '.[0]')
  ${BIN_DIR}/oc get packagemanifest -n openshift-marketplace kubecost-operator -o json | jq -r --arg channel $CHANNEL '.status.channels[] | select(.name==$channel) | .currentCSVDesc.annotations."alm-examples"' | jq '.[0]' > $WORKSPACE_DIR/$OPERAND_FILENAME
  if [[ $? != 0 ]]; then
    log-error "Unable to retrieve example operand definition"
    exit 1
  else
    log-info "Successfully retrieved operand definition"
  fi
else
  log-info "Using supplied Cost Analyzer operand"
  echo $CA_OPERAND > $WORKSPACE_DIR/$OPERAND_FILENAME
fi

# Create the namespace
if [[ ! $(${BIN_DIR}/oc get ns ${NAMESPACE} 2> /dev/null)  ]]; then
    log-info "Creating namespace"
    ${BIN_DIR}/oc create ns ${NAMESPACE} 
    if [[ $? != 0 ]]; then
        log-error "Unable to create namespace ${NAMESPACE}"
        exit 1
    else
        log-info "Successfully created namespace ${NAMESPACE}"
    fi
else
    log-info "Namespace ${NAMESPACE} already exists"
fi

# Label namespace
log-info "Labelling namespace ${NAMESPACE} to enable monitoring"
${BIN_DIR}/oc label namespace ${NAMESPACE} openshift.io/cluster-monitoring=true
if [[ $? != 0 ]]; then
    log-error "Unable to label namespace"
    exit 1
else
    log-info "Namespace labelled"
fi

# Create operatorGroup
if [[ ! $(${BIN_DIR}/oc get operatorgroup -n ${NAMESPACE} kubecost-nngns 2> /dev/null) ]]; then
    log-info "Creating Kubecost operator group"
    cat << EOF | ${BIN_DIR}/oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: kubecost-nngns
  namespace: ${NAMESPACE}
spec:
  targetNamespaces:
  - kubecost
  upgradeStrategy: Default
EOF
    if [[ $? != 0 ]]; then
        log-error "Unable to create operator group"
        exit 1
    else
        log-info "Successfully installed operator group"
    fi
else
    log-info "Operator group already installed"
fi

# Create subscription
if [[ ! $(${BIN_DIR}/oc get subscription -n ${KUBECOST} kubecost-operator 2> /dev/null) ]]; then
    log-info "Create Kubecost subscription"
    cat << EOF | ${BIN_DIR}/oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: kubecost-operator
  namespace: ${NAMESPACE}
spec:
  channel: alpha
  installPlanApproval: Automatic
  name: kubecost-operator
  source: certified-operators
  sourceNamespace: openshift-marketplace
  startingCSV: ${STARTING_CSV}
EOF
    if [[ $? != 0 ]]; then
        log-error "Unable to create subscription"
        exit 1
    else
        log-info "Subscription created"
    fi
else
    log-info "Kubecost subscription already in place"
fi

# Wait for subscription to bind to CSV
wait_for_subscription ${NAMESPACE} kubecost-operator 15
log-info "Subscription ready"

# Create operand
if [[ ! $(${BIN_DIR}/oc get costanalyzer -n ${NAMESPACE} kubecost 2> /dev/null) ]]; then
    if [[ $LICENSE == "accept" ]]; then
        log-info "Creating Kubecost operand"
        ${BIN_DIR}/oc project $NAMESPACE > /dev/null
        cat $WORKSPACE_DIR/$OPERAND_FILENAME | \
          jq --arg namespace $NAMESPACE '.metadata += {"namespace":$namespace}' | \
          jq --arg cluster_name $CLUSTER_NAME '.spec.global.assetReports.reports[0].filters[0].value |= $cluster_name' | \
          ${BIN_DIR}/oc apply -f -
        if [[ $? != 0 ]]; then
            log-error "Unable to create Kubecost operand"
            exit 1
        else
            log-info "Kubecost operand created"
        fi

        # Wait for operand to be ready
        sleep 10
        count=0;
        while [[ $(${BIN_DIR}/oc get CostAnalyzer -n ${NAMESPACE} kubecost -o json | jq -r '.status.conditions[] | select(.type=="Deployed").status') != "True" ]]; do
            log-info "Waiting for Kubecost operand to be ready. Waited $count minutes. Will wait up to 15 minutes"
            sleep 60
            count=$(( $count + 1 ))
            if (( $count > 15)); then    # Timeout set to 15 minutes
                log-error "Timeout waiting for Kubecost operand to be ready"
                exit 1
            fi
        done
    else
        log-info "License not accepted. Kubecost operand not created"
    fi
else
    log-info "Kubecost operand already in place"
fi

# Create route
log-info "Creating route"
if [[ ! $(${BIN_DIR}/oc get route -n ${NAMESPACE} kubecost-ui 2> /dev/null) ]] && [[ $LICENSE == "accept" ]]; then
    log-info "Creating Kubecost route"
    cat << EOF | ${BIN_DIR}/oc apply -f -
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: kubecost-ui
  namespace: ${NAMESPACE}
spec:
  path: /
  to:
    name: kubecost-cost-analyzer
    weight: 100
    kind: Service
  host: ''
  port:
    targetPort: tcp-frontend
  alternateBackends: []
EOF
    if [[ $? != 0 ]]; then
        log-error "Unable to create Kubecost route"
        exit 1
    else
        log-info "Created Kubecost route"
    fi
else
    log-info "Kubecost route already exists"
fi

log-info "Script completed"