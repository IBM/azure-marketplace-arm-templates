#!/bin/bash

###
# Confirm jq is installed
if [[ ! $(which jq 2> /dev/null ) ]]; then
    echo "ERROR: jq tool not found"
    exit 1
fi

###
# Parse parameter file
PARAMETERS="$1"

export BIN_DIR="$(echo $PARAMETERS | jq -r .directories.bin_dir)"
export CPD_WORKSPACE="$(echo $PARAMETERS | jq -r .directories.cpd_dir)"
export API_SERVER="$(echo $PARAMETERS | jq -r .cluster.api_server)"
export OCP_USERNAME="$(echo $PARAMETERS | jq -r .cluster.username)"
export OCP_PASSWORD="$(echo $PARAMETERS | jq -r .cluster.password)"
export STG_CLASS_FILE="$(echo $PARAMETERS | jq -r .cluster.storageclass.file)"
export STG_CLASS_BLOCK="$(echo $PARAMETERS | jq -r .cluster.storageclass.block)"
export OPERATOR_NAMESPACE="$(echo $PARAMETERS | jq -r .cpd.namespace.cpd_operator)"
export INSTANCE_NAMESPACE="$(echo $PARAMETERS | jq -r .cpd.namespace.cpd_operands)"
export VERSION="$(echo $PARAMETERS | jq -r .cpd.version)"
export TUNING_DISABLED="$(echo $PARAMETERS | jq -r .cpd.tuning_disabled)"
export LITE_VERSION="$(echo $PARAMETERS | jq -r .cpd.lite_version)"

###
# Confirm oc cli and log into the OpenShift cluster
if [[ ! -f ${BIN_DIR}/oc ]]; then
    echo "ERROR: oc tool not installed at ${BIN_DIR}/oc"
    exit 1
else
    if [[ ! $(${BIN_DIR}/oc status 2> /dev/null) ]]; then
        echo "**** Trying to log into the OpenShift cluster from command line"
        ${BIN_DIR}/oc login "${API_SERVER}" -u $OCP_USERNAME -p $OCP_PASSWORD --insecure-skip-tls-verify=true

        if [[ $? != 0 ]]; then
            echo "ERROR: Unable to log into OpenShift cluster"
            exit 1
        fi
    else
        echo
        echo "**** Already logged into the OpenShift cluster"
    fi
fi

###
# Confirm storage cluster in place 
if [[ ! $(${BIN_DIR}/oc get storagecluster -A | grep -v NAMESPACE) ]]; then
    echo "ERROR: No storage cluster found"
    exit 1
fi

###
# Confirm cpd-cli is installed and login to OpenShift with cpd-cli
if [[ ! -f ${BIN_DIR}/cpd-cli ]]; then
    echo "ERROR: cpd-cli not installed at ${BIN_DIR}/cpd-cli"
    exit 0
else
    ${BIN_DIR}/cpd-cli manage login-to-ocp --server "${API_SERVER}" -u $OCP_USERNAME -p $OCP_PASSWORD

    if [[ $? != 0 ]]; then
        echo "ERROR: Failed to log into the OpenShift cluster via the cpd cli tool"
        exit 1
    fi
fi

###
# Create watsonx.ai catalog source and operator subscription
echo
echo "**** Creating watsonx.ai catalog source and operator subscription"
${BIN_DIR}/cpd-cli manage apply-olm --release=${VERSION} --components=watsonx_ai --cpd_operator_ns=${OPERATOR_NAMESPACE}

if [[ $? != 0 ]]; then
    echo "ERROR: Failed to apply watsonx.ai catalog or subscription"
    exit 1
fi

###
# Create the custom spec file
cat << EOF >> ${CPD_WORKSPACE}/olm-utils-workspace/work/install-options.yaml
custom_spec:  
 watsonx_ai:
  tuning_disabled: ${TUNING_DISABLED}
  lite_install: ${LITE_VERSION}
EOF

###
# Create the watsonx.ai operand
${BIN_DIR}/cpd-cli manage apply-cr --release=${VERSION} --components=watsonx_ai  --license_acceptance=true --cpd_operator_ns=${OPERATOR_NAMESPACE} --cpd_instance_ns=${INSTANCE_NAMESPACE} --file_storage_class=${STG_CLASS_FILE} --block_storage_class=${STG_CLASS_BLOCK} --param-file=/tmp/work/install-options.yaml

if [[ $? != 0 ]]; then
    echo "ERROR: Failed to create watsonx.ai operands"
    exit 1
fi