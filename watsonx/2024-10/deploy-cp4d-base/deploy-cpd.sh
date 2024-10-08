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

OPERATOR_NAMESPACE="$(echo $PARAMETERS | jq -r .cpd.namespace.cpd_operator)"
INSTANCE_NAMESPACE="$(echo $PARAMETERS | jq -r .cpd.namespace.cpd_operands)"
CERT_MGR_NAMESPACE="$(echo $PARAMETERS | jq -r .cpd.namespace.cert_manager)"
SCHEDULING_SVC_NAMESPACE="$(echo $PARAMETERS | jq -r .cpd.namespace.scheduling_service)"
LICENSE_SVC_NAMESPACE="$(echo $PARAMETERS | jq -r .cpd.namespace.license_service)"
BIN_DIR="$(echo $PARAMETERS | jq -r .directories.bin_dir)"
API_SERVER="$(echo $PARAMETERS | jq -r .cluster.api_server)"
OCP_USERNAME="$(echo $PARAMETERS | jq -r .cluster.username)"
OCP_PASSWORD="$(echo $PARAMETERS | jq -r .cluster.password)"
export STG_CLASS_FILE="$(echo $PARAMETERS | jq -r .cluster.storageclass.file)"
export STG_CLASS_BLOCK="$(echo $PARAMETERS | jq -r .cluster.storageclass.block)"
export VERSION="$(echo $PARAMETERS | jq -r .cpdcli.version)"
export IBM_ENTITLEMENT_KEY="$(echo $PARAMETERS | jq -r .cpdcli.ibm_entitlement_key)"
export COMPONENTS="$(echo $PARAMETERS | jq -r .cpdcli.conponents)"

###
# Confirm oc cli and log into the OpenShift cluster
if [[ ! -f ${BIN_DIR}/oc ]]; then
    echo "ERROR: oc tool not installed at ${BIN_DIR}/oc"
    exit 1
else
    if [[ ! $(${BIN_DIR}/oc status 2> /dev/null) ]]; then
        echo "**** Trying to log into the OpenShift cluster from command line"
        ${BIN_DIR}/oc login "${API_SERVER}" -u $OCP_USERNAME -p $OCP_PASSWORD --insecure-skip-tls-verify=true
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
# Use cpd cli to update the global pull secret
echo
echo "**** Creating the global pull secret"
${BIN_DIR}/cpd-cli manage add-icr-cred-to-global-pull-secret --entitled_registry_key=${IBM_ENTITLEMENT_KEY}

if [[ $? != 0 ]]; then
    echo "ERROR: Failed to update the global secret"
    exit 1
fi

###
# Create cert manager and licensing services
echo
echo "**** Creating cert manager and licensing services"
${BIN_DIR}/cpd-cli manage apply-cluster-components --release=${VERSION} \
    --license_acceptance=true \
    --cert_manager_ns=${CERT_MGR_NAMESPACE} \
    --scheduler_ns=${SCHEDULING_SVC_NAMESPACE}


${BIN_DIR}/cpd-cli manage authorize-instance-topology --cpd_operator_ns=${OPERATOR_NAMESPACE} --cpd_instance_ns=${INSTANCE_NAMESPACE}
${BIN_DIR}/cpd-cli manage setup-instance-topology --release=${VERSION} --cpd_operator_ns=${OPERATOR_NAMESPACE} --cpd_instance_ns=${INSTANCE_NAMESPACE} --block_storage_class=${STG_CLASS_BLOCK}  --license_acceptance=true

###
# Create catalog sources and create subscription for cpd operator
echo
echo "**** Creating catalog soruces and subscription for cpd operator"
${BIN_DIR}/cpd-cli manage apply-olm --release=${VERSION} --components=cpd_platform --cpd_operator_ns=${OPERATOR_NAMESPACE}

if [[ $? != 0 ]]; then
    echo "ERROR: Failed to apply cpfs,cpd_platform catalog or subscription"
    exit 1
fi

###
# Create the cpd platform instance
echo
echo "**** Creating the CPD platform operand"
${BIN_DIR}/cpd-cli manage apply-cr --release=${VERSION} --components=cpd_platform  --license_acceptance=true --cpd_instance_ns=${INSTANCE_NAMESPACE} --file_storage_class=${STG_CLASS_FILE} --block_storage_class=${STG_CLASS_BLOCK}

if [[ $? != 0 ]]; then
    echo "ERROR: Failed to apply cpd_platform"
    exit 1
fi

###
# Enable CSV injector
echo
echo "**** Enabling the CSV injector"
${BIN_DIR}/oc patch namespacescope common-service --type='json' -p='[{\"op\":\"replace\", \"path\": \"/spec/csvInjector/enable\", \"value\":true}]' -n ${OPERATOR_NAMESPACE}

