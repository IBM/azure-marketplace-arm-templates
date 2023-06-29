#!/bin/bash

source common.sh

# This moves the old log file to a backup
reset-output

######
# Check environment variables
ENV_VAR_NOT_SET=""
if [[ -z $ARO_CLUSTER ]]; then ENV_VAR_NOT_SET="ARO_CLUSTER"; fi
if [[ -z $RESOURCE_GROUP ]]; then ENV_VAR_NOT_SET="RESOURCE_GROUP"; fi
if [[ -z $OMS_NAMESPACE ]]; then ENV_VAR_NOT_SET="OMS_NAMESPACE"; fi
if [[ -z $ADMIN_PASSWORD ]]; then ENV_VAR_NOT_SET="ADMIN_PASSWORD"; fi
if [[ -z $WHICH_OMS ]]; then ENV_VAR_NOT_SET="WHICH_OMS"; fi
if [[ -z $ACR_NAME ]]; then ENV_VAR_NOT_SET="ACR_NAME"; fi
if [[ -z $STORAGE_ACCOUNT_NAME ]]; then ENV_VAR_NOT_SET="STORAGE_ACCOUNT_NAME"; fi
if [[ -z $FILE_TYPE ]]; then ENV_VAR_NOT_SET="FILE_TYPE"; fi
if [[ -z $SC_NAME ]]; then ENV_VAR_NOT_SET="SC_NAME"; fi
if [[ -z $IBM_ENTITLEMENT_KEY ]]; then ENV_VAR_NOT_SET="IBM_ENTITLEMENT_KEY"; fi
if [[ -z $PSQL_HOST ]]; then ENV_VAR_NOT_SET="PSQL_HOST"; fi

if [[ -n $ENV_VAR_NOT_SET ]]; then
    log-output "ERROR: Mandatory environment variable $ENV_VAR_NOT_SET not set. Please set and retry."
    exit 1
fi

#######
# Set defaults (can be overriden with environment variables)
if [[ -z $CLIENT_ID ]]; then CLIENT_ID=""; fi
if [[ -z $CLIENT_SECRET ]]; then CLIENT_SECRET=""; fi
if [[ -z $TENANT_ID ]]; then TENANT_ID=""; fi
if [[ -z $SUBSCRIPTION_ID ]]; then SUBSCRIPTION_ID=""; fi
if [[ -z $WORKSPACE_DIR ]]; then WORKSPACE_DIR="/workspace"; fi
if [[ -z $BIN_DIR ]]; then export BIN_DIR="/usr/local/bin"; fi
if [[ -z $TMP_DIR ]]; then TMP_DIR="${WORKSPACE_DIR}/tmp"; fi
if [[ -z $PSQL_POD_NAME ]]; then export PSQL_POD_NAME="psql-client"; fi
if [[ -z $DB_NAME ]]; then export DB_NAME="oms"; fi
if [[ -z $SCHEMA_NAME ]]; then export SCHEMA_NAME="oms"; fi
if [[ -z $OM_INSTANCE_NAME ]]; then export OM_INSTANCE_NAME="oms-instance"; fi
if [[ -z $LICENSE ]]; then export LICENSE="decline"; fi
if [[ -z $NEW_CLUSTER ]]; then NEW_CLUSTER="yes"; fi
if [[ -z $ADMIN_USER ]]; then ADMIN_USER="azureuser"; fi
if [[ -z $CREATE_ACR ]]; then CREATE_ACR=true; fi
if [[ -z $PROFESSIONAL_REPO ]]; then PROFESSIONAL_REPO="cp.icr.io/cp/ibm-oms-professional"; fi
if [[ -z $ENTERPRISE_REPO ]]; then ENTERPRISE_REPO="cp.icr.io/cp/ibm-oms-enterprise"; fi
if [[ -z $VERSION ]]; then VERSION="10.0.2306.0"; fi
if [[ -z $OPERATOR_VERSION ]]; then OPERATOR_VERSION="1.0"; fi

# Default secrets
if [[ -z $CONSOLEADMINPW ]]; then export CONSOLEADMINPW="$ADMIN_PASSWORD"; fi
if [[ -z $CONSOLENONADMINPW ]]; then export CONSOLENONADMINPW="$ADMIN_PASSWORD"; fi
if [[ -z $DBPASSWORD ]]; then export DBPASSWORD="$ADMIN_PASSWORD"; fi
if [[ -z $TLSSTOREPW ]]; then export TLSSTOREPW="$ADMIN_PASSWORD"; fi
if [[ -z $TRUSTSTOREPW ]]; then export TRUSTSTOREPW="$ADMIN_PASSWORD"; fi
if [[ -z $KEYSTOREPW ]]; then export KEYSTOREPW="$ADMIN_PASSWORD"; fi
if [[ -z $CASSANDRA_USERNAME ]]; then export CASSANDRA_USERNAME="admin"; fi
if [[ -z $CASSANDRA_PASSWORD ]]; then export CASSANDRA_PASSWORD="$ADMIN_PASSWORD"; fi
if [[ -z $ES_USERNAME ]]; then export ES_USERNAME="admin"; fi
if [[ -z $ES_PASSWORD ]]; then export ES_PASSWORD="$ADMIN_PASSWORD"; fi

# Set edition specific parameters
export OMS_VERSION=$WHICH_OMS
if [[ ${WHICH_OMS} == *"-pro-"* ]]; then
    export EDITION="Professional"
    export OPERATOR_NAME="ibm-oms-pro"
    export OPERATOR_CSV="ibm-oms-pro.v${OPERATOR_VERSION}"
    export REPOSITORY="${PROFESSIONAL_REPO}"
    export TAG="${VERSION}-amd64"
else
    export EDITION="Enterprise"
    export OPERATOR_NAME="ibm-oms-ent"
    export OPERATOR_CSV="ibm-oms-ent.v${OPERATOR_VERSION}"
    export REPOSITORY="${ENTERPRISE_REPO}"
    export TAG="${VERSION}-amd64"
fi

# Output parameters to log file before proceeding
log-output "INFO: ARO Cluster is $ARO_CLUSTER"
log-output "INFO: RESOURCE_GRUP is $RESOURCE_GROUP"
log-output "INFO: OMS_NAMESPACE is $OMS_NAMESPACE"
log-output "INFO: ADMIN_USER is $ADMIN_USER"
if [[ -z $ADMIN_PASSWORD ]]; then log-output "INFO: ADMIN_PASSWORD is NOT set"; else log-output "INFO: ADMIN_PASSWORD is set"; fi
log-output "INFO: WHICH_OMS is $WHICH_OMS"
log-output "INFO: CREATE_ACR is $CREATE_ACR"
log-output "INFO: ACR_NAME is $ACR_NAME"
log-output "INFO: STORAGE_ACCOUNT_NAME is $STORAGE_ACCOUNT_NAME"
log-output "INFO: FILE TYPE is $FILE_TYPE"
log-output "INFO: SC_NAME is $SC_NAME"
if [[ -z $IBM_ENTITLEMENT_KEY ]]; then log-output "ERROR: IBM_ENTITLEMENT_KEY is NOT set"; else log-output "INFO: IBM_ENTITLEMENT_KEY is set"; fi
log-output "INFO: PSQL_HOST is $PSQL_HOST"
log-output "INFO: WORKSPACE_DIR is $WORKSPACE_DIR"
log-output "INFO: TMP_DIR is $TMP_DIR"
log-output "INFO: BIN_DIR is $BIN_DIR"
log-output "INFO: PSQL_POD_NAME is $PSQL_POD_NAME"
log-output "INFO: DB_NAME is $DB_NAME"
log-output "INFO: SCHEMA_NAME is $SCHEMA_NAME"
log-output "INFO: OM_INSTANCE_NAME is $OM_INSTANCE_NAME"
log-output "INFO: LICENSE state is $LICENSE"
log-output "INFO: VERSION is $VERSION"
log-output "INFO: EDITION is $EDITION"
log-output "INFO: REPOSITORY is $REPOSITORY"
log-output "INFO: TAG is $TAG"
log-output "INFO: OPERATOR_CSV is $OPERATOR_CSV"

######
# Create working directories
mkdir -p ${WORKSPACE_DIR}
mkdir -p ${TMP_DIR}

#####
# Download OC and kubectl
ARCH=$(uname -m)
OC_FILETYPE="linux"
KUBECTL_FILETYPE="linux"

OC_URL="https://mirror.openshift.com/pub/openshift-v4/${ARCH}/clients/ocp/stable/openshift-client-${OC_FILETYPE}.tar.gz"
#KUBECTL_URL="https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/${KUBECTL_FILETYPE}/${ARCH}/kubectl"

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

######
# Pause to let cluster settle if just created before trying to login
if [[ $NEW_CLUSTER == "yes" ]]; then
  log-output "INFO: Sleeping for 10 minutes to let cluster finish setting up authentication services before logging in"
  sleep 600
fi

#######
# Login to cluster
oc-login $ARO_CLUSTER $BIN_DIR

######
# Wait for cluster operators to finish deploying
count=0
while [[ $(${BIN_DIR}/oc get clusteroperators -o json | jq -r '.items[].status.conditions[] | select(.type=="Available") | .status' | grep False) ]]; do
    log-output "INFO: Waiting for cluster operators to finish installation. Waited $count minutes. Will wait up to 30 minutes."
    sleep 60
    count=$(( $count + 1 ))
    if (( $count > 60 )); then
        log-output "ERROR: Timeout waiting for cluster operators to be available"
        exit 1;    
    fi
done
log-output "INFO: All OpenShift cluster operators available"

######
# Create required namespace
CURRENT_NAMESPACE=$(${BIN_DIR}/oc get namespaces | grep $OMS_NAMESPACE)
if [[ -z $CURRENT_NAMESPACE ]]; then
    log-output "INFO: Creating namespace"
    if error=$(${BIN_DIR}/oc create namespace $OMS_NAMESPACE 2>&1) ; then
        log-output "INFO: Successfully created namespace $OMS_NAMESPACE"
    else
        log-output "FAILED: Unable to create $OMS_NAMESPACE"
        log-output "$error"
    fi
else
    log-output "INFO: Namespace $OMS_NAMESPACE already exists"
fi

######
# Install and configure Azure Files CSI Drivers and Storage Classes

export LOCATION=$(az group show --resource-group $RESOURCE_GROUP --query location -o tsv)
export RESOURCE_GROUP_NAME=$RESOURCE_GROUP

#####
# Set ARO cluster permissions
if [[ $(${BIN_DIR}/oc get clusterrole | grep azure-secret-reader) ]]; then
    log-output "INFO: Using existing cluster role"
else
    log-output "INFO: creating cluster role for Azure file storage"
    if error=$(${BIN_DIR}/oc create clusterrole azure-secret-reader --verb=create,get --resource=secrets 2>&1) ; then
        log-output "INFO: Successfully created cluster role for storage"
    else
        log-output "FAILED: Unable to create cluster storage role"
        log-output "$error"
    fi
    if error=$(${BIN_DIR}/oc adm policy add-cluster-role-to-user azure-secret-reader system:serviceaccount:kube-system:persistent-volume-binder 2>&1) ; then
        log-output "INFO: Successfully created policy for cluster role"
    else
        log-output "FAILED: Unable to create policy for cluster role"
        log-output "$error"
    fi
fi

#####
# Create storage class
if [[ -z $(${BIN_DIR}/oc get sc | grep $SC_NAME) ]]; then
    log-output "INFO: Creating Azure file storage"
    cleanup_file ${WORKSPACE_DIR}/azure-storageclass-azure-file.yaml
    cat << EOF >> ${WORKSPACE_DIR}/azure-storageclass-azure-file.yaml
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: $SC_NAME
provisioner: kubernetes.io/azure-file
mountOptions:
  - dir_mode=0777
  - file_mode=0777
  - uid=0
  - gid=0
  - mfsymlinks
  - cache=strict
  - actimeo=30
  - noperm
parameters:
  location: $LOCATION
  secretNamespace: kube-system
  skuName: $FILE_TYPE
  storageAccount: $STORAGE_ACCOUNT_NAME
  resourceGroup: $RESOURCE_GROUP
reclaimPolicy: Delete
volumeBindingMode: Immediate
EOF

    if error=$(${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/azure-storageclass-azure-file.yaml 2>&1) ; then
        log-output "INFO: Successfully created Azure file storage class"
    else
        log-output "FAILED: Unable to create Azure file storage class"
        log-output "$error"
    fi
else
    log-output "INFO: Azure file storage already exists"
fi


######
# Install and configure IBM Operator catalog

# Create role 
if [[ -z $(${BIN_DIR}/oc get roles -n $OMS_NAMESPACE | grep oms-role) ]]; then
    log-output "INFO: Creating OMS Role"
    cleanup_file ${WORKSPACE_DIR}/oms-role.yaml
    cat << EOF >> ${WORKSPACE_DIR}/oms-role.yaml
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: oms-role
  namespace: $OMS_NAMESPACE
rules:
  - apiGroups: ['']
    resources: ['secrets']
    verbs: ['get', 'watch', 'list', 'create', 'delete', 'patch', 'update']
EOF

    if error=$(${BIN_DIR}/oc apply -f ${WORKSPACE_DIR}/oms-role.yaml 2>&1); then
        log-output "INFO: Successfully created role for OMS"
    else
        log-output "FAILED: Unable to create either the role or the role binding"
        log-output "$error"
    fi
else
    log-output "INFO: OMS RBAC already exists"
fi

# Create role bindings
if [[ -z $(${BIN_DIR}/oc get rolebindings -n $OMS_NAMESPACE | grep oms-rolebinding) ]]; then
    log-output "INFO: Creating OMS RBAC"
    cleanup_file ${WORKSPACE_DIR}/oms-rbac.yaml
    cat << EOF >> ${WORKSPACE_DIR}/oms-rbac.yaml
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: oms-rolebinding
  namespace: $OMS_NAMESPACE
subjects:
  - kind: ServiceAccount
    name: default
    namespace: $OMS_NAMESPACE
roleRef:
  kind: Role
  name: oms-role
  apiGroup: rbac.authorization.k8s.io
EOF

    if error=$(${BIN_DIR}/oc apply -f ${WORKSPACE_DIR}/oms-rbac.yaml 2>&1); then
        log-output "INFO: Successfully created role and role binding for OMS"
    else
        log-output "FAILED: Unable to create either the role or the role binding"
        log-output "$error"
    fi
else
    log-output "INFO: OMS RBAC already exists"
fi

# Create OMS secret with default passwords
if [[ -z $(${BIN_DIR}/oc get secrets -n $OMS_NAMESPACE | grep oms-secret) ]]; then
    log-output "INFO: Creating OMS Secret"
    cleanup_file ${WORKSPACE_DIR}/oms-secret.yaml
    cat << EOF >> ${WORKSPACE_DIR}/oms-secret.yaml
apiVersion: v1
kind: Secret
metadata:
   name: oms-secret
   namespace: $OMS_NAMESPACE
type: Opaque
stringData:
  consoleAdminPassword: $CONSOLEADMINPW
  consoleNonAdminPassword: $CONSOLENONADMINPW
  dbPassword: $DBPASSWORD
  tlskeystorepassword: $TLSSTOREPW
  trustStorePassword: $TRUSTSTOREPW
  keyStorePassword: $KEYSTOREPW
  cassandra_username: $CASSANDRA_USERNAME
  cassandra_password: $CASSANDRA_PASSWORD
  es_username: $ES_USERNAME
  es_password: $ES_PASSWORD
EOF
    if error=$(${BIN_DIR}/oc apply -f ${WORKSPACE_DIR}/oms-secret.yaml 2>&1) ; then
        log-output "INFO: Successfully created OMS secret"
    else
        log-output "FAILED: Unable to create OMS secret"
        log-output "$error"
        exit 1
    fi
else
    log-output "INFO: OMS Secret already exists"
fi

# Get Azure container registry credentials
if [[ $CREATE_ACR == "True" ]]; then
  if [[ -z $(${BIN_DIR}/oc get secrets --all-namespaces | grep $ACR_NAME-dockercfg ) ]]; then
      log-output "INFO: Creating Azure container registry login Secret"
      export ACR_LOGIN_SERVER=$(az acr show -n $ACR_NAME -g $RESOURCE_GROUP --query loginServer -o tsv)
      export ACR_PASSWORD=$(az acr credential show -n $ACR_NAME -g $RESOURCE_GROUP --query passwords[0].value -o tsv )
      cleanup_file ${WORKSPACE_DIR}/oms-pullsecret.json
      cat << EOF >> ${WORKSPACE_DIR}/oms-pullsecret.json
{"auths":{"$ACR_LOGIN_SERVER":{"auth":"$ACR_PASSWORD"}}}
EOF
      if error=$(${BIN_DIR}/oc create secret generic $ACR_NAME-dockercfg --from-file=.dockercfg=${WORKSPACE_DIR}/oms-pullsecret.json --type=kubernetes.io/dockercfg  2>&1) ; then
          log-output "INFO: Successfully created Azure container registry secret" 
      else
          log-output "FAILED: Unable to create Azure container registry secret"
          log-output "$error"
          exit 1
      fi
  else
      log-output "INFO: Azure container registry login secret already created on cluster"
  fi
fi


#######
# Create entitlement key secret for image pull
if [[ -z $(${BIN_DIR}/oc get secret -n ${OMS_NAMESPACE} | grep ibm-entitlement-key) ]]; then
    log-output "INFO: Creating entitlement key secret"
    if error=$(${BIN_DIR}/oc create secret docker-registry ibm-entitlement-key --docker-server=cp.icr.io --docker-username=cp --docker-password=$IBM_ENTITLEMENT_KEY -n $OMS_NAMESPACE 2>&1) ; then
        log-output "INFO: Successfully created IBM Entitlement Key docker registry secret"
    else
        log-output "FAILED: Unable to create IBM Entitlement Key docker registry secret"
        log-output "$error"
        exit 1
    fi
else
    log-output "INFO: Using existing entitlement key secret"
fi

########
# Install OMS Operator

# Create catalog source
if [[ -z $(${BIN_DIR}/oc get catalogsource -n openshift-marketplace | grep ibm-sterling-oms) ]]; then
  log-output "INFO: Creating catalog source ibm-sterling-oms"
  cleanup_file ${WORKSPACE_DIR}/sterling-catalog.yaml
  cat << EOF >> ${WORKSPACE_DIR}/sterling-catalog.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-sterling-oms
  namespace: openshift-marketplace
spec:
  displayName: IBM Sterling OMS
  image: $OMS_VERSION
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 10m0s
EOF
    if error=$(${BIN_DIR}/oc apply -f ${WORKSPACE_DIR}/sterling-catalog.yaml 2>&1) ; then
        log-output "INFO: Successfully installed catalog source ibm-sterling-oms"
    else
        log-output "FAILED: Unable to install catalog source ibm-sterling-oms"
        log-output "$error"
        exit 1
    fi

else
  log-output "INFO: Catalog source ibm-sterling-oms already exists"
fi

# Wait for catalog source to be ready
wait_for_catalog ibm-sterling-oms 15
log-output "INFO: Catalog ibm-sterling-oms ready"

# Create operator group

if [[ -z $(${BIN_DIR}/oc get operatorgroup -n ${OMS_NAMESPACE} | grep oms-operator-global) ]]; then
  log-output "INFO: Creating operator group oms-operator-global"
  cleanup_file ${WORKSPACE_DIR}/operator-group.yaml
  cat << EOF >> ${WORKSPACE_DIR}/operator-group.yaml
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: oms-operator-global
  namespace: $OMS_NAMESPACE
spec: {}
EOF
    if error=$(${BIN_DIR}/oc apply -f ${WORKSPACE_DIR}/operator-group.yaml 2>&1) ; then
        log-output "INFO: Successfully created operator group oms-operator-global"
    else
        log-output "FAILED: Unable to create operator group oms-operator-global"
        log-output "$error"
        exit 1
    fi
else
  log-output "INFO: Operator group oms-operator-global already exists"
fi

# Create subscription for operator

if [[ -z $(${BIN_DIR}/oc get operators -n $OMS_NAMESPACE | grep ibm-oms) ]]; then
    log-output "INFO: Installing OMS Operator"
    log-output "INFO: Name        : $OPERATOR_NAME"
    log-output "INFO: Operator CSV: $OPERATOR_CSV"
    cleanup_file ${WORKSPACE_DIR}/oms-operator.yaml
    cat << EOF >> ${WORKSPACE_DIR}/oms-operator.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: oms-operator
  namespace: $OMS_NAMESPACE
spec:
  channel: v${OPERATOR_VERSION}
  installPlanApproval: Automatic
  name: ${OPERATOR_NAME}
  source: ibm-sterling-oms
  sourceNamespace: openshift-marketplace
EOF
    if error=$(${BIN_DIR}/oc apply -f ${WORKSPACE_DIR}/oms-operator.yaml 2>&1) ; then
        log-output "INFO: Successfully installed OMS operator"
    else
        log-output "FAILED: Unable to install OMS operator"
        log-output "$error"
        exit 1
    fi
else
    log-output "INFO: IBM OMS Operator already installed"
fi

# Wait for operator to be ready
wait_for_subscription ${OMS_NAMESPACE} oms-operator
log-output "INFO: OMS Operator subscription ready" 

# Check operator status
if [[ $(${BIN_DIR}/oc get pods -n ${OMS_NAMESPACE} | grep ibm-oms-controller-manager | awk '{print $2}') != '3/3' ]]; then
    log-output "ERROR: IBM OMS Operator did not start before timeout"
    exit 1;
else
    log-output "INFO: IBM OMS Operator installed and running"
fi

######
# Create psql pod to manage DB (this will be used to create db and schema)
if [[ -z $(${BIN_DIR}/oc get pods -n ${OMS_NAMESPACE} | grep ${PSQL_POD_NAME}) ]]; then
    log-output "INFO: Creating new psql client pod ${PSQL_POD_NAME}"
    cleanup_file ${WORKSPACE_DIR}/psql-pod.yaml
    cat << EOF >> ${WORKSPACE_DIR}/psql-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: ${PSQL_POD_NAME}
  namespace: ${OMS_NAMESPACE}
spec:
  containers:
    - name: psql-container
      image: rhel8/postgresql-12
      command: [ "/bin/bash", "-c", "--" ]
      args: [ "while true; do sleep 30; done;" ]
      env:
        - name: PSQL_HOST
          value: ${PSQL_HOST}
        - name: PSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: oms-secret
              key: dbPassword
        - name: DB_NAME
          value: ${DB_NAME}
        - name: SCHEMA_NAME
          value: ${SCHEMA_NAME}
EOF
    if error=$(${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/psql-pod.yaml 2>&1 ) ; then
        log-output "INFO: Successfully created psql client pod"
    else
        log-output "FAILED: Unable to create psql client pod"
        log-output "$error"
        exit 1
    fi
else
    log-output "INFO: Using existing psql client pod ${PSQL_POD_NAME}"
fi

#####
# Wait for psql pod to start
count=1;
while [[ $(${BIN_DIR}/oc get pods -n ${OMS_NAMESPACE} | grep ${PSQL_POD_NAME} | awk '{print $3}') != "Running" ]]; do
    log-output "INFO: Waiting for psql client pod ${PSQL_POD_NAME} to start. Waited $(( $count * 30 )) seconds. Will wait up to 300 seconds."
    sleep 30
    count=$(( $count + 1 ))
    if (( $count > 10 )); then
        log-output "ERROR: Timeout waiting for pod ${PSQL_POD_NAME} to start."
        exit 1
    fi
done
log-output "INFO: PSQL POD $PSQL_POD_NAME successfully started"

#######
# Create OMEnvironment
if [[ $LICENSE == "accept" ]]; then

    # Create OMS Shared Persistent Volume
    if [[ -z $(${BIN_DIR}/oc get pvc -n $OMS_NAMESPACE | grep oms-pv) ]]; then
      log-output "INFO: Creating PVC for OMS"
      cleanup_file ${WORKSPACE_DIR}/oms-pvc.yaml
      cat << EOF >> ${WORKSPACE_DIR}/oms-pvc.yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: oms-pvc
  namespace: $OMS_NAMESPACE             
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 100Gi
  storageClassName: $SC_NAME
  volumeMode: Filesystem
EOF

      if error=$(${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/oms-pvc.yaml 2>&1 ) ; then
          log-output "INFO: Successfully created OMS PVC" 
      else
          log-output "FAILED: Unable to create OMS PVC"
          log-output "$error"
          exit 1
      fi
    else
        log-output "INFO: PVC for OMS already exists"
    fi
    if [[ -z $(${BIN_DIR}/oc get omenvironment.apps.oms.ibm.com -n ${OMS_NAMESPACE} | grep ${OM_INSTANCE_NAME}) ]]; then

    # Confirm db server exists, then create DB & Schema in DB
    PSQL_NAME=$(echo ${PSQL_HOST} | sed 's/.postgres.database.azure.com//g')
    if [[ -z $(${BIN_DIR}/az postgres flexible-server list -o table | grep ${PSQL_NAME}) ]]; then
        log-output "ERROR: PostgreSQL server ${PSQL_NAME} not found"
        exit 1
    else
        # Create database if it does not exist
        az postgres flexible-server db show --database-name $DB_NAME --server-name $PSQL_NAME --resource-group $RESOURCE_GROUP > /dev/null 2>&1
        if (( $? != 0 )); then
            log-output "INFO: Creating database $DB_NAME in PostgreSQL server $PSQL_NAME"
            if error=$(az postgres flexible-server db create --database-name $DB_NAME --server-name $PSQL_NAME --resource-group $RESOURCE_GROUP 2>&1) ; then
                log-output "INFO: Successfully created database $DB_NAME on server $PSQL_NAME" 
            else
                log-output "FAILED: Unable to create $DB_NAME in server $PSQL_NAME"
                log-output "$error"
                exit 1
            fi
        else
            log-output "INFO: Database $DB_NAME already exists in PostgeSQL server $PSQL_NAME"
        fi

        # Create schema if it does not exist
        if [[ -z $(${BIN_DIR}/oc exec ${PSQL_POD_NAME} -n ${OMS_NAMESPACE} -- /usr/bin/psql -d "host=${PSQL_HOST} port=5432 dbname=${DB_NAME} user=${ADMIN_USER} password=${ADMIN_PASSWORD} sslmode=require" -c "SELECT schema_name FROM information_schema.schemata;" | grep ${SCHEMA_NAME}) ]]; then
            log-output "INFO: Creating schema $SCHEMA_NAME in database $DB_NAME"
            if error=$(${BIN_DIR}/oc exec ${PSQL_POD_NAME} -n ${OMS_NAMESPACE} -- /usr/bin/psql -d "host=${PSQL_HOST} port=5432 dbname=${DB_NAME} user=${ADMIN_USER} password=${ADMIN_PASSWORD} sslmode=require" -c "CREATE SCHEMA $SCHEMA_NAME;" 2>&1 ) ; then
                log-output "INFO: Successfully created $SCHEMA_NAME in $DB_NAME on $PSQL_NAME" 
            else
                log-output "FAILED: Unable to create schema $SCHEMA_NAME"
                log-output "$error"
                exit 1
            fi
        else
            log-output "INFO: Schema $SCHEMA_NAME already exists in database $DB_NAME"
        fi
    fi

    # Create OMEnvironment instance
    log-output "INFO: Creating new OMEnvironment instance ${OM_INSTANCE_NAME}"

    export ARO_INGRESS=$(az aro show -g $RESOURCE_GROUP -n $ARO_CLUSTER --query consoleProfile.url -o tsv | sed -e 's#^https://console-openshift-console.##; s#/##')
    cleanup_file ${WORKSPACE_DIR}/omenvironment.yaml
    cat << EOF >> ${WORKSPACE_DIR}/omenvironment.yaml
apiVersion: apps.oms.ibm.com/v1beta1
kind: OMEnvironment
metadata:
  name: ${OM_INSTANCE_NAME}
  namespace: ${OMS_NAMESPACE}
  annotations:
    apps.oms.ibm.com/dbvendor-install-driver: "true"
    apps.oms.ibm.com/dbvendor-auto-transform: "true"
    apps.oms.ibm.com/dbvendor-driver-url: "https://jdbc.postgresql.org/download/postgresql-42.2.27.jre7.jar"
    apps.oms.ibm.com/activemq-install-driver: 'yes'
    apps.oms.ibm.com/activemq-driver-url: "https://repo1.maven.org/maven2/org/apache/activemq/activemq-all/5.16.0/activemq-all-5.16.0.jar"  
spec:
  license:
    accept: true
    acceptCallCenterStore: true
  common:
    ingress:
      host: "${ARO_INGRESS}"
      ssl:
        enabled: false
  callCenter:
    bindingAppServerName: smcfs    
    base:
      replicaCount: 1
      profile: ProfileMedium
      envVars: EnvironmentVariables
    extn:
      replicaCount: 1
      profile: ProfileMedium
      envVars: EnvironmentVariables
  database:
    postgresql:
      dataSourceName: jdbc/OMDS
      host: "${PSQL_HOST}"
      name: ${DB_NAME}
      port: 5432
      schema: ${SCHEMA_NAME}
      secure: true
      user: ${ADMIN_USER}
  dataManagement:
    mode: create
  storage:
    name: oms-pvc
  secret: oms-secret
  healthMonitor:
    profile: ProfileSmall
    replicaCount: 1
  orderHub:
    bindingAppServerName: smcfs
    base:
      profile: ProfileSmall
      replicaCount: 1
    extn:
      profile: ProfileSmall
      replicaCount: 1
  orderService:
    cassandra:
      createDevInstance:
        profile: ProfileColossal
        storage:
          accessMode: ReadWriteMany
          capacity: 20Gi
          name: oms-pvc-ordserv
          storageClassName: ${SC_NAME}
      keyspace: cassandra_keyspace
    configuration:
      additionalConfig:
        enable_graphql_introspection: 'true'
        log_level: DEBUG
        order_archive_additional_part_name: ordRel
        service_auth_disable: 'true'
        ssl_vertx_disable: 'false'
      jwt_ignore_expiration: false
    elasticsearch:
      createDevInstance:
        profile: ProfileLarge
    orderServiceVersion: ${VERSION}
    profile: ProfileLarge
    replicaCount: 1
  image:
    oms:
      tag: ${TAG}
      repository: ${REPOSITORY}
    orderHub:
      base:
        tag: ${TAG}
        repository: ${REPOSITORY}
      extn:
        tag: ${TAG}
        repository: ${REPOSITORY}
    orderService:
      imageName: orderservice
      repository: ${REPOSITORY}
      tag: ${TAG}
    callCenter:
      base:
        repository: ${REPOSITORY}
        tag: ${TAG}
      extn:
        repository: ${REPOSITORY}
        tag: ${TAG}
    imagePullSecrets:
      - name: ibm-entitlement-key
  networkPolicy:
    ingress: []
    podSelector:
      matchLabels:
        release: oms
        role: appserver
    policyTypes:
      - Ingress
  serverProfiles:
    - name: ProfileSmall
      resources:
        limits:
          cpu: 1000m
          memory: 1Gi
        requests:
          cpu: 200m
          memory: 512Mi
    - name: ProfileMedium
      resources:
        limits:
          cpu: 2000m
          memory: 2Gi
        requests:
          cpu: 500m
          memory: 1Gi
    - name: ProfileLarge
      resources:
        limits:
          cpu: 4000m
          memory: 4Gi
        requests:
          cpu: 500m
          memory: 2Gi
    - name: ProfileHuge
      resources:
        limits:
          cpu: 4000m
          memory: 8Gi
        requests:
          cpu: 500m
          memory: 4Gi
    - name: ProfileColossal
      resources:
        limits:
          cpu: 4000m
          memory: 16Gi
        requests:
          cpu: 500m
          memory: 4Gi
  servers:
    - name: smcfs
      replicaCount: 1
      profile: ProfileHuge
      appServer:
        dataSource:
          minPoolSize: 10
          maxPoolSize: 25
        ingress:
          contextRoots: [smcfs, sbc, sma, isccs, wsc, isf, icc]
        threads:
          min: 10
          max: 25
        vendor: websphere
  serviceAccount: default
  upgradeStrategy: RollingUpdate
  serverProperties:
    customerOverrides:
        - groupName: BaseProperties
          propertyList:
            yfs.yfs.ssi.enabled: N
            yfs.api.security.enabled: Y
            yfs.api.security.token.enabled: Y
EOF
    if error=$(${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/omenvironment.yaml 2>&1) ; then
        log-output "INFO: Successfully installed OMEnvironment instance"
        # Sleep 30 seconds to let navigator get created before checking status
        sleep 30
    else
        log-output "FAILED: Unable to create OMEnvironment"
        log-output "$error"
    fi
  else
    log-output "INFO: Using existing OMEnvironment instance ${OM_INSTANCE_NAME}"
  fi

  # Wait for instance to be created
  count=0
  while [[ $(${BIN_DIR}/oc get OMEnvironment -n ${OMS_NAMESPACE} ${OM_INSTANCE_NAME} -o json | jq -r '.status.conditions[] | select(.type=="OMEnvironmentAvailable").status') != "True" ]]; do
      current_status=$(${BIN_DIR}/oc get OMEnvironment -n ${OMS_NAMESPACE} ${OM_INSTANCE_NAME} -o json | jq -r '.status.conditions[].reason')
      log-output "INFO: Waiting for OMEnvironment instance to be ready. Status = $current_status"
      log-output "Info: Waited $count minutes. Will wait up to 90 minutes. "
      sleep 60
      count=$(( $count + 1 ))
      if (( $count > 90)); then    # Timeout set to 90 minutes
          log-output "ERROR: Timout waiting for ${OM_INSTANCE_NAME} to be ready"
          exit 1
      fi
  done

  # Sleep to allow pods to finish starting up
  log-output "INFO: Sleeping for 3 minutes to allow pods to finish starting"
  sleep 180
else
    log-output "INFO: License not accepted. Manually create instance"
fi

log-output "INFO: Completed"
