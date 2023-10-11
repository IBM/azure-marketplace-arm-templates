#!/bin/bash

# Supports RHEL 8 and RHEL 9

#### TODO: 
# Add support for user supplied certificates

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
INSTANA_PASSWORD=$(echo $PARAMS | jq -r '.credentials.instanaPassword')
TENANT_NAME=$(echo $PARAMS | jq -r '.config.tenantName')
ENV_NAME=$(echo $PARAMS | jq -r '.config.envName')
FQDN=$(echo $PARAMS | jq -r '.config.fqdn')
DOCKER_DISK_SIZE=$(echo $PARAMS | jq -r '.config.dockerDiskSize')
DATA_DISK_SIZE=$(echo $PARAMS | jq -r '.config.dataDiskSize')
METRICS_DISK_SIZE=$(echo $PARAMS | jq -r '.config.metricsDiskSize')
TRACES_DISK_SIZE=$(echo $PARAMS | jq -r '.config.tracesDiskSize')
AGENT_TYPE=$(echo $PARAMS | jq -r '.config.agentType')
AGENT_MODE=$(echo $PARAMS | jq -r '.config.agentMode')

# Check critical parameters
VAR_NOT_SET=""

if [[ $DOWNLOAD_KEY == null ]]; then VAR_NOT_SET="DOWNLOAD_KEY"; fi
if [[ $SALES_KEY == null ]]; then VAR_NOT_SET="SALES_KEY"; fi
if [[ $TENANT_NAME == null ]]; then VAR_NOT_SET="TENANT_NAME"; fi
if [[ $ENV_NAME == null ]]; then VAR_NOT_SET="ENV_NAME"; fi
if [[ $FQDN == null ]]; then VAR_NOT_SET="FQDN"; fi
if [[ $INSTANA_PASSWORD == null ]]; then VAR_NOT_SET="INSTANA_PASSWORD"; fi
if [[ $DOCKER_DISK_SIZE == null ]]; then VAR_NOT_SET="DOCKER_DISK_SIZE"; fi
if [[ $METRICS_DISK_SIZE == null ]]; then VAR_NOT_SET="METRICS_DISK_SIZE"; fi
if [[ $TRACES_DISK_SIZE == null ]]; then VAR_NOT_SET="TRACES_DISK_SIZE"; fi

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
if [[ -z $MOUNT_DISKS ]] || [[ $MOUNT_DISKS == null ]]; then MOUNT_DISKS=true; fi
if [[ -z $HOME ]]; then export HOME="/root"; fi

# Wait for cloud-init to finish
count=0
while [[ $(/usr/bin/ps xua | grep cloud-init | grep -v grep) ]]; do
    log-output "INFO: Waiting for cloud init to finish. Waited $count minutes. Will wait 15 mintues."
    sleep 60
    count=$(( $count + 1 ))
    if (( $count > 15 )); then
        log-output "ERROR: Timeout waiting for cloud-init to finish"
        exit 1;
    fi
done
log-output "INFO: cloud-init finished. Proceeding with deployment"

# Extend the var logical volume for docker
log-output "INFO: Extending var filesystem to accommodate docker registry"
CURRENT_VAR_SIZE=$(lvscan | grep varlv | awk '{print $3}' | sed 's/\[//g' | awk -F '.' '{print $1}')
NEW_VAR_SIZE=$(( $CURRENT_VAR_SIZE + $DOCKER_DISK_SIZE ))
lvextend -r -L ${NEW_VAR_SIZE}G /dev/rootvg/varlv

if (( $? != 0 )); then
    log-output "ERROR: Unable to extend var filesystem to $NEW_VAR_SIZE for docker registry"
    exit 1
fi

# Install Docker
if [[ -z $(which docker) ]]; then

    log-output "INFO: Installing docker"
    ARCH="$(arch)"
    OS_MAJOR="$(uname -a | awk '{print $3}' | awk -F '.' '{print $6}' | awk -F '_' '{print $1}')"
    OS_MINOR="$(echo $OS_MAJOR | sed 's/el//g' )"

    # Download and install docker-ce, containerd.io and other packages
    wget -q -O $TMP_DIR/containerd.io.rpm https://download.docker.com/linux/centos/${OS_MINOR}/${ARCH}/stable/Packages/containerd.io-1.6.24-3.1.${OS_MAJOR}.${ARCH}.rpm
    wget -q -O $TMP_DIR/docker-ce.rpm https://download.docker.com/linux/centos/${OS_MINOR}/${ARCH}/stable/Packages/docker-ce-24.0.6-1.${OS_MAJOR}.${ARCH}.rpm
    wget -q -O $TMP_DIR/docker-cli.rpm https://download.docker.com/linux/centos/${OS_MINOR}/${ARCH}/stable/Packages/docker-ce-cli-24.0.6-1.${OS_MAJOR}.${ARCH}.rpm
    wget -q -O $TMP_DIR/docker-rootless-extras.rpm https://download.docker.com/linux/centos/${OS_MINOR}/${ARCH}/stable/Packages/docker-ce-rootless-extras-24.0.6-1.${OS_MAJOR}.${ARCH}.rpm

    log-output "INFO: Installing containerd.io"
    yum install -y ${TMP_DIR}/containerd.io.rpm
    if (( $? != 0 )); then
        log-output "ERROR: Unable to install containerd.io"
        exit 1
    else
        log-output "INFO: Successfully installed containerd.io"
    fi

    log-output "INFO: Installing docker cli"
    yum install -y ${TMP_DIR}/docker-cli.rpm
    if (( $? != 0 )); then
        log-output "ERROR: Unable to install Docker cli"
        exit 1
    else
        log-output "INFO: Successfully installed Docker cli"
    fi

    log-output "INFO: Installing Docker CE and Rootless Extras"
    yum install -y ${TMP_DIR}/docker-rootless-extras.rpm ${TMP_DIR}/docker-ce.rpm
    if (( $? != 0 )); then
        log-output "ERROR: Unable to install Docker CE"
        exit 1
    else
        log-output "INFO: Successfully installed Docker CE" 
    fi

    # Start the docker service
    systemctl enable docker
    if (( $? != 0 )); then
        log-output "ERROR: Unable to enable Docker service"
        exit 1
    fi
else
    log-output "INFO: Docker already installed on VM" 
fi

log-output "INFO: Starting docker"
systemctl start docker
if (( $? != 0 )); then
    log-output "ERROR: Unable to start docker"
    exit 1
else
    log-output "INFO: Successfully started docker"
fi

# Install the Instana console
if [[ -z $(which instana) ]]; then
    log-output "INFO: Installing the Instana console tool"
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
    if (( $? != 0 )); then
        log-output "ERROR: Unable to install the Instana console tool"
        exit 1
    else
        log-output "INFO: Successfully installed the Instana console tool"
    fi
else
    log-output "INFO: Instana console already installed"
fi

# Create the self-signed certificates
if [[ -z $INSTANA_CERT ]] || [[ -z $INSTANA_KEY ]]; then
    log-output "INFO: Creating self-signed certificates"
    openssl req -x509 -newkey rsa:2048 -keyout /root/instana.key -out /root/instana.crt -days 365 -nodes -subj "/CN=$FQDN"
else
    log-output "INFO: Using provided certificates"
    echo $INSTANA_CERT > /root/instana.crt
    echo $INSTANA_KEY > /root/instana.key
    chmod 644 /root/instana.crt
    chmod 600 /root/instana.key
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

# Identify drives
DATA_DISKS=( $(lsblk --json | jq -r ".blockdevices[] | select(.type == \"disk\") | select(.mountpoint == null) | select(.children == null ) | select(.size == \"${DATA_DISK_SIZE}G\") | .name") )
METRICS_DISKS=( $(lsblk --json | jq -r ".blockdevices[] | select(.type == \"disk\") | select(.mountpoint == null) | select(.children == null ) | select(.size == \"${METRICS_DISK_SIZE}G\") | .name") )
TRACES_DISKS=( $(lsblk --json | jq -r ".blockdevices[] | select(.type == \"disk\") | select(.mountpoint == null) | select(.children == null ) | select(.size == \"${TRACES_DISK_SIZE}G\") | .name") )

if [[ ${#DATA_DISKS[@]} == 0 ]]; then
    echo "ERROR: No data disk found"
else
    DATA_DRIVE=${DATA_DISKS[0]}
    DATA_DISK="/dev/${DATA_DISKS[0]}"
fi

if [[ ${#METRICS_DISKS[@]} == 0 ]]; then
    echo "ERROR: No metrics disk found"
else
    for (( i=0; i<${#METRICS_DISKS[@]}; i++  )); do
        if [[ ${METRICS_DISKS[$i]} != $DATA_DRIVE ]]; then
            METRICS_DRIVE="${METRICS_DISKS[$i]}"
            METRICS_DISK="/dev/${METRICS_DISKS[$i]}"
            break
        fi
    done
fi

if [[ ${#TRACES_DISKS[@]} == 0 ]]; then
    echo "ERROR: No traces disk found"
else
     for (( i=0; i<${#TRACES_DISKS[@]}; i++  )); do
        if [[ ${TRACES_DISKS[$i]} != $DATA_DRIVE ]] && [[ ${TRACES_DISKS[$i]} != $METRICS_DRIVE ]]; then
            TRACES_DRIVE="${TRACES_DISKS[$i]}"
            TRACES_DISK="/dev/${TRACES_DISKS[$i]}"
            break
        fi
    done
fi

log-output "INFO: Data disk identified as $DATA_DISK for size $DATA_DISK_SIZE"
log-output "INFO: Metrics disk identified as $METRICS_DISK for size $METRICS_DISK_SIZE"
log-output "INFO: Traces disk identified as $TRACES_DISK for size $TRACES_DISK_SIZE"

if [[ $MOUNT_DISKS == true ]]; then
    # Partition the data disks
    log-output "INFO: Partitioning data disk $DATA_DISK"
    cat << EOF | fdisk $DATA_DISK
o
n
p
1


w
EOF

    log-output "INFO: Partitioning traces disk $TRACES_DISK"
    cat << EOF | fdisk $TRACES_DISK
o
n
p
1


w
EOF

    log-output "INFO: Partitioning metrics data disk $METRICS_DISK"
    cat << EOF | fdisk $METRICS_DISK
o
n
p
1


w
EOF

    # Format the disks
    log-output "INFO: Formatting data disk ${DATA_DISK}1"
    echo "y\n\n" | mkfs.xfs ${DATA_DISK}1

    log-output "INFO: Formatting traces disk ${TRACES_DISK}1"
    echo "y\n\n" | mkfs.xfs ${TRACES_DISK}1

    log-output "INFO: Formatting metrics disk ${METRICS_DISK}1"
    echo "y\n\n" | mkfs.xfs ${METRICS_DISK}1

    # Mount the disks
    log-output "INFO: Adding mount entries to fstab for data disk ${DATA_DISK}1 to /mnt/data"
    echo "${DATA_DISK}1                /mnt/data               xfs    rw,relatime,seclabel,attr2,inode64,logbufs=8,logbsize=32k,noquota   0 0" >> /etc/fstab

    log-output "INFO: Adding mount entries to fstab for traces disk ${TRACES_DISK}1 to /mnt/traces"
    echo "${TRACES_DISK}1                /mnt/traces               xfs    rw,relatime,seclabel,attr2,inode64,logbufs=8,logbsize=32k,noquota   0 0" >> /etc/fstab

    log-output "INFO: Adding mount entries to fstab for metrics disk ${METRICS_DISK}1 to /mnt/metrics"
    echo "${METRICS_DISK}1                /mnt/metrics               xfs    rw,relatime,seclabel,attr2,inode64,logbufs=8,logbsize=32k,noquota   0 0" >> /etc/fstab

    # Mount the disks
    log-output "INFO: Mounting all disks"
    systemctl daemon-reload
    mount -a
    if (( $? != 0 )); then
        log-output "ERROR: Unable to mount drives"
        exit 1
    else
        log-output "INFO: Successfully mounted drives"
    fi
else
    log-output "INFO: Skipping data disk partitioning and mounting"
fi

# Create the settings file
log-output "INFO: Creating Instana configuration"
TOKEN=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 12 ; echo '')

cat << EOF > /root/instana-settings.hcl
type                      = "single"
profile                   = "normal"
tenant                    = "${TENANT_NAME}"
unit                      = "${ENV_NAME}"
agent_key                 = "${DOWNLOAD_KEY}"
download_key              = "${DOWNLOAD_KEY}"
sales_key                 = "${SALES_KEY}"
host_name                 = "${FQDN}"
token_secret              = "${TOKEN}"

cert {
    crt  = "/root/instana.crt"
    key  = "/root/instana.key"
}

dir {
    metrics  = "/mnt/metrics"
    traces   = "/mnt/traces"
    data     = "/mnt/data"
    logs     = "/var/log/instana"
}

proxy {
  host     = ""
  port     = 0
  user     = ""
  password = ""
}

artifact_repository {
  repository_url = "https://artifact-public.instana.io/artifactory/rel-generic-instana-virtual/"
  user           = "_"
  password       = "${DOWNLOAD_KEY}"
}

email {

  smtp {
    from      = ""
    host      = ""
    port      = 0
    user      = ""
    password  = ""
    use_ssl   = false
    start_tls = false
  }

  ses {
    from            = ""
    aws_access_key  = ""
    aws_access_id   = ""
    aws_return_path = ""
    aws_region      = ""
  }
}

o_auth {
  client_id     = ""
  client_secret = ""
}

docker_repository {
  base_url = "artifact-public.instana.io"
  username = "_"
  password = "${DOWNLOAD_KEY}"
}

EOF

chmod 600 /root/instana-settings.hcl

# Install Instana
instana init -y -f /root/instana-settings.hcl
if (( $? != 0 )); then
    log-output "ERROR: Instana initialization was unsuccessful."
    exit 1
else
    log-output "INFO: Successfully initialized Instana"
fi

# Add the license
if [[ $LICENSE = "accept" ]]; then
    log-output "INFO: Applying license"

    instana license download
    if (( $? != 0 )); then
        log-output "ERROR: Unable to download license"
        exit 1
    else
        log-output "INFO: Successfully downloaded license"
    fi

    instana license import -f $(pwd)/license
    if (( $? !+ 0 )); then
        log-output "ERROR: Unable to apply license"
        exit 1
    else
        log-output "INFO: Successfully applied license"
    fi
else
    log-output "INFO: License not accepted. License not applied."
fi

# Set Instana administrator password
log-output "INFO: Setting Instana administrator password"
instana configure admin -p $INSTANA_PASSWORD
if (( $? != 0 )); then
    log-output "ERROR: Unable to update Instana administrator password"
    exit 1
else
    log-output "INFO: Instana administrator password set"
fi

# Install monitoring agent on the Instana VM host
if [[ $AGENT_TYPE == "docker" ]] && [[ $LICENSE == "accept" ]]; then 
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

    if (( $? != 0 )); then
        log-output "ERROR: Unable to run docker agent"
        exit 1
    else
        log-output "INFO: Successfully started docker agent"
    fi 

elif [[ $AGENT_TYPE = "host" ]] && [[ $LICENSE == "accept" ]]; then
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

    if (( $? != 0 )); then
        log-output "ERROR: Unable to setup host agent"
        exit 1
    else
        log-output "INFO: Successfully setup host agent"
    fi
else
    log-output "INFO: Unknown agent type $AGENT_TYPE or license not accepted. No agent installed."
fi

log-output "INFO: Deployment script completed"