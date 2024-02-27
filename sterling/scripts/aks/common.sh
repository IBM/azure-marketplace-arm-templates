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
