#!/bin/bash

if [[ -z $OCP_USERNAME ]]; then OCP_USERNAME="kubeadmin"; fi
if [[ -z $LICENSE ]]; then LICENSE="decline"; fi
if [[ -z $WORKSPACE_DIR ]]; then WORKSPACE_DIR="/workspace"; fi
if [[ -z $BIN_DIR ]]; then export BIN_DIR="/usr/local/bin"; fi
if [[ -z $TMP_DIR ]]; then TMP_DIR="${WORKSPACE_DIR}/tmp"; fi
if [[ -z $NAMESPACE ]]; then export NAMESPACE="cp4i"; fi
if [[ -z $CLUSTER_SCOPED ]]; then CLUSTER_SCOPED="false"; fi
if [[ -z $REPLICAS ]]; then REPLICAS="1"; fi
if [[ -z $STORAGE_CLASS ]]; then STORAGE_CLASS="ocs-storagecluster-cephfs"; fi
if [[ -z $INSTANCE_NAMESPACE ]]; then export INSTANCE_NAMESPACE=$NAMESPACE; fi
if [[ -z $VERSION ]]; then export VERSION="2022.2.1"; fi
if [[ -z $LICENSE_ID ]]; then export LICENSE_ID="L-RJON-CD3JKX"; fi
if [[ -z $OCP_VERSION ]]; then OCP_VERSION="stable"; fi    # This will download the latest stable client version
