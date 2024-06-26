#!/bin/bash

if [[ -z $OCP_USERNAME ]]; then OCP_USERNAME="kubeadmin"; fi
if [[ -z $LICENSE ]]; then LICENSE="decline"; fi
if [[ -z $WORKSPACE_DIR ]]; then WORKSPACE_DIR="/mnt/azscripts/azscriptinput"; fi
if [[ -z $BIN_DIR ]]; then export BIN_DIR="/usr/local/bin"; fi
if [[ -z $TMP_DIR ]]; then TMP_DIR="${WORKSPACE_DIR}/tmp"; fi
if [[ -z $NAMESPACE ]]; then export NAMESPACE="cp4i"; fi
if [[ -z $CLUSTER_SCOPED ]]; then CLUSTER_SCOPED="false"; fi
if [[ -z $REPLICAS ]]; then REPLICAS="1"; fi
if [[ -z $STORAGE_CLASS ]]; then STORAGE_CLASS="ocs-storagecluster-cephfs"; fi
if [[ -z $INSTANCE_NAMESPACE ]]; then export INSTANCE_NAMESPACE=$NAMESPACE; fi
if [[ -z $DEFAULT_VERSION ]]; then export DEFAULT_VERSION="2022.2.1"; fi
if [[ -z $DEFAULT_LICENSE_ID ]]; then export DEFAULT_LICENSE_ID="L-RJON-CD3JKX"; fi
if [[ -z $OCP_VERSION ]]; then OCP_VERSION="stable"; fi    # This will download the latest stable client version
if [[ -z $CLIENT_ID ]]; then CLIENT_ID=""; fi
if [[ -z $CLIENT_SECRET ]]; then CLIENT_SECRET=""; fi
if [[ -z $TENANT_ID ]]; then TENANT_ID=""; fi
if [[ -z $SUBSCRIPTION_ID ]]; then SUBSCRIPTION_ID=""; fi
if [[ -z $STORAGE_SIZE ]]; then export STORAGE_SIZE="2Ti"; fi
if [[ -z $EXISTING_NODES ]]; then EXISTING_NODES="no"; fi
if [[ -z $BRANCH ]]; then BRANCH="main"; fi
if [[ -z $VERSION_URI ]]; then VERSION_URI="https://raw.githubusercontent.com/IBM/azure-marketplace-arm-templates"; fi
if [[ -z $VERSION_PATH ]]; then VERSION_PATH="cloud-pak-for-integration/version-files"; fi