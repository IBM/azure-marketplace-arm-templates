#!/bin/bash
#
# Note that admin user must be enabled in the Azure Container Registry

source common.sh

if [[ -z $OUTPUT_DIR ]]; then 
    if [[ -z $AZ_SCRIPTS_PATH_OUTPUT_DIRECTORY ]]; then
        export OUTPUT_DIR="/mnt/azscripts/azscriptoutput" 
    else
        export OUTPUT_DIR=$AZ_SCRIPTS_PATH_OUTPUT_DIRECTORY
    fi
fi
export OUTPUT_FILE="oms-script-output-$(date -u +'%Y-%m-%d-%H%M%S').log"
log-info "Script started" 

# Check required parameters
if [[ -z $RESOURCE_GROUP ]]; then log-error "RESOURCE_GROUP not defined"; exit 1; fi
if [[ -z $IBM_ENTITLEMENT_KEY ]]; then log-error "IBM_ENTITLEMENT_KEY not defined"; exit 1; fi
if [[ -z $ADMIN_PASSWORD ]]; then log-error "ADMIN_PASSWORD not defined"; exit 1; fi
if [[ -z $PSQL_HOST ]]; then log-error "PSQL_HOST not defined"; exit 1; fi
# if [[ -z $TRUSTSTORE_PASSWORD ]]; then log-error "TRUSTSTORE_PASSWORD not defined"; exit 1; fi
if [[ -z $DOMAIN_NAME ]]; then log-error "DOMAIN_NAME is not defined"; fi

# Set default values
if [[ -z $TMP_DIR ]]; then TMP_DIR="$(pwd)"; fi
if [[ -z $WORKSPACE_DIR ]]; then WORKSPACE_DIR="$TMP_DIR"; fi
if [[ -z $BIN_DIR ]]; then BIN_DIR="/usr/local/bin"; fi
if [[ -z $OMS_CATALOG ]]; then OMS_CATALOG="cp.icr.io/cpopen/ibm-oms-ent-case-catalog:v1.0.13-10.0.2403.0"; fi
if [[ -z $OPERATOR_NAMESPACE ]]; then OPERATOR_NAMESPACE="ibm-operators"; fi
if [[ -z $OPERATOR_CHANNEL ]]; then OPERATOR_CHANNEL="1.0"; fi
if [[ -z $VERSION ]]; then VERSION="10.0.2403.0"; fi
if [[ -z $SUBSCRIPTION_NAME ]]; then SUBSCRIPTION_NAME="oms-subscription"; fi
if [[ -z $OMS_NAMESPACE ]]; then OMS_NAMESPACE="oms"; fi
if [[ -z $OMS_INSTANCE_NAME ]]; then OMS_INSTANCE_NAME="oms"; fi
if [[ -z $SC_NAME ]]; then SC_NAME="azurefile"; fi
if [[ -z $PVC_NAME ]]; then PVC_NAME="oms-pvc"; fi
if [[ -z $LICENSE ]]; then LICENSE="decline"; fi
if [[ -z $CERT_MANAGER_VERSION ]]; then CERT_MANAGER_VERSION="v1.14.3"; fi
if [[ -z $PVC_SIZE ]]; then PVC_SIZE="100Gi"; fi
if [[ -z $PSQL_POD_NAME ]]; then export PSQL_POD_NAME="psql-client"; fi
if [[ -z $PSQL_IMAGE ]]; then export PSQL_IMAGE="postgres:13"; fi
if [[ -z $DB_NAME ]]; then export DB_NAME="oms"; fi
if [[ -z $SCHEMA_NAME ]]; then export SCHEMA_NAME="oms"; fi
if [[ -z $ADMIN_USER ]]; then ADMIN_USER="azureuser"; fi
if [[ -z $PROFESSIONAL_REPO ]]; then PROFESSIONAL_REPO="cp.icr.io/cp/ibm-oms-professional"; fi
if [[ -z $ENTERPRISE_REPO ]]; then ENTERPRISE_REPO="cp.icr.io/cp/ibm-oms-enterprise"; fi
if [[ -z $BASE_URI ]]; then BASE_URI="https://raw.githubusercontent.com/IBM/azure-marketplace-arm-templates"; fi
if [[ -z $BRANCH ]]; then BRANCH="main"; fi
if [[ -z $HELM_URL ]]; then HELM_URL="https://get.helm.sh/helm-v3.14.3-linux-amd64.tar.gz"; fi
if [[ -z $AZ_SCRIPTS_OUTPUT_PATH ]]; then AZ_SCRIPTS_OUTPUT_PATH="$OUTPUT_DIR/scriptoutputs.json"; fi

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
if [[ ${OMS_CATALOG} == *"-pro-"* ]]; then
    export EDITION="Professional"
    export OPERATOR_NAME="ibm-oms-pro"
    export OPERATOR_CSV="ibm-oms-pro.v${OPERATOR_CHANNEL}"
    export CATALOG_NAME="ibm-oms-pro-catalog"
    export REPOSITORY="${PROFESSIONAL_REPO}"
    export TAG="${VERSION}-amd64"
else
    export EDITION="Enterprise"
    export OPERATOR_NAME="ibm-oms-ent"
    export OPERATOR_CSV="ibm-oms-ent.v${OPERATOR_CHANNEL}"
    export CATALOG_NAME="ibm-oms-ent-catalog"
    export REPOSITORY="${ENTERPRISE_REPO}"
    export TAG="${VERSION}-amd64"
fi

# Install the az cli if it is not already installed
if [[ -z $(which az) ]]; then
    log-info "Installing the az cli"
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
else
    log-info "The az cli is already installed"
fi

# Log in with the az cli if not already
az account show > /dev/null 2>&1
if (( $? != 0 )); then
    # Login with service principal details
    log-info "Logging into the Azure CLI"
    az login --identity
else
    log-info "Using existing Azure CLI login"
fi

# Install the kubectl CLI tools if not installed
if [[ -z $(which kubectl) ]] || [[ -z $(which kubelogin) ]]; then
    log-info "Installing kubectl and kubelogin CLI tools"
    if [[ $(whoami) == "root" ]]; then
        az aks install-cli
        if (( $? != 0 )); then
            log-error "Unable to install kubectl and kubelogin"
            exit 1
        fi
    else
        sudo az aks install-cli
        if (( $? != 0 )); then
            log-error "Unable to install kubectl and kubelogin"
            exit 1
        fi
    fi
else
    log-info "kubectl and kubelogin CLI tools already installed"
fi

# Install the certificate manager tool if not already installed
# if [[ -z $(which cmctl) ]]; then
#     log-info "Installing certificate manager control CLI tool"
#     OS=$(uname | awk '{print tolower($0)}')
#     ARCH=$(case $(uname -m) in x86_64) echo -n amd64 ;; aarch64) echo -n arm64 ;; *) echo -n $(uname -m) ;; esac)
#     curl -fsSL -o ${TMP_DIR}/cmctl.tar.gz https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cmctl-$OS-$ARCH.tar.gz
#     if (( $? != 0 )); then
#         log-error "Unable to download cmctl from https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cmctl-$OS-$ARCH.tar.gz"
#         exit 1
#     else
#         tar xzf ${TMP_DIR}/cmctl.tar.gz
#         if (( $? != 0 )); then
#             log-error "Unable to untar file ${TMP_DIR}/cmctl.tar.gz"
#             exit 1
#         fi
#         mv cmctl ${BIN_DIR}
#         if (( $? != 0 )); then
#             log-error "Unable to move file cmctl to ${BIN_DIR}"
#             exit 1
#         fi
#     fi
# else
#     log-info "Certificate manager control tool already installed"
# fi

# Install the operatorSDK if not already
if [[ -z $(which operator-sdk) ]]; then
    log-info "Installing the Operator-SDK CLI tool"
    export ARCH=$(case $(uname -m) in x86_64) echo -n amd64 ;; aarch64) echo -n arm64 ;; *) echo -n $(uname -m) ;; esac)
    export OS=$(uname | awk '{print tolower($0)}')
    export OPERATOR_SDK_DL_URL=https://github.com/operator-framework/operator-sdk/releases/download/v1.32.0

    curl -LO ${OPERATOR_SDK_DL_URL}/operator-sdk_${OS}_${ARCH}

    if [[ $(whoami) == "root" ]]; then
        chmod +x operator-sdk_${OS}_${ARCH} && mv operator-sdk_${OS}_${ARCH} ${BIN_DIR}/operator-sdk
    else
        chmod +x operator-sdk_${OS}_${ARCH} && sudo mv operator-sdk_${OS}_${ARCH} ${BIN_DIR}/operator-sdk
    fi
else
    log-info "The Operator-SDK CLI tool is already installed"
fi

# Install the helm cli
if [[ -z $(which helm) ]]; then
    wget -q --spider $HELM_URL
    if (( $? != 0 )); then
        log-error "Unable to locate Helm CLI at $HELM_URL"
        exit 1
    else
        log-info "Downloading the Helm CLI"
        wget -q -O ${TMP_DIR}/helm.tgz $HELM_URL

        tar xaf ${TMP_DIR}/helm.tgz 
        if (( $? != 0 )); then
            log-error "Unable to untar file ${TMP_DIR}/helm.tgz"
            exit 1
        fi
        mv linux-amd64/helm ${BIN_DIR}/helm
        if (( $? != 0 )); then
            log-error "Unable to copy helm to bin directory"
            exit 1
        else
            log-info "Successfully installed helm"
        fi
    fi

else
    log-info "Helm CLI already installed"
fi

# Get the Azure Container Registry details
# if [[ -z $ACR_NAME ]]; then 
#     log-info "Getting list of Azure Container Registries"
#     ACRS=( $(az acr list -g $RESOURCE_GROUP --query '[].loginServer' -o tsv) )
#     if [ ${#ACRS[@]} -gt 1 ]; then
#         log-error "More than one ACR visible. Please specify desired ACR in environment parameter"
#         exit 1
#     else
#         ACR_NAME="$(echo ${ACRS[0]} | awk -F. '{print $1}')"
#     fi
# fi
# log-info "Azure container registry is set to $ACR_NAME"
# log-info "Logging into the Azure Container Registry $ACR_NAME in resource group $RESOURCE_GROUP"
# az acr login --name $ACR_NAME


# Log into the AKS cluster
if [[ -z $AKS_CLUSTER ]]; then 
    AKS_CLUSTERS=( $(az aks list -g $RESOURCE_GROUP --query '[].name' -o tsv) )
    if [ ${#AKS_CLUSTERS[@]} -gt 1 ]; then
        log-error "More than one AKS cluster visible. Please specify desired cluster in environment parameter"
        exit 1
    else
        AKS_CLUSTER="${AKS_CLUSTERS[0]}"
    fi
fi
log-info "Logging into AKS Cluster ${AKS_CLUSTER} in resource group $RESOURCE_GROUP"
az aks get-credentials -n $AKS_CLUSTER -g $RESOURCE_GROUP

# Add OLM to the cluster
kubectl get pods -n olm | grep olm-operator 2>&1
if (( $? != 0 )); then
    log-info "Installing OperatorSDK OLM"
    operator-sdk olm install
else
    log-info "OperatorSDK OLM already installed"
fi

# Create the operator namespace
if [[ -z $(kubectl get ns ${OPERATOR_NAMESPACE} 2> /dev/null ) ]]; then
    log-info "Creating namespace ${OPERATOR_NAMESPACE}"
    kubectl create namespace ${OPERATOR_NAMESPACE}
    if (( $? != 0 )); then
        log-error "Unable to create namespace $OPERATOR_NAMESPACE"
        exit 1
    else
        log-info "Successfully created namespace $OPERATOR_NAMESPACE"
    fi
else
    log-info "Namespace ${OPERATOR_NAMESPACE} already exists"
fi

# Create the OMS catalog source
if [[ -z $(kubectl get catalogsource -n ${OPERATOR_NAMESPACE} ${CATALOG_NAME} 2> /dev/null) ]]; then
    log-info "Creating Catalog Source for ${CATALOG_NAME}"
    cat << EOF | kubectl create -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ${CATALOG_NAME}
  namespace: ${OPERATOR_NAMESPACE}
spec:
  displayName: IBM OMS Operator Catalog
  image: '${OMS_CATALOG}' 
  publisher: IBM
  sourceType: grpc 
  updateStrategy:
    registryPoll:
      interval: 10m0s
EOF
    if (( $? != 0 )); then
        log-error "Unable to create catalog source for ${CATALOG_NAME}"
        exit 1
    else
        log-info "Created catalog source for ${CATALOG_NAME}"
    fi
else
    log-info "Catalog source for ${CATALOG_NAME} already exists"
fi

# Wait for catalog source to be ready
wait_for_catalog ${OPERATOR_NAMESPACE} ${CATALOG_NAME} 15
log-info "Catalog source ${CATALOG_NAME} in namespace ${OPERATOR_NAMESPACE} is ready"

# Create the operator group
if [[ -z $(kubectl get operatorgroup -n ${OPERATOR_NAMESPACE} oms-operator-global 2> /dev/null) ]]; then
    log-info "Creating operator group oms-operator-global in namespace ${OPERATOR_NAMESPACE}"
    cat << EOF | kubectl create -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: oms-operator-global
  namespace: ${OPERATOR_NAMESPACE}
spec: {}
EOF
    if (( $? != 0 )); then
        log-error "Unable to create operator group oms-operator-global in namespace ${OPERATOR_NAMESPACE}"
        exit 1
    else
        log-info "Created operator group oms-operator-global in namespace ${OPERATOR_NAMESPACE}"
    fi
else
    log-info "Operator group oms-operator-global already exists in namespace ${OPERATOR_NAMESPACE}"
fi

# Create the OMS operator
if [[ -z $(kubectl get subscription -n ${OPERATOR_NAMESPACE} ${SUBSCRIPTION_NAME} 2> /dev/null) ]]; then 
    log-info "Creating subscription ${SUBSCRIPTION_NAME} in namespace ${OPERATOR_NAMESPACE}"
    cat << EOF | kubectl create -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ${SUBSCRIPTION_NAME}
  namespace: ${OPERATOR_NAMESPACE}
spec:
  channel: v${OPERATOR_CHANNEL}
  installPlanApproval: Automatic
  name: ${OPERATOR_NAME}
  source: ${CATALOG_NAME}
  sourceNamespace: ${OPERATOR_NAMESPACE}
EOF
    if (( $? != 0 )); then
        log-error "Unable to create subscription ${SUBSCRIPTION_NAME} in namespace ${OPERATOR_NAMESPACE}"
        exit 1
    else
        log-info "Created subscription${SUBSCRIPTION_NAME} in namespace ${OPERATOR_NAMESPACE}"
    fi
else
    log-info "Subscription ${SUBSCRIPTION_NAME} already exists in namespace ${OPERATOR_NAMESPACE}"
fi

# Wait for operator to be ready
wait_for_subscription ${OPERATOR_NAMESPACE} ${SUBSCRIPTION_NAME}
log-info "${SUBSCRIPTION_NAME} subscription ready" 

# Create the operand namespace
if [[ -z $(kubectl get namespace ${OMS_NAMESPACE} 2> /dev/null) ]]; then
    log-info "Creating namespace ${OMS_NAMESPACE}"
    kubectl create namespace $OMS_NAMESPACE
    if (( $? != 0 )); then
        log-error "Unable to create namespace $OMS_NAMESPACE"
        exit 1
    else
        log-info "Successfully created namespace $OMS_NAMESPACE"
    fi
else
    log-info "Namespace $OMS_NAMESPACE already exists"
fi

# Upload images to the Azure Container Registry
# log-info "Importing required SIP images to the Azure Container Registry"
# for image in $(cat ${WORKSPACE_DIR}/${IMAGE_LIST_SIP_FILENAME}); do
#     REPO_NAME="${CP_REPO_BASE}/$(echo $image | awk -F":" '{print $1}')"
#     if [[ -z $(az acr repository list --name $ACR_NAME -o tsv | grep $REPO_NAME) ]]; then
#         IMAGE_NAME="$image:$SIP_TAG"
#         log-info "Importing ${CP_REPO_BASE}/$IMAGE_NAME to $ACR_NAME"
#         az acr import \
#             --name $ACR_NAME \
#             --source cp.icr.io/${CP_REPO_BASE}/$IMAGE_NAME \
#             --image ${CP_REPO_BASE}/$IMAGE_NAME \
#             --username cp \
#             --password $IBM_ENTITLEMENT_KEY
#         if (( $? != 0 )); then
#             log-error "Unable to import image ${CP_REPO_BASE}/$IMAGE_NAME to $ACR_NAME"
#             exit 1
#         else
#             log-info "Successfully imported image ${CP_REPO_BASE}/$IMAGE_NAME to $ACR_NAME"
#         fi
#     else
#         log-info "Image ${CP_REPO_BASE}/$IMAGE_NAME already exists in $ACR_NAME repository"
#     fi
# done

# Create the certificate manager CRD
if [[ -z $(kubectl get crd certificates.cert-manager.io 2> /dev/null) ]]; then
    log-info "Installing the certificate manager operator"
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml
    if (( $? != 0 )); then
        log-error "Unable to install certificate manager operator"
        exit 1
    else
        while [[ -z $(kubectl get deployments -n cert-manager | grep "cert-manager " | grep "1/1") ]] \
            && [[ -z $(kubectl get deployments -n cert-manager | grep "cert-manager-cainjector" | grep "1/1") ]] \
            && [[ -z $(kubectl get deployments -n cert-manager | grep "cert-manager-webhook" | grep "1/1") ]]; do
            log-info "Waiting for certificate manager to initialize"
            i=$(( $i + 1))
            if (( $i > 10 )); then
                log-error "Timeout waiting for certificate manager to initialize"
                exit 1
            fi
            sleep 30
        done
        log-info "Certificate manager installed and running"
    fi
else
    log-info "Certificate Manager custom resource definition already exists"
fi

# Create the image pull secrets
if [[ -z $(kubectl get secrets -n $OMS_NAMESPACE | grep ibm-entitlement-key) ]]; then
    log-info "Creating image pull secret ibm-entitlement-key in namespace $OMS_NAMESPACE"
    kubectl create secret docker-registry ibm-entitlement-key --docker-server=cp.icr.io --docker-username=cp --docker-password=$IBM_ENTITLEMENT_KEY -n $OMS_NAMESPACE
    if (( $? != 0 )); then
        log-error "Unable to create image pull secret for ibm-entitlement-key in namespace $OMS_NAMESPACE"
        exit 1
    else
        log-info "Created image pull secret for ibm-entitlement-key in namespace $OMS_NAMESPACE"
    fi
else
    log-info "Image pull secret for ibm-entitlement-key already exists in namespace $OMS_NAMESPACE"
fi

# Create OMS secret with default passwords
if [[ -z $(kubectl get secrets -n $OMS_NAMESPACE oms-secret 2> /dev/null) ]]; then
    log-info "Creating OMS Secret"
    cat << EOF | kubectl apply -f -
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
    if (( $? == 0 )) ; then
        log-info "Successfully created OMS secret"
    else
        log-error "Unable to create OMS secret"
        exit 1
    fi
else
    log-info "OMS Secret already exists"
fi

######
# Create psql pod to manage DB (this will be used to create db and schema)
if [[ -z $(kubectl get pods -n ${OMS_NAMESPACE} ${PSQL_POD_NAME} 2> /dev/null ) ]]; then
    log-info "Creating new psql client pod ${PSQL_POD_NAME} in namespace ${OMS_NAMESPACE}"
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${PSQL_POD_NAME}
  namespace: ${OMS_NAMESPACE}
spec:
  containers:
    - name: psql-container
      image: ${PSQL_IMAGE}
      command: [ "/bin/bash", "-c", "--" ]
      args: [ "while true; do sleep 30; done;" ]
      env:
        - name: PSQL_HOST
          value: ${PSQL_HOST}
        - name: PSQL_ADMIN
          value: ${ADMIN_USER}
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
    if (( $? == 0 )) ; then
        log-info "Successfully created psql client pod ${PSQL_POD_NAME} in namespace ${OMS_NAMESPACE}"
    else
        log-error "Unable to create psql client pod ${PSQL_POD_NAME} in namespace ${OMS_NAMESPACE}"
        exit 1
    fi
else
    log-info "Using existing psql client pod ${PSQL_POD_NAME} in namespace ${OMS_NAMESPACE}"
fi

# Wait for psql pod to start
count=1;
while [[ $(kubectl get pods -n ${OMS_NAMESPACE} | grep ${PSQL_POD_NAME} | awk '{print $3}') != "Running" ]]; do
    log-info "Waiting for psql client pod ${PSQL_POD_NAME} to start. Waited $(( $count * 30 )) seconds. Will wait up to 300 seconds."
    sleep 30
    count=$(( $count + 1 ))
    if (( $count > 10 )); then
        log-error "Timeout waiting for pod ${PSQL_POD_NAME} to start."
        exit 1
    fi
done
log-info "PSQL POD $PSQL_POD_NAME successfully started"

# if [[ -z $(kubectl get secrets -n $SIP_NAMESPACE | grep acr-secret) ]]; then
#     log-info "Creating image pull secret acr-secret in namespace $SIP_NAMESPACE"
#     ACR_USERNAME="$(az acr credential show -n $ACR_NAME -g $RESOURCE_GROUP --query 'username' -o tsv)"
#     ACR_PASSWORD="$(az acr credential show -n $ACR_NAME -g $RESOURCE_GROUP --query 'passwords[0].value' -o tsv)"

#     kubectl create secret docker-registry acr-secret --docker-server=$ACR_NAME.azurecr.io --docker-username=$ACR_USERNAME --docker-password=$ACR_PASSWORD -n $SIP_NAMESPACE
#     if (( $? != 0 )); then
#         log-error "Unable to create image pull secret for acr-secret in namespace $SIP_NAMESPACE"
#         exit 1
#     else
#         log-info "Created image pull secret for acr-secret in namespace $SIP_NAMESPACE"
#     fi
# else
#     log-info "Image pull secret for acr-secret already exists in namespace $SIP_NAMESPACE"
# fi

# Create the nginx ingress controller
if [[ -z $(helm list --namespace ingress-nginx | grep ingress-nginx ) ]]; then
    helm upgrade --install ingress-nginx ingress-nginx \
    --repo https://kubernetes.github.io/ingress-nginx \
    --namespace ingress-nginx --create-namespace
    if (( $? != 0 )); then
        log-error "Unable to install ingress controller"
        exit 1
    else
        log-info "Successfully installed ingress controller"
    fi
else
    log-info "NGINX ingress controller already deployed"
fi

# Deploy OMS instance
if [[ -z $(kubectl get omenvironment -n $OMS_NAMESPACE $OMS_INSTANCE_NAME 2> /dev/null) ]]; then
    if [[ $LICENSE == "accept" ]]; then

    HOSTNAME="oms-service-${OMS_NAMESPACE}.${DOMAIN_NAME}"

        # Create the persistant volume
        if [[ -z $(kubectl get pvc -n $OMS_NAMESPACE $PVC_NAME 2> /dev/null) ]]; then
            log-info "Creating the persistent volume $PVC_NAME in namespace $OMS_NAMESPACE"
            cat << EOF | kubectl create -f -
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: $PVC_NAME
  namespace: $OMS_NAMESPACE             
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: $PVC_SIZE
  storageClassName: $SC_NAME
  volumeMode: Filesystem
EOF
            if (( $? != 0 )); then
                log-error "Unable to create PVC $PVC_NAME in namespace $OMS_NAMESPACE"
                exit 1
            else
                log-info "Created PVC $PVC_NAME in namespace $OMS_NAMESPACE"
            fi

            log-info "Running job to mount volume and force PV creation"
            # Remove any existing job
            if [[ $(kubectl get jobs -n $OMS_NAMESPACE volume-pod 2> /dev/null ) ]]; then
                log-info "Deleting existing volume-pod job in namespace $OMS_NAMESPACE"
                kubectl delete job -n $OMS_NAMESPACE volume-pod
                if (( $? != 0 )); then
                    log-error "Unable to delete volume-pod job in namespace $OMS_NAMESPACE"
                    exit 1
                else
                    log-info "Deleted volume-pod job in namespace $OMS_NAMESPACE"
                fi
            fi
            cat << EOF | kubectl create -f -
kind: Job
apiVersion: batch/v1
metadata: 
  name: volume-pod
  namespace: $OMS_NAMESPACE
spec:
  template:
    spec:
      volumes:
        - name: sip-volume
          persistentVolumeClaim:
            claimName: $PVC_NAME
      containers:
        - name: nginx
          image: nginx:latest
          command: [ "/bin/bash", "-c", "--" ]
          args: [ "echo done" ]
          volumeMounts:
            - name: sip-volume
              mountPath: /mnt
      restartPolicy: OnFailure
  backoffLimit: 4
EOF
            if (( $? != 0 )); then
                log-error "Unable to create batch job to mount volume"
                exit 1
            else
                while [[ -z $(kubectl get job volume-pod -n $OMS_NAMESPACE | grep "1/1") ]]; do
                    log-info "Waiting for volume-pod job in namespace $OMS_NAMESPACE to complete"
                    i=$(( $i + 1 ))
                    if (( $i > 10 )); then
                        log-error "Timeout waiting for volume-pod job in namespace $OMS_NAMESPACE to complete"
                        exit 1
                    fi
                    sleep 30
                done
                log-info "Job volume-pod completed in namespace $OMS_NAMESPACE"
            fi
        else
            log-info "PVC $PVC_NAME already exists in namespace $OMS_NAMESPACE"
        fi

        # Confirm db server exists, then create DB & Schema in DB
        PSQL_NAME=$(echo ${PSQL_HOST} | sed 's/.postgres.database.azure.com//g')
        if [[ -z $(az postgres flexible-server list -o table | grep ${PSQL_NAME}) ]]; then
            log-error "PostgreSQL server ${PSQL_NAME} not found"
            exit 1
        else
            # Create database if it does not exist
            az postgres flexible-server db show --database-name $DB_NAME --server-name $PSQL_NAME --resource-group $RESOURCE_GROUP > /dev/null 2>&1
            if (( $? != 0 )); then
                log-info "Creating database $DB_NAME in PostgreSQL server $PSQL_NAME"
                if error=$(az postgres flexible-server db create --database-name $DB_NAME --server-name $PSQL_NAME --resource-group $RESOURCE_GROUP 2>&1) ; then
                    log-info "Successfully created database $DB_NAME on server $PSQL_NAME" 
                else
                    log-error "Unable to create $DB_NAME in server $PSQL_NAME with error $error"
                    exit 1
                fi
            else
                log-info "Database $DB_NAME already exists in PostgeSQL server $PSQL_NAME"
            fi

            # Create schema if it does not exist
            if [[ -z $(kubectl exec ${PSQL_POD_NAME} -n ${OMS_NAMESPACE} -- /usr/bin/psql -d "host=${PSQL_HOST} port=5432 dbname=${DB_NAME} user=${ADMIN_USER} password=${ADMIN_PASSWORD} sslmode=require" -c "SELECT schema_name FROM information_schema.schemata;" | grep ${SCHEMA_NAME}) ]]; then
                log-info "Creating schema $SCHEMA_NAME in database $DB_NAME"
                if error=$(kubectl exec ${PSQL_POD_NAME} -n ${OMS_NAMESPACE} -- /usr/bin/psql -d "host=${PSQL_HOST} port=5432 dbname=${DB_NAME} user=${ADMIN_USER} password=${ADMIN_PASSWORD} sslmode=require" -c "CREATE SCHEMA $SCHEMA_NAME;" 2>&1 ) ; then
                    log-info "Successfully created $SCHEMA_NAME in $DB_NAME on $PSQL_NAME" 
                else
                    log-error "Unable to create schema $SCHEMA_NAME with error $error"
                    exit 1
                fi
            else
                log-info "Schema $SCHEMA_NAME already exists in database $DB_NAME"
            fi
        fi 

        log-info "Creating OMS instance in namespace $OMS_NAMESPACE"
        cat << EOF | kubectl apply -f -
apiVersion: apps.oms.ibm.com/v1beta1
kind: OMEnvironment
metadata:
  name: ${OMS_INSTANCE_NAME}
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
      host: "${HOSTNAME}"
      ssl:
        enabled: false
  callCenter:
    bindingAppServerName: smcfs    
    base:
      replicaCount: 1
      profile: ProfileMedium
    #   envVars: EnvironmentVariables
    extn:
      replicaCount: 1
      profile: ProfileMedium
    #   envVars: EnvironmentVariables
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
        if (( $? != 0 )); then
            log-error "Unable to create OMS instance ${OMS_INSTANCE_NAME} in namespace $OMS_NAMESPACE"
            exit 1
        else
            # Wait for instance to finish creation            #######TODO

            ###########
            log-info "Successfully created OMS instance ${OMS_INSTANCE_NAME} in namespace $OMS_NAMESPACE"
        fi

        # Wait for instance to be created
        count=0
        while [[ $(kubectl get OMEnvironment -n ${OMS_NAMESPACE} ${OMS_INSTANCE_NAME} -o json | jq -r '.status.conditions[] | select(.type=="OMEnvironmentAvailable").status') != "True" ]]; do
            current_status=$(kubectl get OMEnvironment -n ${OMS_NAMESPACE} ${OMS_INSTANCE_NAME} -o json | jq -r '.status.conditions[].reason')
            log-info "Waiting for OMEnvironment instance to be ready. Status = $current_status"
            log-info "Info: Waited $count minutes. Will wait up to 90 minutes. "
            sleep 60
            count=$(( $count + 1 ))
            if (( $count > 90)); then    # Timeout set to 90 minutes
                log-error "Timout waiting for ${OMS_INSTANCE_NAME} to be ready"
                exit 1
            fi
        done

        # Sleep to allow pods to finish starting up
        log-info "Sleeping for 3 minutes to allow pods to finish starting"
        sleep 180


    else
        log-info "License not accepted. Instance not created"
    fi
else
    log-info "OMS instance ${OMS_INSTANCE_NAME} already exists in namespace $OMS_NAMESPACE"
fi

# Output the key details
# jq -n -c \
#     --arg privateKey "$(cat ${TMP_DIR}/${JWT_KEY_NAME}.pem)" \
#     --arg publicKey "$(cat ${TMP_DIR}/${JWT_KEY_NAME}.pub)" \
#     '{"jwtKey": {"privateKey": $privateKey, "publicKey": $publicKey}}' > $AZ_SCRIPTS_OUTPUT_PATH

log-info "Script completed"