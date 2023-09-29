#!/bin/bash

# Supports RHEL 8 and RHEL 9

function log-output() {
    MSG=${1}

    if [[ -z $OUTPUT_DIR ]]; then
        OUTPUT_DIR="$(pwd)"
    fi
    mkdir -p $OUTPUT_DIR

    if [[ -z $OUTPUT_FILE ]]; then
        OUTPUT_FILE="script-output.log"
    fi

    echo "$(date -u +"%Y-%m-%d %T") ${MSG}" >> ${OUTPUT_DIR}/${OUTPUT_FILE}
    echo ${MSG}
}

function usage()
{
   echo "Installs Instana on a RHEL server"
   echo
   echo "Usage: ${0} -p PARAMETERS [-a]"
   echo "  options:"
   echo "  -p     install parameters in json format"
   echo "  -a     (optional) accept the license terms"
   echo "  -h     Print this help"
   echo
}

log-output "INFO: Script started"

# Get the command line arguments
while getopts ":p:ah" option; do
   case $option in
      h) # display Help
         usage
         exit 1;;
      p) # install parameters
         PARAMS=$OPTARG;;
      a) # Accept license   
         LICENSE="accept";;
     \?) # Invalid option
         echo "Error: Invalid option"
         usage
         exit 1;;
   esac
done

# Check running as root
if [[ $(id -u) != 0 ]]; then
    log-output "ERROR: Not running as root. Please change to root and retry"
    exit 1
fi

# Parse parameters
if [[ -z $PARAMS ]]; then
    log-output "ERROR: No parameters provided"
    exit 1
fi

DOWNLOAD_KEY=$(echo $PARAMS | jq -r '.credentials.downloadKey')
SALES_KEY=$(echo $PARAMS | jq -r '.credentials.salesKey')
TENANT_NAME=$(echo $PARAMS | jq -r '.config.tenantName')
ENV_NAME=$(echo $PARAMS | jq -r '.config.envName')
FQDN=$(echo $PARAMS | jq -r '.config.fqdn')
DOCKER_DISK_SIZE=$(echo $PARAMS | jq -r '.config.dockerDiskSize')
AGENT_TYPE=$(echo $PARAMS | jq -r '.config.agentType')
AGENT_MODE=$(echo $PARAMS | jq -r '.config.agentMode')

# Check critical parameters
VAR_NOT_SET=""

if [[ $DOWNLOAD_KEY == null ]]; then VAR_NOT_SET="DOWNLOAD_KEY"; fi
if [[ $SALES_KEY == null ]]; then VAR_NOT_SET="SALES_KEY"; fi
if [[ $TENANT_NAME == null ]]; then VAR_NOT_SET="TENANT_NAME"; fi
if [[ $ENV_NAME == null ]]; then VAR_NOT_SET="ENV_NAME"; fi
if [[ $FQDN == null ]]; then VAR_NOT_SET="FQDN"; fi

if [[ -n $VAR_NOT_SET ]]; then
    log-output "ERROR: $VAR_NOT_SET not set. Please set and retry."
    exit 1
fi

# Set defaults
if [[ -z $TMP_DIR ]] || [[ $TMP_DIR == null ]]; then TMP_DIR="/tmp"; fi
if [[ -z $LICENSE ]] ; then LICENSE="decline"; fi
if [[ -z $DOCKER_DISK_SIZE ]] || [[ $DOCKER_DISK_SIZE == null ]]; then DOCKER_DISK_SIZE=20; fi
if [[ -z $AGENT_TYPE ]] || [[ $AGENT_TYPE == null ]]; then AGENT_TYPE="docker"; fi
if [[ -z $AGENT_MODE ]] || [[ $AGENT_MODE == null ]]; then AGENT_MODE="INFRASTRUCTURE"; fi

# Extend the var logical volume for docker
log-output "INFO: Extending var filesystem to accommodate docker registry"
CURRENT_VAR_SIZE=$(lvscan | grep varlv | awk '{print $3}' | sed 's/\[//g' | awk -F '.' '{print $1}')
NEW_VAR_SIZE=$(( $CURRENT_VAR_SIZE + $DOCKER_DISK_SIZE ))
lvextend -r -L ${NEW_VAR_SIZE}G /dev/rootvg/varlv

if [[ $? != 0 ]]; then
    log-output "ERROR: Unable to extend var filesystem to $NEW_VAR_SIZE for docker registry"
    exit 1
fi

# Install Docker

if [[ -z $(which docker) ]]; then

    log-output "INFO: Installing docker"

    # TODO: Test the below with different RHEL versions (tested 9.2)
    ARCH="$(arch)"
    OS_MAJOR="$(uname -a | awk '{print $3}' | awk -F '.' '{print $6}' | awk -F '_' '{print $1}')"
    OS_MINOR="$(echo $OS_MAJOR | sed 's/el//g' )"

    # Download and install docker-ce, containerd.io and other packages
    wget -q -O $TMP_DIR/containerd.io.rpm https://download.docker.com/linux/centos/${OS_MINOR}/${ARCH}/stable/Packages/containerd.io-1.6.24-3.1.${OS_MAJOR}.${ARCH}.rpm
    wget -q -O $TMP_DIR/docker-ce.rpm https://download.docker.com/linux/centos/${OS_MINOR}/${ARCH}/stable/Packages/docker-ce-24.0.6-1.${OS_MAJOR}.${ARCH}.rpm
    wget -q -O $TMP_DIR/docker-cli.rpm https://download.docker.com/linux/centos/${OS_MINOR}/${ARCH}/stable/Packages/docker-ce-cli-24.0.6-1.${OS_MAJOR}.${ARCH}.rpm
    wget -q -O $TMP_DIR/docker-rootless-extras.rpm https://download.docker.com/linux/centos/${OS_MINOR}/${ARCH}/stable/Packages/docker-ce-rootless-extras-24.0.6-1.${OS_MAJOR}.${ARCH}.rpm

    yum install -y ${TMP_DIR}/containerd.io.rpm
    yum install -y ${TMP_DIR}/docker-cli.rpm
    yum install -y ${TMP_DIR}/docker-rootless-extras.rpm ${TMP_DIR}/docker-ce.rpm

    # Start the docker service
    systemctl enable docker
    systemctl start docker
else
    log-output "INFO: Docker already installed on VM" 
fi

# Install the Instana console
if [[ -z $(which instana) ]]; then
    log-output "INFO: Installing the Instana console"
    cat << EOF > /etc/yum.repos.d/Instana-Product.repo
[instana-product]
name=Instana-Product
baseurl=https://_:$DOWNLOAD_KEY@artifact-public.instana.io/artifactory/rel-rpm-public-virtual/
enabled=1
gpgcheck=0
gpgkey=https://_:$DOWNLOAD_KEY@artifact-public.instana.io/artifactory/api/security/keypair/public/repositories/rel-rpm-public-virtual
repo_gpgcheck=1
EOF

    yum clean expire-cache -y && yum update -y
    yum install -y instana-console
else
    log-output "INFO: Instana console already installed"
fi

# Create the self-signed certificates
if [[ -z $INSTANA_CERT ]]; then
    log-output "INFO: Creating self-signed certificates"
    openssl req -x509 -newkey rsa:2048 -keyout /root/instana.key -out /root/instana.crt -days 365 -nodes -subj "/CN=$FQDN"
    openssl rsa -in /root/instana.key -pubout -out /root/instana-pub.key
else
    log-output "INFO: Using provided certificates"
fi

# Open firewall ports
log-output "INFO: Opening firewall ports for Instana"
firewall-cmd --zone=public --add-port=443/tcp --permanent
firewall-cmd --zone=public --add-port=80/tcp --permanent
firewall-cmd --zone=public --add-port=86/tcp --permanent
firewall-cmd --zone=public --add-port=446/tcp --permanent
firewall-cmd --zone=public --add-port=1444/tcp --permanent
firewall-cmd --reload

# Make sure directories exist
log-output "INFO: Created directories for Instana"
mkdir -p /mnt/data
mkdir -p /mnt/traces
mkdir -p /mnt/metrics

##################TEMP
echo $PARAMS > $(pwd)/instanaParameters.json
exit 0

# Create the settings file


# Install Instana
instana init -y

# Add the license
if [[ $LICENSE = "accept" ]]; then
    log-output "INFO: Applying license"
    instana license download
    instana license import -f $(pwd)/license
else
    log-output "INFO: License not accepted. License not applied."
fi

# Install monitoring agent on the Instana VM host
if [[ $AGENT_TYPE == "docker" ]]; then 
    # Create the docker Instana agent
    log-output "INFO: Starting docker agent"
    docker run \
    --detach \
    --name instana-agent \
    --volume /var/run:/var/run \
    --volume /run:/run \
    --volume /dev:/dev:ro \
    --volume /sys:/sys:ro \
    --volume /var/log:/var/log:ro \
    --privileged \
    --net=host \
    --pid=host \
    --env="INSTANA_AGENT_ENDPOINT=$(ifconfig eth0 | grep "inet " | awk '{print $2}')" \
    --env="INSTANA_AGENT_ENDPOINT_PORT=1444" \
    --env="INSTANA_AGENT_KEY=${DOWNLOAD_KEY}" \
    --env="INSTANA_AGENT_MODE=${AGENT_MODE}" \
    --env="INSTANA_DOWNLOAD_KEY=${DOWNLOAD_KEY}" \
    icr.io/instana/agent

elif [[ $AGENT_TYPE = "host" ]]; then
    # Install the Instana server agent in the Instana VM
    log-output "INFO: Creating instana host agent"
    curl -o setup_agent.sh https://setup.instana.io/agent \
        && chmod 700 ./setup_agent.sh \
        && sudo ./setup_agent.sh \
        -a ${DOWNLOAD_KEY} \
        -d ${DOWNLOAD_KEY} \
        -t dynamic \
        -m infra \
        -e ${FQDN}:1444  -y
else
    log-output "INFO: Unknown agent type $AGENT_TYPE. No agent installed."
fi