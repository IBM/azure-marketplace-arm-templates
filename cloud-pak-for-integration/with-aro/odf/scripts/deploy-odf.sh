#
# Script to deploy OpenShift Data Foundation onto ARO
#
# Written by:  Rich Ehrhardt
# Email: rich_ehrhardt@au1.ibm.com

source common.sh

######
# Set defaults
if [[ -z $LICENSE ]]; then LICENSE="decline"; fi
if [[ -z $CLIENT_ID ]]; then CLIENT_ID=""; fi
if [[ -z $CLIENT_SECRET ]]; then CLIENT_SECRET=""; fi
if [[ -z $TENANT_ID ]]; then TENANT_ID=""; fi
if [[ -z $SUBSCRIPTION_ID ]]; then SUBSCRIPTION_ID=""; fi
if [[ -z $WORKSPACE_DIR ]]; then export WORKSPACE_DIR="/workspace"; fi
if [[ -z $BIN_DIR ]]; then export BIN_DIR="/usr/local/bin"; fi
if [[ -z $TMP_DIR ]]; then export TMP_DIR="${WORKSPACE_DIR}/tmp"; fi
if [[ -z $NEW_CLUSTER ]]; then NEW_CLUSTER="no"; fi
if [[ -z $STORAGE_SIZE ]]; then export STORAGE_SIZE="2Ti"; fi

######
# Create working directories
mkdir -p ${WORKSPACE_DIR}
mkdir -p ${TMP_DIR}

######
# Check environment variables
ENV_VAR_NOT_SET=""

if [[ -z $ARO_CLUSTER ]]; then ENV_VAR_NOT_SET="ARO_CLUSTER"; fi
if [[ -z $RESOURCE_GROUP ]]; then ENV_VAR_NOT_SET="RESOURCE_GROUP"; fi

if [[ -n $ENV_VAR_NOT_SET ]]; then
    log-output "ERROR: $ENV_VAR_NOT_SET not set. Please set and retry."
    exit 1
fi

#######
# Download and install CLI's if they do not already exist
if [[ ! -f ${BIN_DIR}/oc ]] || [[ ! -f ${BIN_DIR}/kubectl ]]; then
    cli-download $BIN_DIR $TMP_DIR
fi

#######
# Login to Azure CLI
az account show > /dev/null 2>&1
if (( $? != 0 )); then
    # Login with service principal details
    az-login $CLIENT_ID $CLIENT_SECRET $TENANT_ID $SUBSCRIPTION_ID
else
    log-output "INFO: Using existing Azure CLI login"
fi

#####
# Wait for cluster operators to be available
wait_for_cluster_operators $ARO_CLUSTER $RESOURCE_GROUP $BIN_DIR

#######
# Login to cluster
oc-login $ARO_CLUSTER $BIN_DIR $RESOURCE_GROUP

##### 
# Obtain cluster id, version and other details
log-output "INFO: Obtaining information on cluster"
export CLUSTER_ID=$(${BIN_DIR}/oc get -o jsonpath='{.status.infrastructureName}{"\n"}' infrastructure cluster)
log-output "INFO: CLUSTER_ID = $CLUSTER_ID"

export OCP_VERSION=$(${BIN_DIR}/oc version -o json | jq -r '.openshiftVersion' | awk '{split($0,version,"."); print version[1],version[2]}' | sed 's/ /./g')
log-output "INFO: OCP_VERSION = $OCP_VERSION"

export CLUSTER_LOCATION=$(az aro list --query "[?contains(name, '$CLUSTER_NAME')].[location]" -o tsv)
log-output "INFO: CLUSTER_LOCATION = $CLUSTER_LOCATION"

export IMAGE_SKU=$(${BIN_DIR}/oc get machineset/${CLUSTER_ID}-worker-${CLUSTER_LOCATION}1 -n openshift-machine-api -o jsonpath='{.spec.template.spec.providerSpec.value.image.sku}{"\n"}')
log-output "INFO: IMAGE_SKU = $IMAGE_SKU"

export IMAGE_OFFER=$(${BIN_DIR}/oc get machineset/${CLUSTER_ID}-worker-${CLUSTER_LOCATION}1 -n openshift-machine-api -o jsonpath='{.spec.template.spec.providerSpec.value.image.offer}{"\n"}')
log-output "INFO: IMAGE_OFFER = $IMAGE_OFFER"

export IMAGE_VERSION=$(${BIN_DIR}/oc get machineset/${CLUSTER_ID}-worker-${CLUSTER_LOCATION}1 -n openshift-machine-api -o jsonpath='{.spec.template.spec.providerSpec.value.image.version}{"\n"}')
log-output "INFO: IMAGE_VERSION = $IMAGE_VERSION"

export ARO_RESOURCE_GROUP=$(${BIN_DIR}/oc get machineset/${CLUSTER_ID}-worker-${CLUSTER_LOCATION}1 -n openshift-machine-api -o jsonpath='{.spec.template.spec.providerSpec.value.resourceGroup}{"\n"}')
log-output "INFO: ARO_RESOURCE_GROUP = $ARO_RESOURCE_GROUP"

export VNET_NAME=$(${BIN_DIR}/oc get machineset/${CLUSTER_ID}-worker-${CLUSTER_LOCATION}1 -n openshift-machine-api -o jsonpath='{.spec.template.spec.providerSpec.value.vnet}{"\n"}')
log-output "INFO: VNET_NAME = $VNET_NAME"

export SUBNET_NAME=$(${BIN_DIR}/oc get machineset/${CLUSTER_ID}-worker-${CLUSTER_LOCATION}1 -n openshift-machine-api -o jsonpath='{.spec.template.spec.providerSpec.value.subnet}{"\n"}')
log-output "INFO: SUBNET_NAME = $SUBNET_NAME"



######
# Create the openshift storage namespace
if [[ -z $(${BIN_DIR}/oc get namespace | grep "openshift-storage") ]]; then
    log-output "INFO: Creating namespace openshift-storage"
    cat << EOF | oc apply -f - 
apiVersion: v1
kind: Namespace
metadata:
  labels:
    openshift.io/cluster-monitoring: "true"
  name: "openshift-storage"
spec: {}
EOF
else
    log-output "INFO: Using existing openshift-storage namespace"
fi

#####
# Create ODF operator group
if [[ -z $(${BIN_DIR}/oc get operatorgroup -n openshift-storage | grep openshift-storage-operatorgroup) ]]; then
    log-output "INFO: Creating operator group openshift-storage-operatorgroup under namespace openshift-storage"
    cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
    name: openshift-storage-operatorgroup
    namespace: openshift-storage
spec:
    targetNamespaces:
    - openshift-storage
EOF
else
    log-output "INFO: Using existing operator group"
fi

#####
# Create ODF subscription
if [[ -z $(${BIN_DIR}/oc get subscription -n openshift-storage | grep odf-operator) ]]; then
    log-output "INFO: Creating subscription for odf-operator"
    cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
    name: odf-operator
    namespace: openshift-storage
spec:
    channel: "stable-${OCP_VERSION}"
    installPlanApproval: Automatic
    name: odf-operator
    source: redhat-operators
    sourceNamespace: openshift-marketplace
EOF
else
    log-output "INFO: Using existing odf-operator subscription"
fi

####
# Patch the console to add the ODF console
if [[ -z $(${BIN_DIR}/oc get console.operator cluster -n openshift-storage -o json | grep odf-console) ]]; then
    log-output "INFO: Patching openshift console to add ODF console"
    ${BIN_DIR}/oc patch console.operator cluster -n openshift-storage --type json -p '[{"op": "add", "path": "/spec/plugins", "value": ["odf-console"]}]'
else
    log-output "INFO: Openshift console already patched for ODF console"
fi

####
# Generate new machineset for ODF storage cluster - zone 1
if [[ -z $(${BIN_DIR}/oc get machineset -n openshift-machine-api ${CLUSTER_ID}-odf-${CLUSTER_LOCATION}1) ]]; then
    log-output "INFO: Creating machineset for zone 1 for ODF storage cluster"
    cat << EOF | oc apply -f -
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  labels:
    machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID} 
    machine.openshift.io/cluster-api-machine-role: worker
    machine.openshift.io/cluster-api-machine-type: worker
  name: ${CLUSTER_ID}-odf-${CLUSTER_LOCATION}1
  namespace: openshift-machine-api
spec:
  replicas: 1
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID} 
      machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-odf-${CLUSTER_LOCATION}1
  template:
    metadata:
      creationTimestamp: null
      labels:
        machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID} 
        machine.openshift.io/cluster-api-machine-role: worker
        machine.openshift.io/cluster-api-machine-type: worker
        machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-odf-${CLUSTER_LOCATION}1
    spec:
      metadata:
        creationTimestamp: null
        labels:
          cluster.ocs.openshift.io/openshift-storage: ""
      providerSpec:
        value:
          apiVersion: azureproviderconfig.openshift.io/v1beta1
          credentialsSecret:
            name: azure-cloud-credentials
            namespace: openshift-machine-api
          image:
            offer: ${IMAGE_OFFER}
            publisher: azureopenshift
            resourceID: ''
            sku: ${IMAGE_SKU}
            version: ${IMAGE_VERSION}
          internalLoadBalancer: ""
          kind: AzureMachineProviderSpec
          location: ${CLUSTER_LOCATION}
          metadata:
            creationTimestamp: null
          natRule: null
          networkResourceGroup: ${RESOURCE_GROUP}
          osDisk:
            diskSizeGB: 128
            managedDisk:
              storageAccountType: Premium_LRS
            osType: Linux
          publicIP: false
          publicLoadBalancer: ${CLUSTER_ID}
          resourceGroup: ${ARO_RESOURCE_GROUP} 
          sshPrivateKey: ""
          sshPublicKey: ""
          subnet: ${SUBNET_NAME}  
          userDataSecret:
            name: worker-user-data 
          vmSize: Standard_D16s_v3
          vnet: ${VNET_NAME}
          zone: "1" 
EOF
else
    log-output "INFO: Using existing machinesets for zone 1 for ODF storage cluster"
fi

####
# Generate new machineset for ODF storage cluster - zone 2
if [[ -z $(${BIN_DIR}/oc get machineset -n openshift-machine-api ${CLUSTER_ID}-odf-${CLUSTER_LOCATION}2) ]]; then
    log-output "INFO: Creating machineset for zone 2 for ODF storage cluster"
    cat << EOF | oc apply -f -
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  labels:
    machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID} 
    machine.openshift.io/cluster-api-machine-role: worker
    machine.openshift.io/cluster-api-machine-type: worker
  name: ${CLUSTER_ID}-odf-${CLUSTER_LOCATION}2
  namespace: openshift-machine-api
spec:
  replicas: 1
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID} 
      machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-odf-${CLUSTER_LOCATION}2
  template:
    metadata:
      creationTimestamp: null
      labels:
        machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID} 
        machine.openshift.io/cluster-api-machine-role: worker
        machine.openshift.io/cluster-api-machine-type: worker
        machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-odf-${CLUSTER_LOCATION}2
    spec:
      metadata:
        creationTimestamp: null
        labels:
          cluster.ocs.openshift.io/openshift-storage: ""
      providerSpec:
        value:
          apiVersion: azureproviderconfig.openshift.io/v1beta1
          credentialsSecret:
            name: azure-cloud-credentials
            namespace: openshift-machine-api
          image:
            offer: ${IMAGE_OFFER}
            publisher: azureopenshift
            resourceID: ''
            sku: ${IMAGE_SKU}
            version: ${IMAGE_VERSION}
          internalLoadBalancer: ""
          kind: AzureMachineProviderSpec
          location: ${CLUSTER_LOCATION}
          metadata:
            creationTimestamp: null
          natRule: null
          networkResourceGroup: ${RESOURCE_GROUP}
          osDisk:
            diskSizeGB: 128
            managedDisk:
              storageAccountType: Premium_LRS
            osType: Linux
          publicIP: false
          publicLoadBalancer: ${CLUSTER_ID}
          resourceGroup: ${ARO_RESOURCE_GROUP} 
          sshPrivateKey: ""
          sshPublicKey: ""
          subnet: ${SUBNET_NAME}  
          userDataSecret:
            name: worker-user-data 
          vmSize: Standard_D16s_v3
          vnet: ${VNET_NAME}
          zone: "2" 
EOF
else
    log-output "INFO: Using existing machinesets for zone 2 for ODF storage cluster"
fi

####
# Generate new machineset for ODF storage cluster - zone 3
if [[ -z $(${BIN_DIR}/oc get machineset -n openshift-machine-api ${CLUSTER_ID}-odf-${CLUSTER_LOCATION}3) ]]; then
    log-output "INFO: Creating machineset for zone 3 for ODF storage cluster"
    cat << EOF | oc apply -f -
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  labels:
    machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID} 
    machine.openshift.io/cluster-api-machine-role: worker
    machine.openshift.io/cluster-api-machine-type: worker
  name: ${CLUSTER_ID}-odf-${CLUSTER_LOCATION}3
  namespace: openshift-machine-api
spec:
  replicas: 1
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID} 
      machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-odf-${CLUSTER_LOCATION}3
  template:
    metadata:
      creationTimestamp: null
      labels:
        machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID} 
        machine.openshift.io/cluster-api-machine-role: worker
        machine.openshift.io/cluster-api-machine-type: worker
        machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-odf-${CLUSTER_LOCATION}3
    spec:
      metadata:
        creationTimestamp: null
        labels:
          cluster.ocs.openshift.io/openshift-storage: ""
      providerSpec:
        value:
          apiVersion: azureproviderconfig.openshift.io/v1beta1
          credentialsSecret:
            name: azure-cloud-credentials
            namespace: openshift-machine-api
          image:
            offer: ${IMAGE_OFFER}
            publisher: azureopenshift
            resourceID: ''
            sku: ${IMAGE_SKU}
            version: ${IMAGE_VERSION}
          internalLoadBalancer: ""
          kind: AzureMachineProviderSpec
          location: ${CLUSTER_LOCATION}
          metadata:
            creationTimestamp: null
          natRule: null
          networkResourceGroup: ${RESOURCE_GROUP}
          osDisk:
            diskSizeGB: 128
            managedDisk:
              storageAccountType: Premium_LRS
            osType: Linux
          publicIP: false
          publicLoadBalancer: ${CLUSTER_ID}
          resourceGroup: ${ARO_RESOURCE_GROUP} 
          sshPrivateKey: ""
          sshPublicKey: ""
          subnet: ${SUBNET_NAME}  
          userDataSecret:
            name: worker-user-data 
          vmSize: Standard_D16s_v3
          vnet: ${VNET_NAME}
          zone: "3" 
EOF
else
    log-output "INFO: Using existing machinesets for zone 3 for ODF storage cluster"
fi

#####
# Wait for machines to provision
count=0
while [[ $(${BIN_DIR}/oc get machinesets -n openshift-machine-api ${CLUSTER_ID}-odf-${CLUSTER_LOCATION}1 -o jsonpath='{.status.availableReplicas}{"\n"}') != "1" ]] \
    || [[ $(${BIN_DIR}/oc get machinesets -n openshift-machine-api ${CLUSTER_ID}-odf-${CLUSTER_LOCATION}2 -o jsonpath='{.status.availableReplicas}{"\n"}') != "1" ]] \
    || [[ $(${BIN_DIR}/oc get machinesets -n openshift-machine-api ${CLUSTER_ID}-odf-${CLUSTER_LOCATION}3 -o jsonpath='{.status.availableReplicas}{"\n"}') != "1" ]]; do
    log-output "INFO: Waiting for machinesets to become available. Waiting $count minutes. Will wait up to 30 minutes."
    sleep 60
    count=$(( $count + 1 ))
    if (( $count > 30 )); then
        log-output "ERROR: Timeout waiting for cluster operators to be available"
        exit 1;    
    fi
done


#####
# Create the storage cluster
if [[ -z $(${BIN_DIR}/oc get storagecluster -n openshift-storage ocs-storagecluster) ]]; then
    log-output "INFO: Creating storage cluster ocs-storagecluster"
    cat << EOF | oc apply -f -
apiVersion: ocs.openshift.io/v1
kind: StorageCluster
metadata:
  name: ocs-storagecluster
  namespace: openshift-storage
spec:
  arbiter: {}
  encryption:
    kms: {}
  externalStorage: {}
  flexibleScaling: true
  resources:
    mds:
      limits:
        cpu: "3"
        memory: "8Gi"
      requests:
        cpu: "3"
        memory: "8Gi"
  monDataDirHostPath: /var/lib/rook
  managedResources:
    cephBlockPools:
      reconcileStrategy: manage   
    cephConfig: {}
    cephFilesystems: {}
    cephObjectStoreUsers: {}
    cephObjectStores: {}
  multiCloudGateway:
    reconcileStrategy: manage   
  storageDeviceSets:
  - count: 1  
    dataPVCTemplate:
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: "${STORAGE_SIZE}"
        storageClassName: managed-premium
        volumeMode: Block
    name: ocs-deviceset
    placement: {}
    portable: false
    replica: 3
    resources:
      limits:
        cpu: "2"
        memory: "5Gi"
      requests:
        cpu: "2"
        memory: "5Gi"
EOF
else
    log-output "INFO: Using existing storage cluster"
fi

######
# Wait for storage cluster to become available
count=0
while [[ $(${BIN_DIR}/oc get StorageCluster ocs-storagecluster -n openshift-storage --no-headers -o custom-columns='phase:status.phase') != "Ready" ]]; do
    log-output "INFO: Waiting for storage cluster to become available. Waited $count minutes. Will wait up to 30 minutes"
    sleep 60
    count=$(( $count + 1 ))
    if (( $count > 30 )); then
        log-output "ERROR: Timeout waiting for cluster operators to be available"
        exit 1;    
    fi
done
log-output "ODF successfully installed on cluster $ARO_CLUSTER"