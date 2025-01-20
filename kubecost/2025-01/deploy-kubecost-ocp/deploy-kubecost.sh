#!/bin/bash
#
# Script to install kubecost onto an OpenShift cluster.
# Designed to be run from an Azure CLI container
#
# Tested with image mcr.microsoft.com/azure-cli:2.64.0 and OpenShift CLI version 4.17

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
        curl -sLo $TMP_DIR/openshift-client.tgz $OC_URL

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

function helm-download() {

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

    if [[ -z ${3} ]]; then
        local HELM_VERSION="v3.4.1"
    else
        local HELM_VERSION="${3}"
    fi

    log-info "Downloading Helm"
    curl -Lo ${TMP_DIR}/helm.tgz https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz
    if [[ $? != 0 ]]; then
        log-error "Unable to download helm version ${HELM_VERSION} from https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
        exit 1
    else
        log-info "Successfully downloaded helm"
    fi

    log-info "Unpacking helm"
    tar -zxvf ${TMP_DIR}/helm.tgz -C ${TMP_DIR}
    if [[ $? != 0 ]]; then
        log-error "Unable to unpack helm tar file ${TMP_DIR}/helm.tgz"
        exit 1
    else
        log-info "Helm unpacked"
    fi

    log-info "Moving helm to bin directory"
    mv ${TMP_DIR}/linux-amd64/helm ${BIN_DIR}/helm
    if [[ $? != 0 ]]; then
        log-error "Unable to move ${TMP_DIR}/linux-amd64/helm to ${BIN_DIR}/helm"
        exit 1
    else
        log-info "Moved helm to ${BIN_DIR}"
    fi
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
if [[ -z $HELM_VERSION ]]; then HELM_VERSION="v3.4.1"; fi

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

# Install tar and jq
log-info "Installing tar and awk tools"
yum install -y tar awk

# Install tools - helm
if [[ -f ${BIN_DIR}/helm ]]; then
    log-info "Helm already installed"
else
    helm-download $BIN_DIR $TMP_DIR $HELM_VERSION
fi

# Install tools - oc
if [[ -f ${BIN_DIR}/oc ]]; then
    log-info "oc already installed"
else
    oc-download $BIN_DIR $TMP_DIR $OC_VERSION
fi

# Log into cluster
oc-login $API_SERVER $OCP_USERNAME $OCP_PASSWORD $BIN_DIR

### Install Kubecost
# Run helm chart
if [[ $LICENSE == "accept" ]]; then
    log-info "Installing Kubecost"
    helm install kubecost cost-analyzer \
        --repo https://kubecost.github.io/cost-analyzer/ \
        --namespace kubecost --create-namespace \
        --set kubecostToken="${KUBECOST_TOKEN}"
    if [ $? != 0 ]; then
        log-error "Error installing Kubecost"
        exit 1
    else
        log-info "Successfully installed Kubecost"
    fi
else
    log-info "License not accepted. Kubecost not installed"
fi

log-info "Script completed"