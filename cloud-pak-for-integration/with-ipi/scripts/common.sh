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
    echo $MSG >&2
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

function cli-download() {
    
    if [[ -z ${1} ]]; then
        BIN_DIR="/usr/local/bin"
    else
        BIN_DIR=${1}
    fi

    if [[ -z ${2} ]]; then
        TMP_DIR="/tmp"
    else
        TMP_DIR=${2}
    fi

    if [[ -z ${3} ]]; then
        OC_VERSION="stable-4.12"
    else
        OC_VERSION="${3}"
    fi

    # Install glibc dependency if it does not exist (needed for version 4.14 and up)
    if [[ ! -z /lib/libresolv.so.2 ]]; then
      log-info "Installing glibc compatibility libraries"
      apk add gcompat
      if (( $? != 0 )); then
        log-error "Unable to install glibc compatibility libraries"
        exit 1
      fi
      ln -s /lib/libgcompat.so.0 /lib/libresolv.so.2
    fi

    ARCH=$(uname -m)
    OC_FILETYPE="linux"
    KUBECTL_FILETYPE="linux"
    OC_URL="https://mirror.openshift.com/pub/openshift-v4/${ARCH}/clients/ocp/${OC_VERSION}/openshift-client-${OC_FILETYPE}.tar.gz"

    log-info "Downloading and installing oc and kubectl"
    curl -sLo $TMP_DIR/openshift-client.tgz $OC_URL

    if ! error=$(tar xzf ${TMP_DIR}/openshift-client.tgz -C ${TMP_DIR} oc kubectl 2>&1) ; then
        log-error "Unable to extract oc or kubectl from tar file"
        log-error "$error"
        exit 1
    fi

    if ! error=$(mv ${TMP_DIR}/oc ${BIN_DIR}/oc 2>&1) ; then
        log-error "Unable to move oc to $BIN_DIR"
        log-error "$error"
        exit 1
    fi

    if ! error=$(mv ${TMP_DIR}/kubectl ${BIN_DIR}/kubectl 2>&1) ; then
        log-error "Unable to move kubectl to $BIN_DIR"
        log-error "$error"
        exit 1
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
    DEST_DIR=${1}
    VERSION=${2}
    BIN_DIR=${3}

    ARCH=$(uname -m)
    FILETYPE="linux"

    if [[ -z $VERSION ]] || [[ ${VERSION}  == "4" ]]; then
        # Install the latest stable version
        OCP_VERSION="stable"
    elif [[ ${VERSION} =~ [0-9][.][0-9]+[.][0-9]+ ]]; then
        # Install a specific version and patch level
        OCP_VERSION="${VERSION}"
    else
        # Install the latest stable subversion
        OCP_VERSION="stable-${VERSION}"
    fi

    # Install glibc dependency if it does not exist (needed for version 4.14 and up)
    if [[ ! -z /lib/libresolv.so.2 ]]; then
      apk add gcompat
      ln -s /lib/libgcompat.so.0 /lib/libresolv.so.2
    fi

    URL="https://mirror.openshift.com/pub/openshift-v4/${ARCH}/clients/ocp/${OCP_VERSION}/openshift-install-${FILETYPE}.tar.gz"

    if [[ -z ${BIN_DIR} ]]; then
        BIN_DIR="$(pwd)"
        log-info "Setting openshift-install binary installation directory to $BIN_DIR"
    else
        log-info "Openshift-install binary installation directory is set to $BIN_DIR"
    fi

    if [[ -f ${BIN_DIR}/openshift-install ]]; then
        log-info "Openshift install binary already installed"
    else
        if [[ -z ${DEST_DIR} ]]; then
            DEST_DIR="$(pwd)"
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
            log-error "Unable to extract oc or kubectl from tar file"
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

function wait_for_cluster_operators() {
# Usage:
#        wait_for_cluster_operators API_SERVER OCP_USERNAME OCP_PASSWORD BIN_DIR 
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
    if [[ $existing_login == "no" ]]; then
        log-info "Logging out of temporary cluster login"
        oc logout 1> /dev/null 2> /dev/null
    fi
}
