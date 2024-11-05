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

function az-login() {
    CLIENT_ID=${1}
    CLIENT_SECRET=${2}
    TENANT_ID=${3}
    SUBSCRIPTION_ID=${4}

    if [[ -z $CLIENT_ID ]] || [[ -z $CLIENT_SECRET ]] || [[ -z $TENANT_ID ]] || [[ -z $SUBSCRIPTION_ID ]]; then
        log-output "ERROR: Incorrect usage. Supply client id, client secret, tenant id and subcription id to login"
        exit 1
    fi

    az account show > /dev/null 2>&1
    if (( $? != 0 )); then
        # Login with service principal details
        az login --service-principal -u "$CLIENT_ID" -p "$CLIENT_SECRET" -t "$TENANT_ID" > /dev/null 2>&1
        if (( $? != 0 )); then
            log-output "ERROR: Unable to login to service principal. Check supplied details in credentials.properties."
            exit 1
        else
            log-output "Successfully logged on with service principal"
        fi
        az account set --subscription "$SUBSCRIPTION_ID" > /dev/null 2>&1
        if (( $? != 0 )); then
            log-output "ERROR: Unable to use subscription id $SUBSCRIPTION_ID. Please check and try agian."
            exit 1
        else
            log-output "Successfully changed to subscription : $(az account show --query name -o tsv)"
        fi
    else
        log-output "Using existing Azure CLI login"
    fi
}

function oc-login() {
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

    ARCH=$(uname -m)
    OC_FILETYPE="linux"
    KUBECTL_FILETYPE="linux"
    OC_URL="https://mirror.openshift.com/pub/openshift-v4/${ARCH}/clients/ocp/${OC_VERSION}/openshift-client-${OC_FILETYPE}.tar.gz"

    log-output "INFO: Downloading and installing oc and kubectl"
    curl -sLo $TMP_DIR/openshift-client.tgz $OC_URL

    if ! error=$(tar xzf ${TMP_DIR}/openshift-client.tgz -C ${TMP_DIR} oc kubectl 2>&1) ; then
        log-output "ERROR: Unable to extract oc or kubectl from tar file"
        log-output "$error"
    fi

    if ! error=$(mv ${TMP_DIR}/oc ${BIN_DIR}/oc 2>&1) ; then
        log-output "ERROR: Unable to move oc to $BIN_DIR"
        log-output "$error"
    fi

    if ! error=$(mv ${TMP_DIR}/kubectl ${BIN_DIR}/kubectl 2>&1) ; then
        log-output "ERROR: Unable to move kubectl to $BIN_DIR"
        log-output "$error"
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
        log-output "INFO: Waiting for subscription $SUBSCRIPTION to be ready. Waited $(( $count * 30 )) seconds. Will wait up to $(( $TIMEOUT_COUNT * 30 )) seconds."
        sleep 30
        count=$(( $count + 1 ))
        if (( $count > $TIMEOUT_COUNT )); then
            log-output "ERROR: Timeout exceeded waiting for subscription $SUBSCRIPTION to be ready"
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
        log-output "INFO: Waiting for catalog source $CATALOG to be ready. Waited $(( $count * 30 )) seconds. Will wait up to $(( $TIMEOUT_COUNT * 30 )) seconds."
        sleep 30
        count=$(( $count + 1 ))
        if (( $count > $TIMEOUT_COUNT )); then
            log-output "ERROR: Timeout exceeded waiting for catalog source $CATALOG to be ready"
            exit 1
        fi
    done   
}

function menu() {
    local item i=1 numItems=$#

    for item in "$@"; do
        printf '%s %s\n' "$((i++))" "$item"
    done >&2

    while :; do
        printf %s "${PS3-#? }" >&2
        read -r input
        if [[ -z $input ]]; then
            break
        elif (( input < 1 )) || (( input > numItems )); then
          echo "Invalid Selection. Enter number next to item." >&2
          continue
        fi
        break
    done

    if [[ -n $input ]]; then
        printf %s "${@: input:1}"
    fi
}

function get_region() {
    if [[ -z $METADATA_FILE ]]; then
        METADATA_FILE="$(pwd)/azure-metadata.yaml"
    fi

    IFS=$'\n'

    echo
    read -r -d '' -a AREAS < <(yq '.regions[].area' $METADATA_FILE | sort -u)
    DEFAULT_AREA="$(yq ".regions[] | select(.code == \"$DEFAULT_REGION\") | .area" $METADATA_FILE)"
    PS3="Select the deployment area [$DEFAULT_AREA]: "
    area=$(menu "${AREAS[@]}")
    case $area in
        '') AREA="$DEFAULT_AREA"; ;;
        *) AREA=$area; ;;
    esac

    echo
    read -r -d '' -a REGIONS < <(yq ".regions[] | select(.area == \"${AREA}\") | .name" $METADATA_FILE | sort -u)
    if [[ $AREA != $DEFAULT_AREA ]]; then
        DEFAULT_REGION="$(yq ".regions[] | select(.name == \"${REGIONS[0]}\") | .code" $METADATA_FILE)"
    fi
    PS3="Select the region within ${AREA} [$(yq ".regions[] | select(.code == \"$DEFAULT_REGION\") | .name" $METADATA_FILE)]: "
    region=$(menu "${REGIONS[@]}")
    case $region in
        '') REGION="$DEFAULT_REGION"; ;;
        *) REGION="$(yq ".regions[] | select(.name == \"$region\") | .code" $METADATA_FILE)"; ;;
    esac

    echo $REGION
}

function cleanup_file() {
    FILE=${1}

    if [[ -f $FILE ]]; then
        rm $FILE
    fi
}