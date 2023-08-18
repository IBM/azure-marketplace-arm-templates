#!/bin/bash

# Set defaults
if [[ -z $RESOURCE_GROUP ]]; then RESOURCE_GROUP="sip-test1-rg"; fi
if [[ -z $ACR_NAME ]]; then ACR_NAME="sip1acr"; fi
if [[ -z $ARO_CLUSTER ]]; then ARO_CLUSTER="sip-aro"; fi
if [[ -z $LOCATION ]]; then LOCATION="eastus"; fi
if [[ -z $TAG ]]; then TAG="created-by=$(az account show --query 'user.name' -o tsv)"; fi
if [[ -z $ARO_TEMPLATE ]]; then ARO_TEMPLATE="aro-create-azure-deploy.json"; fi
if [[ -z $WORKSPACE_DIR ]]; then WORKSPACE_DIR="$(pwd)"; fi
if [[ -z $NAMESPACE ]]; then NAMESPACE="sip"; fi
if [[ -z $SC_NAME ]]; then SC_NAME="azure-file"; fi
if [[ -z $PVC_NAME ]]; then PVC_NAME="sip-pvc"; fi
if [[ -z $SIP_SECRET ]]; then SIP_SECRET="sip-secret"; fi
if [[ -z $NAME_PREFIX ]]; then NAME_PREFIX="sip"; fi
if [[ -z $VNET_NAME ]]; then VNET_NAME="vnet"; fi
if [[ -z $VNET_CIDR ]]; then VNET_CIDR="10.0.0.0/20"; fi
if [[ -z $CONTROL_SUBNET_NAME ]]; then CONTROL_SUBNET_NAME="control-subnet"; fi
if [[ -z $CONTROL_SUBNET_CIDR ]]; then CONTROL_SUBNET_CIDR="10.0.0.0/24"; fi
if [[ -z $WORKER_SUBNET_NAME ]]; then WORKER_SUBNET_NAME="worker-subnet"; fi
if [[ -z $WORKER_SUBNET_CIDR ]]; then WORKER_SUBNET_CIDR="10.0.1.0/24"; fi
if [[ -z $STORAGE_SUBNET_NAME ]]; then STORAGE_SUBNET_NAME="storage-subnet"; fi
if [[ -z $STORAGE_SUBNET_CIDR ]]; then STORAGE_SUBNET_CIDR="10.0.2.0/24"; fi
if [[ -z $WORKER_SIZE ]]; then WORKER_SIZE="Standard_D4s_v3"; fi
if [[ -z $WORKER_COUNTR ]]; then WORKER_COUNT=3; fi
if [[ -z $DOMAIN_NAME ]]; then DOMAIN_NAME="$(echo "${NAME_PREFIX}${RANDOM}" | base64 | tr -dc '[:alpha:]' | tr '[:upper:]' '[:lower:]' | head -7; echo)"; fi
if [[ -z $INSTANCE_NAME ]]; then INSTANCE_NAME="sip-environment"; fi

# Create resource group
if [[ -z $(az group list --query "[?name == '$RESOURCE_GROUP']" -o tsv) ]]; then
    echo "INFO: Creating resource group $RESOURCE_GROUP"
    az group create -l $LOCATION -n $RESOURCE_GROUP --tags $TAG
else
    echo "INFO: Resource group $RESOURCE_GROUP already exists"
fi

# Build ARO cluster and file share

if [[ -z $(az aro list -g $RESOURCE_GROUP --query "[?name == '$ARO_CLUSTER']" -o tsv) ]]; then   
    echo "INFO: Creating ARO cluster $ARO_CLUSTER"
    az deployment group create \
        --resource-group $RESOURCE_GROUP \
        --name "aro-deployment" \
        --template-uri https://raw.githubusercontent.com/ibm-ecosystem-engineering/azure-arm-templates/main/openshift/aro/azuredeploy.json \
        --mode Incremental \
        --parameters \
            namePrefix="$NAME_PREFIX" \
            clusterName="$ARO_CLUSTER" \
            location="$LOCATION" \
            vnetName="$VNET_NAME" \
            createVnet=true \
            createAzureFileStorage=true \
            vnetCIDR="$VNET_CIDR" \
            controlSubnetCIDR="$CONTROL_SUBNET_CIDR" \
            workerSubnetCIDR="$WORKER_SUBNET_CIDR" \
            storageSubnetCIDR="$STORAGE_SUBNET_CIDR" \
            controlSubnetName="$CONTROL_SUBNET_NAME" \
            workerSubnetName="$WORKER_SUBNET_NAME" \
            storageSubnetName="$STORAGE_SUBNET_NAME" \
            domain="$DOMAIN_NAME" \
            podCIDR="10.128.0.0/14" \
            serviceCIDR="172.30.0.0/16" \
            masterSize="Standard_D8s_v3" \
            workerSize="$WORKER_SIZE" \
            workerCount="$WORKER_COUNT" \
            encryption=true \
            fipsEnabled=false \
            workerDiskSize=128 \
            apiVisibility="Public" \
            ingressVisibility="Public" \
            "branch"="main"
    
    if (( $? != 0 )) ; then
        echo "ERROR: Deployment failed"
        exit 1 
    else
        echo "INFO: Cluster deployment successful"
    fi
else
    echo "INFO: ARO cluster already exists"
fi

# Get ARO credentials
echo "Getting ARO cluster details"
CLUSTER_API="$( az aro show -n $ARO_CLUSTER -g $RESOURCE_GROUP --query 'apiserverProfile.url' -o tsv )"
ARO_PASSWORD="$(az aro list-credentials -n $ARO_CLUSTER -g $RESOURCE_GROUP --query 'kubeadminPassword' -o tsv)"
ARO_USERNAME="$(az aro list-credentials -n $ARO_CLUSTER -g $RESOURCE_GROUP --query 'kubeadminUsername' -o tsv)"
ARO_INGRESS=$(az aro show -g $RESOURCE_GROUP -n $ARO_CLUSTER --query consoleProfile.url -o tsv | sed -e 's#^https://console-openshift-console.##; s#/##')

# Login to cluster
echo "Logging into ARO cluster"
oc login -u $ARO_USERNAME -p $ARO_PASSWORD $CLUSTER_API

# Build Container registry
if [[ -z $(az acr list --query "[?name == '$ACR_NAME']" -o tsv) ]]; then
    echo "INFO: Creating Azure container registry $ACR_NAME"
    az acr create \
        --resource-group $RESOURCE_GROUP \
        --name $ACR_NAME \
        --sku Basic \
        --tags $TAG

        if (( $? != 0 )); then
            echo "ERROR: Failed to create Azure container registry"
            exit 1
        fi
else
    echo "INFO: Azure container registry $ACR_NAME already exists"
fi

az acr update \
    --name $ACR_NAME \
    --admin-enabled true

# Get ACR credentials
echo "INFO: Getting Azure Container Registry details"
ACR_USERNAME="$(az acr credential show -n $ACR_NAME -g $RESOURCE_GROUP --query 'username' -o tsv)"
ACR_PASSWORD="$(az acr credential show -n $ACR_NAME -g $RESOURCE_GROUP --query 'passwords[0].value' -o tsv)"
ACR_SERVER="$(az acr list -g $RESOURCE_GROUP --query '[0].loginServer' -o tsv)"

# Install SIP

if [[ -z $(oc get deployments -n $NAMESPACE | grep ibm-sip-controller-manager) ]]; then

    echo "INFO: Installing SIP operator"

    $WORKSPACE_DIR/install_operators.sh \
        --NAMESPACE=$NAMESPACE \
        --CONTAINER_REGISTRY=$ACR_SERVER \
        --CONTAINER_REGISTRY_USER=$ACR_USERNAME \
        --CONTAINER_REGISTRY_PASSWORD=$ACR_PASSWORD
else
    echo "INFO: SIP Operator already isntalled"
fi

# Create PVC

if [[ -z $(oc get pvc -n $NAMESPACE | grep $PVC_NAME) ]]; then
    echo "INFO: Creating PVC $PVC_NAME for SIP in namespace $NAMESPACE" 

    cat << EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC_NAME
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteMany
  volumeMode: Filesystem
  storageClassName: $SC_NAME
  resources:
    requests:
      storage: 10Gi
EOF

else
    echo "INFO: PVC $PVC_NAME already exists"
fi

# Create the SIP secret (blank in this case)

if [[ -z $(oc get secret -n $NAMESPACE | grep $SIP_SECRET) ]]; then

    echo "INFO: Creating secret $SIP_SECRET"

    cat << EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
   name: $SIP_SECRET
   namespace: $NAMESPACE
type: Opaque
stringData:
  secret: ""

EOF

else
    echo "INFO: Secret $SIP_SECRET already exists"
fi

# Build the public key



if [[ ! -f ${WORKSPACE_DIR}/jwt-key.pem ]]; then
    echo "INFO: Generating key pair for JWT"
    openssl genrsa -out ${WORKSPACE_DIR}/jwt-key.pem 2048
else
    echo "INFO: Using existing key pair ${WORKSPACE_DIR}/jwt-key.pem"
fi

if [[ -z $(oc get secret -n $NAMESPACE | grep jwt-configuration) ]]; then

    echo "INFO: Creating JWT secret"

    openssl rsa -in ${WORKSPACE_DIR}/jwt-key.pem -outform PEM -pubout -out ${WORKSPACE_DIR}/jwt-key.pub

    JWT_PUB=$(cat ${WORKSPACE_DIR}/jwt-key.pub | sed '1h;1!H;$!d;x;s/\n/\\n/g')

    cat << EOF > ${WORKSPACE_DIR}/jwtConfig.json
{
    "jwtConfiguration":[
        {
            "iss": "oms",
            "keys": [
                {
                    "jwtAlgo": "RS256",
                    "publicKey": "${JWT_PUB}"
                }
            ]
        }
    ]
}
EOF

    oc create secret generic -n $NAMESPACE jwt-configuration --from-file=${WORKSPACE_DIR}/jwtConfig.json

    if (( $? != 0 )); then
        echo "ERROR: Unable to create jwt-configuration secret"
        exit 1
    fi
else
    echo "INFO: jwt-configuration secret already exists"
fi

# Create the ingress certificate secret

if [[ -z $(oc get certificatemanager -n $NAMESPACE | grep ingress-cert) ]]; then
    echo "INFO: Creating Ingress certificate secret"

    cat << EOF | oc apply -f -
apiVersion: apps.jwt.verifier.ibm.com/v1beta1
kind: CertificateManager
metadata:
    name: ingress-cert
    namespace: $NAMESPACE
spec:
    expiryDays: 365
    hostName: "sipservice-${NAMESPACE}.${ARO_INGRESS}"
EOF
    if (( $? != 0 )); then
        echo "ERROR: Unable to create Certificate Manager"
        exit 1
    fi
else
    echo "INFO: Certificate Manager already exists"
fi

# Wait for Certificate Manager to be available
count=0
while [[ $(oc get certificatemanager -n $NAMESPACE ingress-cert -o json | jq -r '.status.condition.reason') != "ExecutionCompleted" ]]; do
    echo "INFO: Waiting for ingress cert to be ready. Waited $count minutes. Will wait up to 10 minutes."
    sleep 60
    count=$(( $count + 1 ))
    if (( $count > 10 )); then
        echo "ERROR: Timeout exceeded waiting for ingress cert"
    fi
done

echo "INFO: Ingress cert ready"

# Create the SIP Environment instance

if [[ $(oc get sipenvironment -n $NAMESPACE  $INSTANCE_NAME | grep "not found") ]]; then

    echo "INFO: Creating SIP Environment instance $INSTANCE_NAME"

    cat << EOF | oc apply -f -
apiVersion: apps.sip.ibm.com/v1beta1
kind: SIPEnvironment
metadata:
  name: $INSTANCE_NAME
  namespace: $NAMESPACE
  annotations: 
    apps.sip.ibm.com/skip-ibm-entitlement-key-check: 'yes'
spec:
  secret: $SIP_SECRET
  serviceAccount: default
  upgradeStrategy: RollingUpdate
  networkPolicy:
    podSelector:
      matchLabels:
        none: none
    policyTypes:
      - Ingress
  ivService:
    serviceGroup: dev
  utilityService: 
    serviceGroup: dev
  jwtVerifierService:
    issuerSecret: jwt-configuration
    replicas: 1
    cors:
      allowedOrigins: ""
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
      host: $ARO_INGRESS
      ssl:
        enabled: true
        identitySecretName: ingress-cert
  image:
    imagePullSecrets:
      - name: ibm-sip-jwt-operators-pull-secret
    repository: $ACR_SERVER
    jwtVerifierService:
      tag: 05-07-2023
    ivService:
      tag: container_v23.05.30.4
    utilityService:
      audit:
        tag: V.23.06.15.0-release-Ga006287-J1
      configDataSync:
        tag: release.v2023.05.30.0
      catalog:
        tag: V.23.05.31.2-release-Gaae9d5d-J1
      rules:
        tag: V.23.06.01.0-release-G23db53b-J4
      search:
        tag: V.23.06.15.0-release-Ga006287-J1
  storage:
    accessMode: ReadWriteMany
    capacity: 10Gi
    name: $PVC_NAME
    storageClassName: $SC_NAME
EOF

    if (( $? != 0 )); then
        echo "ERROR: Unable to create instance $INSTANCE_NAME"
        exit 1
    fi
else
    echo "INFO: Instance $INSTANCE_NAME already exists"
fi

echo "INFO: Script completed"