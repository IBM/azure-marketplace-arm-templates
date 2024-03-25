#!/bin/bash
#
# Note that admin user must be enabled in the Azure Container Registry

source common.sh

export OUTPUT_DIR="/mnt/azscripts/azscriptoutput"
export OUTPUT_FILE="sip-script-output-$(date -u +'%Y-%m-%d-%H%M%S').log"
log-info "Script started" 

# Check required parameters
if [[ -z $RESOURCE_GROUP ]]; then log-error "RESOURCE_GROUP not defined"; exit 1; fi
if [[ -z $IBM_ENTITLEMENT_KEY ]]; then log-error "IBM_ENTITLEMENT_KEY not defined"; exit 1; fi
if [[ -z $TRUSTSTORE_PASSWORD ]]; then log-error "TRUSTSTORE_PASSWORD not defined"; exit 1; fi
if [[ -z $DOMAIN_NAME ]]; then log-error "DOMAIN_NAME is not defined"; fi

# Set default values
if [[ -z $TMP_DIR ]]; then TMP_DIR="$(pwd)"; fi
if [[ -z $WORKSPACE_DIR ]]; then WORKSPACE_DIR="$TMP_DIR"; fi
if [[ -z $BIN_DIR ]]; then BIN_DIR="/usr/local/bin"; fi
if [[ -z $OMS_GW_OPERATOR ]]; then OMS_GW_OPERATOR="cp.icr.io/cpopen/ibm-oms-gateway-operator-catalog:v1.0"; fi
if [[ -z $SIP_OPERATOR ]]; then SIP_OPERATOR="cp.icr.io/cpopen/ibm-oms-sip-operator-catalog:v1.0"; fi
if [[ -z $OPERATOR_NAMESPACE ]]; then OPERATOR_NAMESPACE="ibm-operators"; fi
if [[ -z $SIP_NAMESPACE ]]; then SIP_NAMESPACE="sip"; fi
if [[ -z $SIP_INSTANCE_NAME ]]; then SIP_INSTANCE_NAME="sip"; fi
if [[ -z $BASE_URI ]]; then BASE_URI="https://raw.githubusercontent.com/IBM/azure-marketplace-arm-templates"; fi
if [[ -z $BRANCH ]]; then BRANCH="main"; fi
if [[ -z $IMAGE_LIST_RH_FILENAME ]]; then IMAGE_LIST_RH_FILENAME="image-list-rh"; fi
if [[ -z $IMAGE_LIST_SIP_FILENAME ]]; then IMAGE_LIST_SIP_FILENAME="image-list-sip"; fi
if [[ -z $IMAGE_LIST_RH_URL ]]; then IMAGE_LIST_RH_URL="${BASE_URI}/${BRANCH}/sterling/2024-03/sip/${IMAGE_LIST_RH_FILENAME}"; fi
if [[ -z $IMAGE_LIST_SIP_URL ]]; then IMAGE_LIST_SIP_URL="${BASE_URI}/${BRANCH}/sterling/2024-03/sip/${IMAGE_LIST_SIP_FILENAME}"; fi
if [[ -z $SC_NAME ]]; then SC_NAME="azurefile"; fi
if [[ -z $PVC_NAME ]]; then PVC_NAME="sip1-pvc"; fi
if [[ -z $LICENSE ]]; then LICENSE="decline"; fi
if [[ -z $CERT_MANAGER_VERSION ]]; then CERT_MANAGER_VERSION="v1.14.3"; fi
if [[ -z $PVC_SIZE ]]; then PVC_SIZE="10Gi"; fi
if [[ -z $CP_REPO_BASE ]]; then CP_REPO_BASE="cp/ibm-oms-enterprise"; fi
if [[ -z $LOG_LEVEL ]]; then LOG_LEVEL="INFO"; fi
if [[ -z $RH_TAG ]]; then RH_TAG="latest"; fi
if [[ -z $SIP_TAG ]]; then SIP_TAG="10.0.2403.0-amd64"; fi
if [[ -z $SIP_SECRET_NAME ]]; then SIP_SECRET_NAME="sip-secret"; fi
if [[ -z $CASSANDRA_USERNAME ]]; then CASSANDRA_USERNAME="sipadmin"; fi
if [[ -z $CASSANDRA_PASSWORD ]]; then CASSANDRA_PASSWORD="$TRUSTSTORE_PASSWORD"; fi
if [[ -z $ELASTICSEARCH_USERNAME ]]; then ELASTICSEARCH_USERNAME="sipadmin"; fi
if [[ -z $ELASTICSEARCH_PASSWORD ]]; then ELASTICSEARCH_PASSWORD="$TRUSTSTORE_PASSWORD"; fi
if [[ -z $KAFKA_SECURITY_PROTOCOL ]]; then KAFKA_SECURITY_PROTOCOL="SSL"; fi
if [[ -z $KAFKA_USER ]]; then KAFKA_USER="sipadmin"; fi
if [[ -z $KAFKA_PASSWORD ]]; then KAFKA_PASSWORD="$TRUSTSTORE_PASSWORD"; fi
if [[ -z $JWT_KEY_NAME ]]; then JWT_KEY_NAME="sipkey"; fi
if [[ -z $JWT_SECRET_NAME ]]; then JWT_SECRET_NAME="jwt-configuration"; fi

# Download the image lists
if [[ -f ${WORKSPACE_DIR}/${IMAGE_LIST_RH_FILENAME} ]]; then
    log-info "Red Hat image list already exists"
else
    wget -q --spider $IMAGE_LIST_RH_URL
    if (( $? != 0 )); then
        log-error "Red Hat image list not found at $IMAGE_LIST_RH_URL"
        exit 1
    else
        log-info "Downloading Red Hat image list"
        wget -q -P $WORKSPACE_DIR $IMAGE_LIST_RH_URL
        if (( $? != 0 )); then
            log-error "Unable to download Red Hat image list from ${IMAGE_LIST_RH_URL}"
            exit 1
        else
            log-info "Successfully download Red Hat image list"
        fi
    fi
fi

if [[ -f ${WORKSPACE_DIR}/${IMAGE_LIST_SIP_FILENAME} ]]; then
    log-info "SIP image list already exists"
else
    wget -q --spider $IMAGE_LIST_SIP_URL 
    if (( $? != 0 )); then
        log-error "SIP image list not found at $IMAGE_LIST_SIP_URL"
        exit 1
    else
        log-info "Downloading SIP image list"
        wget -q -P $WORKSPACE_DIR $IMAGE_LIST_SIP_URL 
        if (( $? != 0 )); then
            log-error "Unable to download SIP image list from ${IMAGE_LIST_SIP_URL}"
            exit 1
        else
            log-info "Successfully download SIP image list"
        fi
    fi
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
if [[ -z $(which cmctl) ]]; then
    log-info "Installing certificate manager control CLI tool"
    OS=$(uname | awk '{print tolower($0)}')
    ARCH=$(case $(uname -m) in x86_64) echo -n amd64 ;; aarch64) echo -n arm64 ;; *) echo -n $(uname -m) ;; esac)
    curl -fsSL -o ${TMP_DIR}/cmctl.tar.gz https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cmctl-$OS-$ARCH.tar.gz
    if (( $? != 0 )); then
        log-error "Unable to download cmctl from https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cmctl-$OS-$ARCH.tar.gz"
        exit 1
    else
        tar xzf ${TMP_DIR}/cmctl.tar.gz
        if (( $? != 0 )); then
            log-error "Unable to untar file ${TMP_DIR}/cmctl.tar.gz"
            exit 1
        fi
        mv cmctl ${BIN_DIR}
        if (( $? != 0 )); then
            log-error "Unable to move file cmctl to ${BIN_DIR}"
            exit 1
        fi
    fi
else
    log-info "Certificate manager control tool already installed"
fi

# Install the operatorSDK if not already
if [[ -z $(which operator-sdk) ]]; then
    log-info "Installing the Oerator-SDK CLI tool"
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

# Get the Azure Container Registry details
if [[ -z $ACR_NAME ]]; then 
    log-info "Getting list of Azure Container Registries"
    ACRS=( $(az acr list -g $RESOURCE_GROUP --query '[].loginServer' -o tsv) )
    if [ ${#ACRS[@]} -gt 1 ]; then
        log-error "More than one ACR visible. Please specify desired ACR in environment parameter"
        exit 1
    else
        ACR_NAME="$(echo ${ACRS[0]} | awk -F. '{print $1}')"
    fi
fi
log-info "Azure container registry is set to $ACR_NAME"
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
if [[ -z $(kubectl get ns | grep ${OPERATOR_NAMESPACE} ) ]]; then
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

# Create the OMS Gateway Operator catalog source
if [[ -z $(kubectl get catalogsource -n ${OPERATOR_NAMESPACE} | grep ibm-oms-gateway-catalog) ]]; then
    log-info "Creating Catalog Source for ibm-oms-gateway-catalog"
    cat << EOF | kubectl create -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-oms-gateway-catalog
  namespace: ${OPERATOR_NAMESPACE}
spec:
  displayName: IBM OMS Gateway Operator Catalog
  image: '${OMS_GW_OPERATOR}' 
  publisher: IBM
  sourceType: grpc 
  updateStrategy:
    registryPoll:
      interval: 10m0s
EOF
    if (( $? != 0 )); then
        log-error "Unable to create catalog source for ibm-oms-gateway-catalog"
        exit 1
    else
        log-info "Created catalog source for ibm-oms-gateway-catalog"
    fi
else
    log-info "Catalog source for ibm-oms-gateway-catalog already exists"
fi

# Create the SIP Operator Catalog Source
if [[ -z $(kubectl get catalogsource -n ${OPERATOR_NAMESPACE} | grep ibm-sip-catalog) ]]; then
    log-info "Creating Catalog Source for ibm-sip-catalog"
    cat << EOF | kubectl create -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-sip-catalog
  namespace: ${OPERATOR_NAMESPACE}
spec:
  displayName: IBM SIP Operator Catalog
  image: '${SIP_OPERATOR}' 
  publisher: IBM
  sourceType: grpc 
  updateStrategy:
    registryPoll:
      interval: 10m0s
EOF
    if (( $? != 0 )); then
        log-error "Unable to create catalog source for ibm-sip-catalog"
        exit 1
    else
        log-info "Created catalog source for ibm-sip-catalog"
    fi
else
    log-info "Catalog source for ibm-sip-catalog already exists"
fi

# Create the operator group
if [[ -z $(kubectl get operatorgroup -n ${OPERATOR_NAMESPACE} | grep sip-operator-global) ]]; then
    log-info "Creating operator group sip-operator-global in namespace ${OPERATOR_NAMESPACE}"
    cat << EOF | kubectl create -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: sip-operator-global
  namespace: ${OPERATOR_NAMESPACE}
spec: {}
EOF
    if (( $? != 0 )); then
        log-error "Unable to create operator group sip-operator-global in namespace ${OPERATOR_NAMESPACE}"
        exit 1
    else
        log-info "Created operator group sip-operator-global in namespace ${OPERATOR_NAMESPACE}"
    fi
else
    log-info "Operator group sip-operator-global already exists in namespace ${OPERATOR_NAMESPACE}"
fi

# Create the OMS Gateway operator
if [[ -z $(kubectl get subscription -n ${OPERATOR_NAMESPACE} | grep oms-gateway-subscription) ]]; then 
    log-info "Creating subscription oms-gateway-subscription in namespace ${OPERATOR_NAMESPACE}"
    cat << EOF | kubectl create -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: oms-gateway-subscription
  namespace: ${OPERATOR_NAMESPACE}
spec:
  channel: v1.0
  installPlanApproval: Automatic
  name: ibm-oms-gateway
  source: ibm-oms-gateway-catalog
  sourceNamespace: ${OPERATOR_NAMESPACE}
EOF
    if (( $? != 0 )); then
        log-error "Unable to create subscription oms-gateway-subscription in namespace ${OPERATOR_NAMESPACE}"
        exit 1
    else
        log-info "Created subscription oms-gateway-subscription in namespace ${OPERATOR_NAMESPACE}"
    fi
else
    log-info "Subscription oms-gateway-subscription already exists in namespace ${OPERATOR_NAMESPACE}"
fi

# Create the SIP operator
if [[ -z $(kubectl get subscription -n ${OPERATOR_NAMESPACE} | grep sip-subscription) ]]; then
    log-info "Creating subscription sip-subscription in namespace ${OPERATOR_NAMESPACE}"
    cat << EOF | kubectl create -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: sip-subscription
  namespace: ${OPERATOR_NAMESPACE}
spec:
  channel: v1.0
  installPlanApproval: Automatic
  name: ibm-sip
  source: ibm-sip-catalog
  sourceNamespace: ${OPERATOR_NAMESPACE}
EOF
    if (( $? != 0 )); then
        log-error "Unable to create subscription sip-subscription in namespace ${OPERATOR_NAMESPACE}"
        exit 1
    else
        log-info "Created subscription sip-subscription in namespace ${OPERATOR_NAMESPACE}"
    fi
else
    log-info "Subscription sip-subscription already exists in namespace ${OPERATOR_NAMESPACE}"
fi

# Create the operand namespace
if [[ -z $(kubectl get namespace | grep ${SIP_NAMESPACE}) ]]; then
    log-info "Creating namespace ${SIP_NAMESPACE}"
    kubectl create namespace $SIP_NAMESPACE
    if (( $? != 0 )); then
        log-error "Unable to create namespace $SIP_NAMESPACE"
        exit 1
    else
        log-info "Successfully created namespace $SIP_NAMESPACE"
    fi
else
    log-info "Namespace $SIP_NAMESPACE already exists"
fi

# Upload images to the Azure Container Registry
log-info "Importing required Red Hat images to the Azure Container Registry"
for image in $(cat ${WORKSPACE_DIR}/${IMAGE_LIST_RH_FILENAME}); do
    REPO_NAME="ubi8/$(echo $image | awk -F":" '{print $1}')"
    if [[ -z $(az acr repository list --name $ACR_NAME -o tsv | grep $REPO_NAME) ]]; then
    IMAGE_NAME="$image:$RH_TAG"
        log-info "Importing ubi8/$IMAGE_NAME to $ACR_NAME"
        az acr import \
            --name $ACR_NAME \
            --source registry.access.redhat.com/ubi8/$IMAGE_NAME \
            --image ubi8/$IMAGE_NAME
        if (( $? != 0 )); then
            log-error "Unable to import image ubi8/$IMAGE_NAME to $ACR_NAME"
            exit 1
        else
            log-info "Successfully imported image ubi8/$IMAGE_NAME to $ACR_NAME"
        fi
    else
        log-info "Image ubi8/$image already exists in $ACR_NAME repository"
    fi
done

log-info "Importing required SIP images to the Azure Container Registry"
for image in $(cat ${WORKSPACE_DIR}/${IMAGE_LIST_SIP_FILENAME}); do
    REPO_NAME="${CP_REPO_BASE}/$(echo $image | awk -F":" '{print $1}')"
    if [[ -z $(az acr repository list --name $ACR_NAME -o tsv | grep $REPO_NAME) ]]; then
        IMAGE_NAME="$image:$SIP_TAG"
        log-info "Importing ${CP_REPO_BASE}/$IMAGE_NAME to $ACR_NAME"
        az acr import \
            --name $ACR_NAME \
            --source cp.icr.io/${CP_REPO_BASE}/$IMAGE_NAME \
            --image ${CP_REPO_BASE}/$IMAGE_NAME \
            --username cp \
            --password $IBM_ENTITLEMENT_KEY
        if (( $? != 0 )); then
            log-error "Unable to import image ${CP_REPO_BASE}/$IMAGE_NAME to $ACR_NAME"
            exit 1
        else
            log-info "Successfully imported image ${CP_REPO_BASE}/$IMAGE_NAME to $ACR_NAME"
        fi
    else
        log-info "Image ${CP_REPO_BASE}/$IMAGE_NAME already exists in $ACR_NAME repository"
    fi
done

# Create the certificate manager CRD
if [[ -z $(kubectl get crds | grep certificatemanagers) ]]; then
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
if [[ -z $(kubectl get secrets -n $SIP_NAMESPACE | grep ibm-entitlement-key) ]]; then
    log-info "Creating image pull secret ibm-entitlement-key in namespace $SIP_NAMESPACE"
    kubectl create secret docker-registry ibm-entitlement-key --docker-server=cp.icr.io --docker-username=cp --docker-password=$IBM_ENTITLEMENT_KEY -n $SIP_NAMESPACE
    if (( $? != 0 )); then
        log-error "Unable to create image pull secret for ibm-entitlement-key in namespace $SIP_NAMESPACE"
        exit 1
    else
        log-info "Created image pull secret for ibm-entitlement-key in namespace $SIP_NAMESPACE"
    fi
else
    log-info "Image pull secret for ibm-entitlement-key already exists in namespace $SIP_NAMESPACE"
fi

if [[ -z $(kubectl get secrets -n $SIP_NAMESPACE | grep acr-secret) ]]; then
    log-info "Creating image pull secret acr-secret in namespace $SIP_NAMESPACE"
    ACR_USERNAME="$(az acr credential show -n $ACR_NAME -g $RESOURCE_GROUP --query 'username' -o tsv)"
    ACR_PASSWORD="$(az acr credential show -n $ACR_NAME -g $RESOURCE_GROUP --query 'passwords[0].value' -o tsv)"

    kubectl create secret docker-registry acr-secret --docker-server=$ACR_NAME.azurecr.io --docker-username=$ACR_USERNAME --docker-password=$ACR_PASSWORD -n $SIP_NAMESPACE
    if (( $? != 0 )); then
        log-error "Unable to create image pull secret for acr-secret in namespace $SIP_NAMESPACE"
        exit 1
    else
        log-info "Created image pull secret for acr-secret in namespace $SIP_NAMESPACE"
    fi
else
    log-info "Image pull secret for acr-secret already exists in namespace $SIP_NAMESPACE"
fi



# Deploy SIP instance
if [[ -z $(kubectl get sipenvironment -n $SIP_NAMESPACE | grep " sip " ) ]]; then
    if [[ $LICENSE == "accept" ]]; then

        # Create JWT issuer cert
        HOSTNAME="sipservice-${SIP_NAMESPACE}.$DOMAIN_NAME"

        if [[ -z $(kubectl get certificatemanager -n $SIP_NAMESPACE | grep "ingress-cert ") ]]; then
            log-info "Creating ingress certificate"
            cat << EOF | kubectl create -f -
apiVersion: apps.oms.gateway.ibm.com/v1beta1
kind: CertificateManager
metadata:
  name: ingress-cert
  namespace: ${SIP_NAMESPACE}
spec:
  expiryDays: 365
  hostName: ${HOSTNAME}
EOF
            if (( $? != 0 )); then
                log-error "Unable to create ingress certificate"
                exit 1
            else
                log-info "Ingress certificate created"
            fi
        else
            log-info "Ingress certificate already exists"
        fi

        # Create the JWT Issuer secret
        if [[ -z $(kubectl get secret -n ${SIP_NAMESPACE} ${JWT_KEY_NAME} 2> /dev/null ) ]]; then
            log-info "Creating JWT Issuer secret"
            if [[ ! -f ${TMP_DIR}/${JWT_KEY_NAME}.pem ]]; then
                log-info "Creating JWT Key Pair"

                openssl genrsa -out ${TMP_DIR}/${JWT_KEY_NAME}.pem 2048
            else
                log-info "JWT Key pair ${JWT_KEY_NAME} already exists"
            fi
            openssl rsa -in ${TMP_DIR}/${JWT_KEY_NAME}.pem -outform PEM -pubout -out ${TMP_DIR}/${JWT_KEY_NAME}.pub

            JWT_PUB=$(cat ${TMP_DIR}/${JWT_KEY_NAME}.pub | sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g')
            cat << EOF > ${TMO_DIR}/jwtConfig.json
{
    "jwtConfiguration":[
        {
            "iss": "oms",
            "keys": [
                "jwtAlgo": "RS256",
                "publicKey": "${JWT_PUB}"
            ]
        }
    ]
}
EOF
            kubectl create secret generic ${JWT_KEY_NAME} --from-file=jwt-issuer-config.json=${TMP_DIR}/jwtConfig.json -n ${SIP_NAMESPACE}
            if (( $? != 0 )); then
                log-error "Unable to create JWT issuer secret"
                exit 1
            else
                log-info "Successfully created JWT issuer secret"
            fi  
        else
          log-info "JWT Issuer secret already exists"
        fi

        # Create the truststore password
        ######### The below needs to be augmented and/or changed for external middleware services if utilised.
        log-info "Creating / updating truststore secret"
        cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${SIP_SECRET_NAME}
  namespace: $SIP_NAMESPACE
type: Opaque
stringData:
  truststore_password: ${TRUSTSTORE_PASSWORD}
  cassandra_username: ${CASSANDRA_USERNAME}
  cassandra_password: ${CASSANDRA_PASSWORD}
  elasticsearch_username: ${ELASTICSEARCH_USERNAME}
  elasticsearch_password: ${ELASTICSEARCH_PASSWORD}
  kafka_security_protocol: ${KAFKA_SECURITY_PROTOCOL}
  kafka_sasl_jaas_config: ${KAFKA_SASL_JAAS_CONFIG}
  kafka_user: ${KAFKA_USER}
  kafka_password: ${KAFKA_PASSWORD}
  kafka_sasl_mechanism: ${KAFKA_SASL_MECHANISM}
EOF
        if (( $? != 0 )); then
            log-error "Unable to create or update truststore secret"
            exit 1
        else
            log-info "Successfully created / updated truststore secret"
        fi

        # Create the persistant volume
        if [[ -z $(kubectl get pvc -n $SIP_NAMESPACE | grep $PVC_NAME ) ]]; then
            log-info "Creating the persistent volume $PVC_NAME in namespace $SIP_NAMESPACE"
            cat << EOF | kubectl create -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC_NAME
  namespace: $SIP_NAMESPACE
spec:
  accessModes:
    - ReadWriteMany
  volumeMode: Filesystem
  storageClassName: $SC_NAME
  resources:
    requests:
      storage: ${PVC_SIZE}
EOF
            if (( $? != 0 )); then
                log-error "Unable to create PVC $PVC_NAME in namespace $SIP_NAMESPACE"
                exit 1
            else
                log-info "Created PVC $PVC_NAME in namespace $SIP_NAMESPACE"
            fi

            log-info "Running job to mount volume and force PV creation"
            # Remove any existing job
            if [[ $(kubectl get jobs -n $SIP_NAMESPACE | grep volume-pod ) ]]; then
                log-info "Deleting existing volume-pod job in namespace $SIP_NAMESPACE"
                kubectl delete job -n $SIP_NAMESPACE volume-pod
                if (( $? != 0 )); then
                    log-error "Unable to delete volume-pod job in namespace $SIP_NAMESPACE"
                    exit 1
                else
                    log-info "Deleted volume-pod job in namespace $SIP_NAMESPACE"
                fi
            fi
            cat << EOF | kubectl create -f -
kind: Job
apiVersion: batch/v1
metadata: 
  name: volume-pod
  namespace: $SIP_NAMESPACE
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
                while [[ -z $(kubectl get job volume-pod -n $SIP_NAMESPACE | grep "1/1") ]]; do
                    log-info "Waiting for volume-pod job in namespace $SIP_NAMESPACE to complete"
                    i=$(( $i + 1 ))
                    if (( $i > 10 )); then
                        log-error "Timeout waiting for volume-pod job in namespace $SIP_NAMESPACE to complete"
                        exit 1
                    fi
                    sleep 30
                done
                log-info "Job volume-pod completed in namespace $SIP_NAMESPACE"
            fi
        else
            log-info "PVC $PVC_NAME already exists in namespace $SIP_NAMESPACE"
        fi        

        log-info "Creating SIP instance in namespace $SIP_NAMESPACE"
        cat << EOF | kubectl apply -f -
apiVersion: apps.sip.ibm.com/v1beta1
kind: SIPEnvironment
metadata:
  name: ${SIP_INSTANCE_NAME}
  namespace: ${SIP_NAMESPACE}
  annotations:
    apps.sip.ibm.com/skip-ibm-entitlement-key-check: 'yes'
spec:
  license:
    accept: true
  secret: ${SIP_SECRET_NAME}
  serviceAccount: default
  upgradeStrategy: RollingUpdate
  # This networkPolicy is most open and hence least secure. You have been warned!
  networkPolicy:
    podSelector:
      matchLabels:
        none: none
    policyTypes:
      - Ingress
  ivService:
    serviceGroup: dev
  promisingService:
    serviceGroup: dev
  utilityService:
    serviceGroup: dev
  apiDocsService: {}    
  omsGateway:
    issuerSecret: ${JWT_SECRET_NAME}
    replicas: 1
    cors:
      allowedOrigins: '*'
  externalServices:
    cassandra:
      createDevInstance:
        resources:
          limits:
            cpu: '3'
            memory: 8000Mi
          requests:
            cpu: '1'
            memory: 5000Mi
      keyspace: inventory_visibility_ks
    elasticSearch:
      createDevInstance: {}
    kafka:
      createDevInstance: {}
  common:
    ingress:
      host: $HOSTNAME
      ssl:
       enabled: true
       identitySecretName: ingress-cert
  image:
    imagePullSecrets:
    - name: ibm-entitlement-key
    - name: acr-secret
    repository: ${ACR_NAME}.azurecr.io
    tag: ${SIP_TAG}
    promisingService:
      imageName: sip-promising
      tag: ${SIP_TAG}
      repository: $ACR_NAME.azurecr.io/$CP_REPO_BASE
    omsGateway:
      tag: ${SIP_TAG}
      imageName: oms-gateway
      pullPolicy: IfNotPresent
    apiDocsService:
      tag: ${SIP_TAG}
      repository: $ACR_NAME.azurecr.io/$CP_REPO_BASE
      imageName: sip-api-docs
    ivService:
      tag: ${SIP_TAG}
      repository: $ACR_NAME.azurecr.io/$CP_REPO_BASE
      appImageName: sip-iv-appserver
      backendImageName: sip-iv-backend
      onboardImageName: sip-iv-onboard
    utilityService:
      repository: $ACR_NAME.azurecr.io/$CP_REPO_BASE
      catalog:
        tag: ${SIP_TAG}
        imageName: sip-catalog
        onboardImageName: sip-catalog-onboard
      rules:
        tag: ${SIP_TAG}
        imageName: sip-rules
        onboardImageName: sip-rules-onboard
      carrier:
        tag: ${SIP_TAG}
        onboardImageName: sip-carrier-onboard
        imageName: sip-carrier
      audit:
        tag: ${SIP_TAG}
        imageName: sip-iv-audit
        onboardImageName: sip-iv-audit-onboard
      search:
        tag: ${SIP_TAG}
        imageName: sip-search
        onboardImageName: sip-search-onboard 
      logstash:
        tag: ${SIP_TAG}
        imageName: sip-logstash
  storage:
    accessMode: ReadWriteMany
    capacity: 10Gi
    name: $PVC_NAME
    storageClassName: $SC_NAME
EOF
        if (( $? != 0 )); then
            log-error "Unable to create SIP instance in namespace $SIP_NAMESPACE"
            exit 1
        else
            # Wait for instance to finish creation            #######TODO

            ###########
            log-info "Successfully created SIP instance in namespace $SIP_NAMESPACE"
        fi

#         # Create the IVServiceGroup instance
#         log-info "Creating IVServiceGroup"
#         cat << EOF | kubectl apply -f -
# apiVersion: apps.sip.ibm.com/v1beta1
# kind: IVServiceGroup
# metadata:
#   name: dev
#   namespace: ${SIP_NAMESPACE}
# spec:
#   active: true
#   # Allowed values are: OFF, FATAL, ERROR, WARN, INFO, DEBUG, TRACE, ALL
#   logLevel: ${LOG_LEVEL} 
#   image:
#     imagePullSecrets:    
#         - name: ibm-entitlement-key
#         - name: acr-secret 
#     repository: $ACR_NAME.azurecr.io/$CP_REPO_BASE
#     tag: $(cat ${WORKSPACE_DIR}/${IMAGE_LIST_SIP_FILENAME} | grep "sip-logstash:" | awk -F':' '{print $2}')  
#   appServers:
#     - active: true
#       groupName: appserver
#       names:
#         - ApiSupplies
#         - ApiDemands
#         - ApiAvailability
#         - ApiReservation
#         - ApiBuc
#         - ApiConfig
#       replicaCount: 1
#   backendServers:
#     - active: true
#       groupName: backend
#       names:
#         - 'ComputeProdAvl:1'
#         - 'DemandAuditPublisher:1'
#         - 'InvActivityPrcs:1'
#         - 'InvDemandSync:1'
#         - 'InvSupplySync:1'
#         - 'PromisingDistributionGroupSync:1'
#         - 'SupplyTransactionUpdater:1'
#         - 'ManageDgAvlBreakup:1'
#         - 'ManageInvDemand:1'
#         - 'ManageBundleItemDgAvlBreakup:1'
#         - 'ManageBundleItemNodeAvlBreakup:1'
#         - 'ManageInvSupply:1'
#         - 'ManageNodeAvlBreakup:1'
#         - 'ManageParentItemNodeAvlBreakup:1'
#         - 'SortDgAvlBreakupNodes:1'
#         - 'SupplyAuditPublisher:1'
#         - 'PromisingShipNodeSync:1'
#         - 'SyncAll:1'
#         - 'DirectKafkaSupplyPublisher:1'
#         - 'DirectKafkaDemandChangePublisher:1'
#         - 'DirectKafkaProductAvailabilityV2Publisher:1'
#         - 'DirectKafkaDgAvailabilityBreakupPublisher:1'
#         - 'DirectKafkaProductAvailabilityBreakupPublisher:1'
#         - 'SafetyStockTriggerConsumer:1'
#       replicaCount: 1
#   defaultresources:
#     limits:
#       cpu: '1'
#       memory: 1536Mi
#     requests:
#       cpu: 100m
#       memory: 1Gi
# EOF
#         if (( $? != 0 )); then
#             log-error "Unable to apply IVServiceGroup dev in namespace $SIP_NAMESPACE"
#             exit 1
#         else
#             log-info "Applied IVServiceGroup dev in namespace $SIP_NAMESPACE"
#         fi

#         # Create promising group 
#         cat << EOF | kubectl apply -f - 
# apiVersion: apps.sip.ibm.com/v1beta1
# kind: PromisingServiceGroup
# metadata:
#   name: dev
#   namespace: ${SIP_NAMESPACE}
# spec:
#   active: true
#   logLevel: ${LOG_LEVEL} 
#   image:
#     imagePullSecrets:    
#         - name: ibm-entitlement-key
#         - name: acr-secret 
#     repository: $ACR_NAME.azurecr.io/$CP_REPO_BASE
#     tag: $(cat ${WORKSPACE_DIR}/${IMAGE_LIST_SIP_FILENAME} | grep "sip-logstash:" | awk -F':' '{print $2}')
#   appServers:
#     - active: true
#       groupName: appserver
#       names:
#         - promising-server
#       replicaCount: 1
#   backendServers:
#     - active: true
#       groupName: backend
#       names:
#         - 'odx-source-stream-flatten:1'
#         - 'iv-breakup-source-stream-flatten:1'
#         - 'cas-carrier-service-sync-flatten:1'
#         - 'prm-source-stream-demux:1'
#         - 'prm-shipnode-sync:1'
#         - 'prm-iv-breakup-sink-stream-consumer:1'
#         - 'prm-carrier-service-sync:1'
#         - 'prm-carrier-service-deleted:1'
#       replicaCount: 1
#   defaultresources:
#     limits:
#       cpu: '1'
#       memory: 1536Mi
#     requests:
#       cpu: 100m
#       memory: 1Gi
# EOF

#         if (( $? != 0 )); then
#             log-error "Unable to apply PromisingServiceGroup dev in namespace $SIP_NAMESPACE"
#             exit 1
#         else
#             log-info "Applied PromisingServiceGroup dev in namespace $SIP_NAMESPACE"
#         fi

#         # Create ingress
#         if [[ -z $(kubectl get ingress -n $SIP_NAMESPACE | grep "sip-ingress ") ]]; then
#             log-info "Creating ingress instance for SIP instance"
#             cat << EOF | kubectl apply -f -
# apiVersion: networking.k8s.io/v1
# kind: Ingress
# metadata:
#   name: sip-ingress
#   namespace: ${SIP_NAMESPACE}
#   annotations:
#     nginx.ingress.kubernetes.io/backend-protocol: HTTPS
# spec:
#   ingressClassName: webapprouting.kubernetes.azure.com
#   tls:
#   - hosts:
#     - ${HOSTNAME}
#   rules:
#   - host: ${HOSTNAME}
#     http:
#       paths:
#       - path: /
#         pathType: Prefix
#         backend:
#           service: 
#             name: sip
#             port: 
#               number: 8300
# EOF
#         else
#             log-info "Ingress instance already exists"
#         fi
    else
        log-info "License not accepted. Instance not created"
    fi
else
    log-info "SIP instance already exists in namespace $SIP_NAMESPACE"
fi

# Output the key details
jq -n -c \
    --arg privateKey \"$(cat ./tempkey)\" \
    --arg publicKey \"$(cat ./tempkey.pub)\" \
    '{\"jwtKey\": {\"privateKey\": $privateKey, \"publicKey\": $publicKey}}' > $AZ_SCRIPTS_OUTPUT_PATH

log-info "Script completed"