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

function catalog_status() {
    # Gets the status of a catalogsource
    # Usage:
    #      catalog_status NAMESPACE CATALOG

    local NAMESPACE=${1}
    local CATALOG=${2}

    CAT_STATUS="$(kubectl get catalogsource -n $NAMESPACE $CATALOG -o json | jq -r '.status.connectionState.lastObservedState')"
    echo $CAT_STATUS
}

function wait_for_catalog() {
    # Waits for a catalog source to be ready
    # Usage:
    #      wait_for_catalog NAMESPACE CATALOG [TIMEOUT]

    local NAMESPACE=${1}
    local CATALOG=${2}
    # Set default timeout of 15 minutes
    if [[ -z ${3} ]]; then
        local TIMEOUT=15
    else
        local TIMEOUT=${3}
    fi

    export TIMEOUT_COUNT=$(( $TIMEOUT * 60 / 30 ))

    local count=0;
    while [[ $(catalog_status $NAMESPACE $CATALOG) != "READY" ]]; do
        log-info "Waiting for catalog source $CATALOG to be ready. Waited $(( $count * 30 )) seconds. Will wait up to $(( $TIMEOUT_COUNT * 30 )) seconds."
        sleep 30
        count=$(( $count + 1 ))
        if (( $count > $TIMEOUT_COUNT )); then
            log-error "Timeout exceeded waiting for catalog source $CATALOG to be ready"
            exit 1
        fi
    done   
}

function subscription_status() {
    local NAMESPACE=${1}
    local SUBSCRIPTION=${2}

    CSV=$(kubectl get subscription -n ${NAMESPACE} ${SUBSCRIPTION} -o json | jq -r '.status.currentCSV')
    if [[ "$CSV" == "null" ]]; then
        STATUS="PendingCSV"
    else
        STATUS=$(kubectl get csv -n ${NAMESPACE} ${CSV} -o json | jq -r '.status.phase')
    fi
    echo $STATUS
}

function wait_for_subscription() {
    local NAMESPACE=${1}
    local SUBSCRIPTION=${2}
    
    # Set default timeout of 15 minutes
    if [[ -z ${3} ]]; then
        local TIMEOUT=15
    else
        local TIMEOUT=${3}
    fi

    export TIMEOUT_COUNT=$(( $TIMEOUT * 60 / 30 ))

    local count=0;
    while [[ $(subscription_status $NAMESPACE $SUBSCRIPTION) != "Succeeded" ]]; do
        log-info "Waiting for subscription $SUBSCRIPTION to be ready. Waited $(( $count * 30 )) seconds. Will wait up to $(( $TIMEOUT_COUNT * 30 )) seconds."
        sleep 30
        count=$(( $count + 1 ))
        if (( $count > $TIMEOUT_COUNT )); then
            log-error "Timeout exceeded waiting for subscription $SUBSCRIPTION to be ready"
            exit 1
        fi
    done
}
