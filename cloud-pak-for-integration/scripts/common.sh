#!/bin/bash

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

function az-login() {
    CLIENT_ID=${1}
    CLIENT_SECRET=${2}
    TENANT_ID=${3}
    SUBSCRIPTION_ID=${4}

    if [[ -z $CLIENT_ID ]] || [[ -z $CLIENT_SECRET ]] || [[ -z $TENANT_ID ]] || [[ -z $SUBSCRIPTION_ID ]]; then
        log-error "Incorrect usage. Supply client id, client secret, tenant id and subcription id to login"
        exit 1
    fi

    az account show > /dev/null 2>&1
    if (( $? != 0 )); then
        # Login with service principal details
        az login --service-principal -u "$CLIENT_ID" -p "$CLIENT_SECRET" -t "$TENANT_ID" > /dev/null 2>&1
        if (( $? != 0 )); then
            log-error "Unable to login to service principal. Check supplied details in credentials.properties."
            exit 1
        else
            log-info "Successfully logged on with service principal"
        fi
        az account set --subscription "$SUBSCRIPTION_ID" > /dev/null 2>&1
        if (( $? != 0 )); then
            log-error "Unable to use subscription id $SUBSCRIPTION_ID. Please check and try agian."
            exit 1
        else
            log-info "Successfully changed to subscription : $(az account show --query name -o tsv)"
        fi
    else
        log-info "Using existing Azure CLI login"
    fi
}

function oc-login-aro() {
# Login to an OpenShift cluster. Must be logged into az cli beforehand and az cli must be in PATH
# Usage:
#        oc-login ARO_CLUSTER BIN_DIR
#

    if [[ -z ${2} ]]; then
        BIN_DIR="/usr/local/bin"
    else
        BIN_DIR="${2}"
    fi

    if ! ${BIN_DIR}/oc status 1> /dev/null 2> /dev/null; then
        log-output "INFO: Logging into OpenShift cluster $ARO_CLUSTER"
        API_SERVER=$(az aro list --query "[?contains(name,'$ARO_CLUSTER')].[apiserverProfile.url]" -o tsv)
        CLUSTER_PASSWORD=$(az aro list-credentials --name $ARO_CLUSTER --resource-group $RESOURCE_GROUP --query kubeadminPassword -o tsv)
        # Below loop added to allow authentication service to start on new clusters
        count=0
        while ! ${BIN_DIR}/oc login $API_SERVER -u kubeadmin -p $CLUSTER_PASSWORD 1> /dev/null 2> /dev/null ; do
            log-output "INFO: Waiting to log into cluster. Waited $count minutes. Will wait up to 15 minutes."
            sleep 60
            count=$(( $count + 1 ))
            if (( $count > 15 )); then
                log-output "ERROR: Timeout waiting to log into cluster"
                exit 1;    
            fi
        done
        log-output "INFO: Successfully logged into cluster $ARO_CLUSTER"
    else   
        CURRENT_SERVER=$(${BIN_DIR}/oc status | grep server | awk '{printf $6}' | sed -e 's#^https://##; s#/##')
        API_SERVER=$(az aro list --query "[?contains(name,'$CLUSTER')].[apiserverProfile.url]" -o tsv)
        if [[ $CURRENT_SERVER == $API_SERVER ]]; then
            log-output "INFO: Already logged into cluster"
        else
            CLUSTER_PASSWORD=$(az aro list-credentials --name $ARO_CLUSTER --resource-group $RESOURCE_GROUP --query kubeadminPassword -o tsv)
            # Below loop added to allow authentication service to start on new clusters
            count=0
            while ! ${BIN_DIR}/oc login $API_SERVER -u kubeadmin -p $CLUSTER_PASSWORD > /dev/null 2>&1 ; do
                log-output "INFO: Waiting to log into cluster. Waited $count minutes. Will wait up to 15 minutes."
                sleep 60
                count=$(( $count + 1 ))
                if (( $count > 15 )); then
                    log-output "ERROR: Timeout waiting to log into cluster"
                    exit 1;    
                fi
            done
            log-output "INFO: Successfully logged into cluster $ARO_CLUSTER"
        fi
    fi
}

function oc-login-aro() {
# Login to an OpenShift cluster. Must be logged into az cli beforehand and az cli must be in PATH
# Usage:
#        oc-login-aro ARO_CLUSTER BIN_DIR
#

    if [[ -z ${2} ]]; then
        BIN_DIR="/usr/local/bin"
    else
        BIN_DIR="${2}"
    fi

    if ! ${BIN_DIR}/oc status 1> /dev/null 2> /dev/null; then
        log-output "INFO: Logging into OpenShift cluster $ARO_CLUSTER"
        API_SERVER=$(az aro list --query "[?contains(name,'$ARO_CLUSTER')].[apiserverProfile.url]" -o tsv)
        CLUSTER_PASSWORD=$(az aro list-credentials --name $ARO_CLUSTER --resource-group $RESOURCE_GROUP --query kubeadminPassword -o tsv)
        # Below loop added to allow authentication service to start on new clusters
        count=0
        while ! ${BIN_DIR}/oc login $API_SERVER -u kubeadmin -p $CLUSTER_PASSWORD 1> /dev/null 2> /dev/null ; do
            log-output "INFO: Waiting to log into cluster. Waited $count minutes. Will wait up to 15 minutes."
            sleep 60
            count=$(( $count + 1 ))
            if (( $count > 15 )); then
                log-output "ERROR: Timeout waiting to log into cluster"
                exit 1;    
            fi
        done
        log-output "INFO: Successfully logged into cluster $ARO_CLUSTER"
    else   
        CURRENT_SERVER=$(${BIN_DIR}/oc status | grep server | awk '{printf $6}' | sed -e 's#^https://##; s#/##')
        API_SERVER=$(az aro list --query "[?contains(name,'$CLUSTER')].[apiserverProfile.url]" -o tsv)
        if [[ $CURRENT_SERVER == $API_SERVER ]]; then
            log-output "INFO: Already logged into cluster"
        else
            CLUSTER_PASSWORD=$(az aro list-credentials --name $ARO_CLUSTER --resource-group $RESOURCE_GROUP --query kubeadminPassword -o tsv)
            # Below loop added to allow authentication service to start on new clusters
            count=0
            while ! ${BIN_DIR}/oc login $API_SERVER -u kubeadmin -p $CLUSTER_PASSWORD > /dev/null 2>&1 ; do
                log-output "INFO: Waiting to log into cluster. Waited $count minutes. Will wait up to 15 minutes."
                sleep 60
                count=$(( $count + 1 ))
                if (( $count > 15 )); then
                    log-output "ERROR: Timeout waiting to log into cluster"
                    exit 1;    
                fi
            done
            log-output "INFO: Successfully logged into cluster $ARO_CLUSTER"
        fi
    fi
}

function oc-login-ipi() {
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

function cli-download() {
    
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
        # Install the latest stable version
        local OC_VERSION="stable"
        local OCP_RELEASE=14
    elif [[ ${VERSION} =~ [0-9][.][0-9]+[.][0-9]+ ]]; then
        # Install a specific version and patch level
        local OC_VERSION="${VERSION}"
        local OCP_RELEASE=$(( $(echo $VERSION | awk -F'.' '{print $2}') ))
    else
        # Install the latest stable subversion
        local OC_VERSION="stable-${3}"
        local OCP_RELEASE=$(( $(echo ${3} | awk -F'.' '{print $2}') ))
    fi

    # Install the gettext package if not already installed
    if [[ -z $(which envsubst) ]]; then 
        log-info "Installing gettext package"
        apk add gettext > /dev/null
        if (( $? != 0 )); then
            log-error "Unable to install gettext package"
            exit 1
        fi
    fi

    # Install glibc dependency if it does not exist (needed for version 4.14 and up)
    if [[ ! -f /lib/libresolv.so.2 ]] && [[ $OCP_RELEASE -ge 14  ]]; then
        log-info "Installing glibc compatibility libraries"
        apk add gcompat > /dev/null
        if (( $? != 0 )); then
            log-error "Unable to install glibc compatibility libraries"
            exit 1
        fi
        ln -s /lib/libgcompat.so.0 /lib/libresolv.so.2
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

function reset-output() {
    if [[ -z $OUTPUT_DIR ]]; then
        OUTPUT_DIR="/mnt/azscripts/azscriptoutput"
    fi

    if [[ -z $OUTPUT_FILE ]]; then
        OUTPUT_FILE="script-output.log"
    fi

    if [[ -f ${OUTPUT_DIR}/${OUTPUT_FILE} ]]; then
        cp ${OUTPUT_DIR}/${OUTPUT_FILE} ${OUTPUT_DIR}/${OUTPUT_FILE}-$(date -u +"%Y%m%d-%H%M%S").log
        rm ${OUTPUT_DIR}/${OUTPUT_FILE}
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
        log-info "Waiting for subscription $SUBSCRIPTION to be ready. Waited $(( $count * 30 )) seconds. Will wait up to $(( $TIMEOUT_COUNT * 30 )) seconds."
        sleep 30
        count=$(( $count + 1 ))
        if (( $count > $TIMEOUT_COUNT )); then
            log-error "Timeout exceeded waiting for subscription $SUBSCRIPTION to be ready"
            exit 1
        fi
    done
}

function catalog_status() {
    # Gets the status of a catalogsource
    # Usage:
    #      catalog_status CATALOG

    CATALOG=${1}

    CAT_STATUS="$(${BIN_DIR}/oc get catalogsource -n openshift-marketplace $CATALOG -o json | jq -r '.status.connectionState.lastObservedState')"
    echo $CAT_STATUS
}

function wait_for_catalog() {
    # Waits for a catalog source to be ready
    # Usage:
    #      wait_for_catalog CATALOG [TIMEOUT]

    CATALOG=${1}
    # Set default timeout of 15 minutes
    if [[ -z ${2} ]]; then
        TIMEOUT=15
    else
        TIMEOUT=${2}
    fi

    export TIMEOUT_COUNT=$(( $TIMEOUT * 60 / 30 ))

    count=0;
    while [[ $(catalog_status $CATALOG) != "READY" ]]; do
        log-info "Waiting for catalog source $CATALOG to be ready. Waited $(( $count * 30 )) seconds. Will wait up to $(( $TIMEOUT_COUNT * 30 )) seconds."
        sleep 30
        count=$(( $count + 1 ))
        if (( $count > $TIMEOUT_COUNT )); then
            log-error "Timeout exceeded waiting for catalog source $CATALOG to be ready"
            exit 1
        fi
    done   
}

function cleanup_file() {
    FILE=${1}

    if [[ -f $FILE ]]; then
        rm $FILE
    fi
}

function download-openshift-installer() {
    local DEST_DIR=${1}
    local VERSION=${2}
    local BIN_DIR=${3}

    local ARCH=$(uname -m)
    local FILETYPE="linux"

    if [[ -z $VERSION ]] || [[ ${VERSION}  == "4" ]]; then
        # Install the latest stable version
        local OCP_VERSION="stable"
        local OCP_RELEASE=14
    elif [[ ${VERSION} =~ [0-9][.][0-9]+[.][0-9]+ ]]; then
        # Install a specific version and patch level
        local OCP_VERSION="${VERSION}"
        local OCP_RELEASE=$(( $(echo $VERSION | awk -F'.' '{print $2}') ))
    else
        # Install the latest stable subversion
        local OCP_VERSION="stable-${VERSION}"
        local OCP_RELEASE=$(( $(echo $VERSION | awk -F'.' '{print $2}') ))
    fi

    # Install glibc dependency if it does not exist (needed for version 4.14 and up)
    if [[ ! -f /lib/libresolv.so.2 ]] && [[ $OCP_RELEASE -ge 14  ]]; then
      log-info "Installing glibc compatibility libraries"
      apk add gcompat > /dev/null
      if (( $? != 0 )); then
        log-error "Unable to install glibc compatibility libraries"
        exit 1
      fi
      ln -s /lib/libgcompat.so.0 /lib/libresolv.so.2
    fi

    URL="https://mirror.openshift.com/pub/openshift-v4/${ARCH}/clients/ocp/${OCP_VERSION}/openshift-install-${FILETYPE}.tar.gz"

    if [[ -z ${BIN_DIR} ]]; then
        local BIN_DIR="$(pwd)"
        log-info "Setting openshift-install binary installation directory to $BIN_DIR"
    else
        log-info "Openshift-install binary installation directory is set to $BIN_DIR"
    fi

    if [[ -f ${BIN_DIR}/openshift-install ]]; then
        log-info "Openshift install binary already installed"
    else
        if [[ -z ${DEST_DIR} ]]; then
            local DEST_DIR="$(pwd)"
            log-info "Setting openshift-install download directory to $DEST_DIR"
        else
            log-info "Openshift-install download directory is set to $DEST_DIR"
        fi

        log-info "Downloading OpenShift installer CLI version $OCP_VERSION"
        curl -sLo ${DEST_DIR}/openshift-install-${FILETYPE}.tar.gz $URL
        if (( $? != 0 )); then
            log-error "Unable to download openshift installer from $URL"
            exit 1
        fi

        log-info "Extracting openshift-install"
        if ! error=$(tar xzf ${DEST_DIR}/openshift-install-${FILETYPE}.tar.gz -C ${DEST_DIR} openshift-install 2>&1) ; then
            log-error "Unable to extract openshift-install from tar file"
            log-error "$error"
            exit 1
        fi

        log-info "Moving openshift-install to $BIN_DIR"
        if ! error=$(mv ${DEST_DIR}/openshift-install ${BIN_DIR}/openshift-install 2>&1) ; then
            log-error "Unable to move openshift-install to $BIN_DIR"
            log-error "$error"
            exit 1
        fi

    fi

}
function wait-for-cluster-operators-aro() {
# Usage:
#        wait-for-cluster-operators-aro
#
    local count=0
    while [[ $(${BIN_DIR}/oc get clusteroperators -o json | jq -r '.items[].status.conditions[] | select(.type=="Available") | .status' | grep False) ]]; do
        log-info "Waiting for cluster operators to finish installation. Waited $count minutes. Will wait up to 30 minutes."
        sleep 60
        count=$(( $count + 1 ))
        if (( $count > 60 )); then
            log-error "Timeout waiting for cluster operators to be available"
            exit 1;    
        fi
    done
    log-info "All OpenShift cluster operators available"
}

function wait-for-cluster-operators-ipi() {
# Usage:
#        wait-for-cluster-operators-ipi API_SERVER OCP_USERNAME OCP_PASSWORD BIN_DIR 
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

    log-info "Checking for cluster operator status"
    # Attempt to login to cluster if not already
    if ! ${BIN_DIR}/oc status 1> /dev/null 2> /dev/null; then
        log-info "Attempting login to OpenShift cluster $API_SERVER"

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
        existing_login="no"
    else
        log-info "Already logged into cluster"
        existing_login="yes"
    fi

    # Wait for cluster operators to be available
    count=0
    while ${BIN_DIR}/oc get clusteroperators | awk '{print $4}' | grep True; do
        log-info "Waiting on cluster operators to be availabe. Waited $count minutes. Will wait up to 30 minutes."
        sleep 60
        count=$(( $count + 1 ))
        if (( $count > 30 )); then
            log-error "Timeout waiting for cluster operators to be available"
            exit 1;
        fi
    done
    log-info "Cluster operators are ready"

    # Log out of cluster to allow secure login
    # Not needed for unmanaged
    # if [[ $existing_login == "no" ]]; then
    #     log-info "Logging out of temporary cluster login"
    #     oc logout 1> /dev/null 2> /dev/null
    # fi
}

function check-aro-env-vars() {
    # Checks that the minimum environment variables for ARO have been set

    if [[ -z $ARO_CLUSTER ]]; then log-error "ARO_CLUSTER not set"; fi
    if [[ -z $RESOURCE_GROUP ]]; then log-error "RESOURCE_GROUP not set"; fi
}

function check-env-vars() {
    # Checks that the minimum environment variables for IPI have been set
    # For IPI, either set a KeyVault name and secret name, OR set the OCP_PASSWORD variable
    # Usage: check-env-vars DIST
    #    where DIST is either ARO or IPI

    local DIST=$1

    if [[ -z $DIST ]]; then
        log-error "No OpenShift distribution specified"
        return 1
    fi

    case $DIST in
    ARO)
        if [[ -z $ARO_CLUSTER ]]; then 
            log-error "Environment variable ARO_CLUSTER not set"
        fi
        if [[ -z $RESOURCE_GROUP ]]; then 
            log-error "Environment variable RESOURCE_GROUP not set"
        fi
        ;;
    IPI)
        if [[ -z $API_SERVER ]]; then 
            log-error "Environment variable API_SERVER not set"
        fi
        if [[ -z $VAULT_NAME ]]; then 
            if [[ -z $OCP_PASSWORD ]]; then 
                log-error "Environment variable OCP_PASSWORD not set"; 
            fi
        elif [[ -z $SECRET_NAME ]]; then
            log-error "Environment variable SECRET_NAME not set"
        fi
        ;;
    *)
        if [[ -z $DIST ]]; then
            log-error "No OpenShift distribution specified"
        else
            log-error "$DIST is not supported"
        fi
        ;;
    esac

    return
}

function output_cp4i_settings() {
    # Outputs the settings for the CP4I deployment script
    # Usage:
    #   output_cp4i_settings DIST
    #       where: 
    #           DIST = the Openshift distribution, ARO, IPI

    if [[ $1 == "ARO" ]]; then
        log-output "INFO: ARO Cluster is set to : $ARO_CLUSTER"
        log-output "INFO: Resource group is set to : $RESOURCE_GROUP"
    else
        log-info "OCP IPI Cluster API is set to : $API_SERVER"
        log-info "OCP Username is set to : $OCP_USERNAME"
        if [[ -z $OCP_PASSWORD ]]; then log-info "OCP Password is set"; fi
    fi
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
}