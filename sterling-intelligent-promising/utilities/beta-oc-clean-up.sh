#!/bin/bash

if [[ -z $NAMESPACE ]]; then NAMESPACE="sip"; fi
if [[ -z $INSTANCE_NAME ]]; then INSTANCE_NAME="sip-environment"; fi
if [[ -z $PVC_NAME ]]; then PVC_NAME="sip-pvc"; fi

# Delete environment
oc delete sipenvironment $INSTANCE_NAME -n $NAMESPACE

# Delete deployments
oc delete deployment ibm-sip-controller-manager -n $NAMESPACE
oc delete deployment ibm-jwt-verifier-controller-manager -n $NAMESPACE

# Delete PVC
oc delete pvc $PVC_NAME -n $NAMESPACE

# Clean up services
oc delete all --all -n $NAMESPACE

# Delete secrets
for secret in $(oc get secret -n $NAMESPACE | grep -v NAME | grep -v "kubernetes.io" | awk '{print $1}'); do
    oc delete secret -n $NAMESPACE $secret
done

# Delete namespace
oc delete namespace $NAMESPACE
