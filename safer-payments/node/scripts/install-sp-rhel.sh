#!/bin/bash
###########################
#
# Script to install and configure a 3 node IBM Safer Payments cluster in Azure
# Should be run on the first node in the cluster. Will create the other nodes
# and configure for Safer Payments.
#
# Author: Rich Ehrhardt 
#
###########################

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
   echo "Sets a node for IBM Safer Payments."
   echo
   echo "Usage: ${0} -p PARAMETERS [-a] [-m -k KEY] [-h]"
   echo "  options:"
   echo "  -p     install parameters in json format"
   echo "  -a     (optional) accept the Safer Payments license terms"
   echo "  -m     (optional) will attempt to mount CIFS drive with provided storage account, share name and key."
   echo "  -k     (optional) the Azure file storage access key."
   echo "  -h     Print this help"
   echo
}

function remote-command() {
    LOCAL_USER=${1}
    REMOTE_USER=${2}
    REMOTE_IP=${3}
    REMOTE_COMMAND=${4}

    sudo -u $LOCAL_USER ssh $REMOTE_USER@$REMOTE_IP $REMOTE_COMMAND
}

function setup-remote-directory() {
    LOCAL_USER=${1}
    REMOTE_USER=${2}
    REMOTE_IP=${3}
    REMOTE_DIR=${4}

    sudo -u $LOCAL_USER ssh $REMOTE_USER@$REMOTE_IP << EOF >> /dev/null
sudo mkdir -p $REMOTE_DIR
sudo chown $REMOTE_USER:$REMOTE_USER $REMOTE_DIR
EOF
}

function stop-safer-payments() {
    NODE1=${1}
    NODE2=${2}
    NODE3=${3}
    LOCAL_USER=${4}
    REMOTE_USER=${5}

    declare -a nodes=("$NODE1" "$NODE2" "$NODE3")
    for node in "${nodes[@]}"; do
        log-output "INFO: Stopping safer payments on node $node"
        sudo -u $LOCAL_USER ssh $REMOTE_USER@$node 'sudo killall iris'
    done
}

function start-safer-payments() {
    NODE1=${1}
    NODE2=${2}
    NODE3=${3}
    LOCAL_USER=${4}
    REMOTE_USER=${5}

    log-output "INFO: Starting safer payments on node 1"
    sudo -u $LOCAL_USER ssh $ADMINUSER@$NODE1_IP 'cd /instancePath/cfg && sudo -u SPUser iris console id=1 & ' > /dev/null &

    log-output "INFO: Starting safer payments on node 2"
    sudo -u $LOCAL_USER ssh $ADMINUSER@$NODE2_IP 'cd /instancePath/cfg && sudo -u SPUser iris console id=2 & ' > /dev/null &

    log-output "INFO: Starting safer payments on node 3"
    sudo -u $LOCAL_USER ssh $ADMINUSER@$NODE3_IP 'cd /instancePath/cfg && sudo -u SPUser iris console id=3 & ' > /dev/null &    
}

function remote-install-safer-payments() {
    REMOTE_IP=${1}
    LOCAL_USER=${2}
    REMOTE_USER=${3}
    BIN_PATH=${4}
    BIN_FILE=${5}
    INSTANCE=${6}

    CONNECTION_PROPERTIES="$LOCAL_USER $REMOTE_USER $REMOTE_IP"

    # Wait for cloud-init to finish if new VM
    count=0
    while [[ $(remote-command $CONNECTION_PROPERTIES "/usr/bin/ps xua | grep cloud-init | grep -v grep") ]]; do
        log-output "INFO: Waiting for cloud init to finish. Waited $count minutes. Will wait 15 mintues."
        sleep 60
        count=$(( $count + 1 ))
        if (( $count > 15 )); then
            log-output "ERROR: Timeout waiting for cloud-init to finish"
            exit 1;
        fi
    done

    log-output "INFO: Extracting files on $REMOTE_IP"
    remote-command $CONNECTION_PROPERTIES "tar xf ${BIN_PATH}/${BIN_FILE} -C ${BIN_PATH}"

    zipFiles=( $(remote-command $CONNECTION_PROPERTIES "cd ${BIN_PATH} && find SaferPayments*.zip") )
    if (( ${#zipFiles[@]} > 0 )); then 
        remote-command $CONNECTION_PROPERTIES "cd ${BIN_PATH} && unzip ./${zipFiles[0]}"
    else
        log-output "ERROR: Safer Payments zip file not found in ${BIN_FILE} on ${REMOTE_IP}"
        exit 1
    fi

    # Setup java runtime environment
    log-output "INFO: Setting up Java Runtime Environment on $REMOTE_IP"
    jreFiles=( $( remote-command $CONNECTION_PROPERTIES "cd ${BIN_PATH} && find ibm_jre*.vm" ) )
    if (( ${#jreFiles[@]} > 0 )); then
        remote-command $CONNECTION_PROPERTIES "cd ${BIN_PATH} && unzip ./${jreFiles[0]}"
    else
        log-output "ERROR: ibm_jre file not found in $BIN_FILE on $REMOTE_IP"
        exit 1
    fi

    if [[ $(remote-command $CONNECTION_PROPERTIES "ls ${BIN_PATH}/vm.tar.Z") ]]; then
        remote-command $CONNECTION_PROPERTIES "cd ${BIN_PATH} && tar xf vm.tar.Z"
    else
        log-output "ERROR: vm.tar.z not found in binary file on $REMOTE_IP"
        exit 1
    fi

    remote-command $CONNECTION_PROPERTIES "chmod +x ${BIN_PATH}/jre/bin/java"
    remote-command $CONNECTION_PROPERTIES "chmod +x ${BIN_PATH}/SaferPayments.bin"

    log-output "Installing Safer Payments on $REMOTE_IP"

    # Accept the license
    remote-command $CONNECTION_PROPERTIES "sed -i 's/LICENSE_ACCEPTED=FALSE/LICENSE_ACCEPTED=TRUE/g' ${BIN_PATH}/installer.properties"

    # Change installer path to be under /var (not enough space under default /opt)
    remote-command $CONNECTION_PROPERTIES "sed -i 's/\/opt\//\/usr\//g' ${BIN_PATH}/installer.properties"

    # Run Safer Payments installer
    remote-command $CONNECTION_PROPERTIES "sudo env \"PATH=${BIN_PATH}/jre/bin:$PATH\" ${BIN_PATH}/SaferPayments.bin -i silent"

    # Create user and group to run safer payments
    remote-command $CONNECTION_PROPERTIES "sudo groupadd SPUserGroup"
    remote-command $CONNECTION_PROPERTIES "sudo adduser SPUser -g SPUserGroup"

    # Configure initial instance
    log-output "INFO: Creating default Safer Payments instance configuration on $REMOTE_IP"
    INSTALL_PROPERTIES=( $(remote-command $CONNECTION_PROPERTIES "cat ${BIN_PATH}/installer.properties") )

    for line in ${INSTALL_PROPERTIES[@]}; do
        if [[ $( echo $line | grep USER_INSTALL_DIR ) ]]; then
            INSTALL_PATH=$(echo $line | grep USER_INSTALL_DIR | awk '{split($0,value,"="); print value[2]}' )
        fi
    done

    if [[ -z $INSTALL_PATH ]]; then
        log-output "ERROR: Install path not found in installer-properties on $REMOTE_IP"
        exit 1
    fi
    remote-command $CONNECTION_PROPERTIES "sudo mkdir -p /instancePath"
    remote-command $CONNECTION_PROPERTIES "sudo cp -R ${INSTALL_PATH}/factory_reset/* /instancePath "
    remote-command $CONNECTION_PROPERTIES "sudo chown -R SPUser:SPUserGroup /instancePath"

    log-output "INFO: Configuring initial instance $INSTANCE on $REMOTE_IP"
    remote-command $CONNECTION_PROPERTIES "cd /instancePath/cfg && sudo -u SPUser iris id=$INSTANCE createinstances=3 &" &
    log-output "INFO: Sleeping for 2 minutes to let process finish"
    sleep 120
    log-output "INFO: Killing initial process on $REMOTE_IP"
    remote-command $CONNECTION_PROPERTIES "sudo killall iris"
    log-output "INFO: Sleeping for 2 minutes to let shutdown complete"
    sleep 120 

    # Configure RHEL firewall

    API_PORT=$(( 8001 ))
    FLI_PORT=$(( 27921 + ( $INSTANCE - 1 ) ))
    STAT_PORT=$(( 27931 + ( $INSTANCE - 1 ) ))
    ECI_PORT=$(( 27941 + ( $INSTANCE - 1 ) ))

    declare -a PORTS=( "$API_PORT" "$FLI_PORT" "$STAT_PORT" "$ECI_PORT" )
    for port in ${PORTS[@]}; do
        remote-command $CONNECTION_PROPERTIES "sudo firewall-cmd --zone=public --add-port=${port}/tcp --permanent"
    done
    remote-command $CONNECTION_PROPERTIES "sudo firewall-cmd --reload"
}

log-output "INFO: Script started"

# Get the options
while getopts ":p:amsh" option; do
   case $option in
      h) # display Help
         usage
         exit 1;;
      p) # install parameters
         PARAMS=$OPTARG;;
      a) # Accept license   
         ACCEPT_LICENSE="yes";;
      m) # mount drive
         MOUNT_DRIVE="yes";;
      k) # Storage account key for mount
         KEY=$OPTARG;;
     \?) # Invalid option
         echo "Error: Invalid option"
         usage
         exit 1;;
   esac
done

# Parse parameters and check for readiness to proceed
if [[ -z $PARAMS ]]; then
    log-output "ERROR: No parameters provided"
    exit 1
fi

BINARY_URL=$(echo $PARAMS | jq -r '.binaryPath' )
RESOURCE_GROUP=$(echo $PARAMS | jq -r '.resourceGroup')
LOCATION=$(echo $PARAMS | jq -r '.location')
VAULT_NAME=$(echo $PARAMS | jq -r '.vaultName')
KEY_NAME=$(echo $PARAMS | jq -r '.keyName')
ADMINUSER=$(echo $PARAMS | jq -r '.adminUser')

NODE1_NAME=$(echo $PARAMS | jq -r '.nodes.node1.vmName')
NODE2_NAME=$(echo $PARAMS | jq -r '.nodes.node2.vmName')
NODE3_NAME=$(echo $PARAMS | jq -r '.nodes.node3.vmName')
NODE1_ZONE=$(echo $PARAMS | jq -r '.nodes.node1.zone')
NODE2_ZONE=$(echo $PARAMS | jq -r '.nodes.node2.zone')
NODE3_ZONE=$(echo $PARAMS | jq -r '.nodes.node3.zone')
NODE1_VMSIZE=$(echo $PARAMS | jq -r '.nodes.node1.vmSize')
NODE2_VMSIZE=$(echo $PARAMS | jq -r '.nodes.node2.vmSize')
NODE3_VMSIZE=$(echo $PARAMS | jq -r '.nodes.node3.vmSize')
NODE1_STORAGESKU=$(echo $PARAMS | jq -r '.nodes.node1.storageSKU')
NODE2_STORAGESKU=$(echo $PARAMS | jq -r '.nodes.node2.storageSKU')
NODE3_STORAGESKU=$(echo $PARAMS | jq -r '.nodes.node3.storageSKU')
NODE1_IMAGEURN="$(echo $PARAMS | jq -r '.nodes.node1.imageURN')"
NODE2_IMAGEURN="$(echo $PARAMS | jq -r '.nodes.node2.imageURN')"
NODE3_IMAGEURN="$(echo $PARAMS | jq -r '.nodes.node3.imageURN')"
NODE1_PUBLICIP=$(echo $PARAMS | jq -r '.nodes.node1.publicIP')
NODE2_PUBLICIP=$(echo $PARAMS | jq -r '.nodes.node2.publicIP')
NODE3_PUBLICIP=$(echo $PARAMS | jq -r '.nodes.node3.publicIP')
VNET_NAME=$(echo $PARAMS | jq -r '.vnetName')
SUBNET_NAME=$(echo $PARAMS | jq -r '.subnetName')
NSG_ID=$(echo $PARAMS | jq -r '.nsgID')

if [[ $ACCEPT_LICENSE ]] && [[ -z $BINARY_URL ]]; then
    log-output "ERROR: License accepted but binary path not provided"
    exit 1
fi

# Set Defaults
if [[ -z $SCRIPT_DIR ]]; then export SCRIPT_DIR="/tmp"; fi
if [[ -z $BIN_FILE ]]; then export BIN_FILE="Safer_Payments_6.5_mp_ml.tar"; fi
export TIMESTAMP=$(date +"%y%m%d-%H%M%S")
if [[ -z $TMP_DIR ]]; then export TMP_DIR="sp-install-$TIMESTAMP"; fi
if [[ -z $OUTPUT_DIR ]]; then export OUTPUT_DIR="${TMP_DIR}"; fi

log-output "INFO: Setting up node as $INSTANCE"

# Log parameters
log-output "INFO: Binary path is $BINARY_URL"
log-output "INFO: Resource group is $RESOURCE_GROUP"
log-output "INFO: Location is $LOCATION"
log-output "INFO: KeyVault name is $VAULT_NAME"
log-output "INFO: SSH Key name is $KEY_NAME"
log-output "INFO: Admin user is $ADMINUSER"
log-output "INFO: Node 1 Name is $NODE1_NAME"
log-output "INFO: Node 2 Name is $NODE2_NAME"
log-output "INFO: Node 3 Name is $NODE3_NAME"
log-output "INFO: Node 1 Zone is $NODE1_ZONE"
log-output "INFO: Node 2 Zone is $NODE2_ZONE"
log-output "INFO: Node 3 Zone is $NODE3_ZONE"
log-output "INFO: Node 1 VM Size is $NODE1_VMSIZE"
log-output "INFO: Node 2 VM Size is $NODE2_VMSIZE"
log-output "INFO: Node 3 VM Size is $NODE3_VMSIZE"
log-output "INFO: Node 1 Storage SKU is $NODE1_STORAGESKU"
log-output "INFO: Node 2 Storage SKU is $NODE2_STORAGESKU"
log-output "INFO: Node 3 Storage SKU is $NODE3_STORAGESKU"
log-output "INFO: Node 1 Image URN is $NODE1_IMAGEURN"
log-output "INFO: Node 2 Image URN is $NODE2_IMAGEURN"
log-output "INFO: Node 3 Image URN is $NODE3_IMAGEURN"
log-output "INFO: Node 1 create public IP is $NODE1_PUBLICIP"
log-output "INFO: Node 2 create public IP is $NODE2_PUBLICIP"
log-output "INFO: Node 3 create public IP is $NODE3_PUBLICIP"
log-output "INFO: Virtual network is $VNET_NAME"
log-output "INFO: Subnet is $SUBNET_NAME"
log-output "INFO: Network security group is $NSG_ID"

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

# Updating OS
sudo yum -y update

# Mount drive if required
if [[ $MOUNT_DRIVE == "yes" ]]; then
    log-output "INFO: Setting up drive mount"

    STORAGE_ACCOUNT=$(echo $PARAMS | jq -r '.mountDetails.storageAccount')
    SHARE=$(echo $PARAMS | jq -r '.mountDetails.shareName')

    if [[ -z $STORAGE_ACCOUNT ]] || [[ -z $SHARE ]] || [[ -z $KEY ]]; then
        log-output "ERROR: Missing parameters for setting up mount"
        log-output "INFO: STORAGE_ACCOUNT = $STORAGE_ACCOUNT"
        log-output "INFO: SHARE = $SHARE"
        log-output "INFO: KEY = $KEY"
        exit 1
    fi

    sudo yum install -y keyutils cifs-utils

    sudo mkdir -p /mnt/${SHARE}

    if [[ ! -d "/etc/smbcredentials" ]]; then
        sudo mkdir /etc/smbcredentials
    fi

    if [[ ! -f "/etc/smbcredentials/${STORAGE_ACCOUNT}.cred" ]]; then
        log-output "INFO: Setting up credentials for drive"
        sudo touch /etc/smbcredentials/${STORAGE_ACCOUNT}.cred
        sudo chmod 600 /etc/smbcredentials/${STORAGE_ACCOUNT}.cred
        echo "username=${STORAGE_ACCOUNT}" | sudo tee -a /etc/smbcredentials/${STORAGE_ACCOUNT}.cred > /dev/null
        echo "password=${KEY}" | sudo tee -a /etc/smbcredentials/${STORAGE_ACCOUNT}.cred > /dev/null
    fi

    if [[ ! $(cat /etc/fstab | grep "${STORAGE_ACCOUNT}.file.core.windows.net/${SHARE}" ) ]]; then
        echo "//${STORAGE_ACCOUNT}.file.core.windows.net/${SHARE} /mnt/${SHARE} cifs nofail,credentials=/etc/smbcredentials/${STORAGE_ACCOUNT}.cred,dir_mode=0777,file_mode=0777,serverino,nosharesock,actimeo=30" | sudo tee -a /etc/fstab > /dev/null
    else
        log-output "INFO: Drive already defined in fstab"
    fi

    if [[ ! $(mount | grep "${STORAGE_ACCOUNT}.file.core.windows.net/${SHARE}" ) ]]; then
        log-output "INFO: Mounting $SHARE from ${STORAGE_ACCOUNT}"
        sudo mount -a | log-output
    else
        log-output "INFO: Drive already mounted"
    fi
fi

######
# Install the az cli
if [[ ! $(/usr/bin/which az 2> /dev/null) ]]; then
    log-output "INFO: Installing Azure CLI tools"
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    if [[ $(/usr/bin/cat /etc/redhat-release | grep "8.") ]]; then
        sudo dnf install -y https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm
    elif [[ $(/usr/bin/cat /etc/redhat-release | grep "9.") ]]; then
        sudo dnf install -y https://packages.microsoft.com/config/rhel/9.0/packages-microsoft-prod.rpm
    else
        log-output "ERROR: RHEL version not supported"
        exit 1
    fi
    sudo dnf install azure-cli -y
else 
    log-output "INFO: Azure CLI tools already installed"
fi

#######
# Log into az cli with managed identity
if [[ $(/usr/bin/which az 2> /dev/null) ]]; then
    if [[ -z $(az account show) ]]; then
        log-output "INFO: Logging into az cli"
        az login --identity
    else
        log-output "INFO: Already logged into Azure CLI"
    fi
else
    log-output "ERROR: AZ CLI not properly installed"
    exit 1
fi

######
# Create ssh key pair
if [[ ! -f "/home/$ADMINUSER/.ssh/id_rsa.pub" ]]; then
    log-output "INFO: Generating a new ssh key pair"
    sudo -u $ADMINUSER /usr/bin/ssh-keygen -t rsa -b 4096 -f /home/$ADMINUSER/.ssh/id_rsa -q -N ""
else
    log-output "INFO: Key pair already exists"
fi

if [[ -z $(az sshkey list --resource-group $RESOURCE_GROUP -o table | grep $KEY_NAME) ]]; then
    log-output "INFO: Uploading public key $KEY_NAME to Azure"
    az sshkey create --name "$KEY_NAME" --resource-group "$RESOURCE_GROUP" --public-key "@/home/$ADMINUSER/.ssh/id_rsa.pub"
else
    log-output "INFO: Public key already exists in resource group"
fi

######
# Upload keypair to vault
if [[ -z $(az keyvault secret list --vault-name $VAULT_NAME -o table | grep ${KEY_NAME}-private ) ]]; then
    log-output "INFO: Uploading private key ${KEY_NAME}-private to key vault $VAULT_NAME"
    az keyvault secret set --name "${KEY_NAME}-private" --vault-name $VAULT_NAME --file "/home/$ADMINUSER/.ssh/id_rsa"
else
    log-output "INFO: Private key ${KEY_NAME}-private already exists in key vault $VAULT_NAME"
fi

#######
# Copy ssh key to local VM
if [[ -z $(sudo -u $ADMINUSER cat /home/$ADMINUSER/.ssh/authorized_keys | grep "$(cat /home/$ADMINUSER/.ssh/id_rsa.pub)") ]]; then
    log-output "INFO: Adding new public key to local authorized keys"
    sudo -u $ADMINUSER cat /home/$ADMINUSER/.ssh/id_rsa.pub >> /home/$ADMINUSER/.ssh/authorized_keys
else
    log-output "INFO: Local authorized keys already contains public key"
fi

######
# Create the virtual machines

# Node 1
if [[ -z $(az vm list --resource-group $RESOURCE_GROUP -o table | grep $NODE1_NAME ) ]]; then
    log-output "INFO: Creating virtual machine $NODE1_NAME in resource group $RESOURCE_GROUP"
    if [[ ${NODE1_PUBLICIP} == "yes" ]]; then 
        az vm create --name $NODE1_NAME \
            --resource-group $RESOURCE_GROUP \
            --authentication-type ssh \
            --location $LOCATION \
            --ssh-key-value /home/$ADMINUSER/.ssh/id_rsa.pub \
            --admin-username $ADMINUSER \
            --encryption-at-host true \
            --size "${NODE1_VMSIZE}" \
            --vnet-name "${VNET_NAME}" \
            --subnet "${SUBNET_NAME}" \
            --nsg "${NSG_ID}" \
            --storage-sku "${NODE1_STORAGESKU}" \
            --image "${NODE1_IMAGEURN}" \
            --zone "${NODE1_ZONE}" 
    else
        az vm create --name $NODE1_NAME \
            --resource-group $RESOURCE_GROUP \
            --authentication-type ssh \
            --location $LOCATION \
            --ssh-key-value /home/$ADMINUSER/.ssh/id_rsa.pub \
            --admin-username $ADMINUSER \
            --encryption-at-host true \
            --size "${NODE1_VMSIZE}" \
            --vnet-name "${VNET_NAME}" \
            --subnet "${SUBNET_NAME}" \
            --nsg "${NSG_ID}" \
            --storage-sku "${NODE1_STORAGESKU}" \
            --image "${NODE1_IMAGEURN}" \
            --zone "${NODE1_ZONE}" \
            --public-ip-address ""
    fi
else
    log-output "INFO: Virtual Machine $NODE1_NAME already exists in resource group $RESOURCE_GROUP"
fi

# Node 2
if [[ -z $(az vm list --resource-group $RESOURCE_GROUP -o table | grep $NODE2_NAME ) ]]; then
    log-output "INFO: Creating virtual machine $NODE2_NAME in resource group $RESOURCE_GROUP"
    if [[ ${NODE2_PUBLICIP} == "yes" ]]; then 
        az vm create --name $NODE2_NAME \
            --resource-group $RESOURCE_GROUP \
            --authentication-type ssh \
            --location $LOCATION \
            --ssh-key-value /home/$ADMINUSER/.ssh/id_rsa.pub \
            --admin-username $ADMINUSER \
            --encryption-at-host true \
            --size "${NODE2_VMSIZE}" \
            --vnet-name "${VNET_NAME}" \
            --subnet "${SUBNET_NAME}" \
            --nsg "${NSG_ID}" \
            --storage-sku "${NODE2_STORAGESKU}" \
            --image "${NODE2_IMAGEURN}" \
            --zone "${NODE2_ZONE}" 
    else
        az vm create --name $NODE2_NAME \
            --resource-group $RESOURCE_GROUP \
            --authentication-type ssh \
            --location $LOCATION \
            --ssh-key-value /home/$ADMINUSER/.ssh/id_rsa.pub \
            --admin-username $ADMINUSER \
            --encryption-at-host true \
            --size "${NODE2_VMSIZE}" \
            --vnet-name "${VNET_NAME}" \
            --subnet "${SUBNET_NAME}" \
            --nsg "${NSG_ID}" \
            --storage-sku "${NODE2_STORAGESKU}" \
            --image "${NODE2_IMAGEURN}" \
            --zone "${NODE2_ZONE}" \
            --public-ip-address ""
    fi
else
    log-output "INFO: Virtual Machine $NODE2_NAME already exists in resource group $RESOURCE_GROUP"
fi

# Node 3
if [[ -z $(az vm list --resource-group $RESOURCE_GROUP -o table | grep $NODE3_NAME ) ]]; then
    log-output "INFO: Creating virtual machine $NODE3_NAME in resource group $RESOURCE_GROUP"
    if [[ ${NODE3_PUBLICIP} == "yes" ]]; then
        az vm create --name $NODE3_NAME \
            --resource-group $RESOURCE_GROUP \
            --authentication-type ssh \
            --location $LOCATION \
            --ssh-key-value /home/$ADMINUSER/.ssh/id_rsa.pub \
            --admin-username $ADMINUSER \
            --encryption-at-host true \
            --size "${NODE3_VMSIZE}" \
            --vnet-name "${VNET_NAME}" \
            --subnet "${SUBNET_NAME}" \
            --nsg "${NSG_ID}" \
            --storage-sku "${NODE3_STORAGESKU}" \
            --image "${NODE3_IMAGEURN}" \
            --zone "${NODE3_ZONE}" 
    else
        az vm create --name $NODE3_NAME \
            --resource-group $RESOURCE_GROUP \
            --authentication-type ssh \
            --location $LOCATION \
            --ssh-key-value /home/$ADMINUSER/.ssh/id_rsa.pub \
            --admin-username $ADMINUSER \
            --encryption-at-host true \
            --size "${NODE3_VMSIZE}" \
            --vnet-name "${VNET_NAME}" \
            --subnet "${SUBNET_NAME}" \
            --nsg "${NSG_ID}" \
            --storage-sku "${NODE3_STORAGESKU}" \
            --image "${NODE3_IMAGEURN}" \
            --zone "${NODE3_ZONE}" \
            --public-ip-address ""
    fi
else
    log-output "INFO: Virtual Machine $NODE3_NAME already exists in resource group $RESOURCE_GROUP"
fi

######
# Get configuration parameters

# IP Addresses
log-output "INFO: Getting VM IP Addresses"

NODE1_IP=$(az vm list-ip-addresses -g $RESOURCE_GROUP -n $NODE1_NAME | jq -r '.[].virtualMachine.network.privateIpAddresses[0]' )
if [[ -z $NODE1_IP ]]; then
    log-output "ERROR: No IP Address found for $NODE1_NAME"
    exit 1
else
    log-output "INFO: $NODE1_NAME IP address is $NODE1_IP"
fi

NODE2_IP=$(az vm list-ip-addresses -g $RESOURCE_GROUP -n $NODE2_NAME | jq -r '.[].virtualMachine.network.privateIpAddresses[0]' )
if [[ -z $NODE2_IP ]]; then
    log-output "ERROR: No IP Address found for $NODE2_NAME"
    exit 1
else
    log-output "INFO: $NODE2_NAME IP address is $NODE2_IP"
fi

NODE3_IP=$(az vm list-ip-addresses -g $RESOURCE_GROUP -n $NODE3_NAME | jq -r '.[].virtualMachine.network.privateIpAddresses[0]' )
if [[ -z $NODE3_IP ]]; then
    log-output "ERROR No IP Address found for $NODE3_NAME"
    exit 1
else
    log-output "INFO: $NODE3_NAME IP address is $NODE3_IP"
fi

# Log in to each node to add to known hosts
declare -a NODE_IPS=( "$NODE1_IP" "$NODE2_IP" "$NODE3_IP" )
if [[ ! -f /home/$ADMINUSER/.ssh/known_hosts ]]; then
    sudo -u $ADMINUSER /usr/bin/touch /home/$ADMINUSER/.ssh/known_hosts
fi
for node_ip in ${NODE_IPS[@]}; do
    if [[ -z $(sudo -u $ADMINUSER cat /home/$ADMINUSER/.ssh/known_hosts | grep $node_ip ) ]]; then
        log-output "INFO: Adding $node_ip to list of known hosts"
        ssh -o StrictHostKeyChecking=no $ADMINUSER@$node_ip "ls -lha" > /dev/null 2>&1
    else
        log-output "INFO: $node_ip already in list of known hosts"
    fi
done

if [[ $ACCEPT_LICENSE == "yes" ]]; then

    ######
    # Extract and confirm binaries
   
    # Download the binary
    if [[ ! -f ${SCRIPT_DIR}/${BIN_FILE} ]]; then
        log-output "INFO: Downloading the Safer Payments binary"
        wget -O ${SCRIPT_DIR}/${BIN_FILE} "$BINARY_URL"
    else
        log-output "INFO: Binary already downloaded"
    fi

    ####### Setup nodes

    # Create temporary directories
    setup-remote-directory $ADMINUSER $ADMINUSER $NODE1_IP /tmp/iris
    setup-remote-directory $ADMINUSER $ADMINUSER $NODE2_IP /tmp/iris
    setup-remote-directory $ADMINUSER $ADMINUSER $NODE3_IP /tmp/iris

    # Install safer payments on each node
    if [[ -z $(sudo -u $ADMINUSER ssh $ADMINUSER@$NODE1_IP "/usr/bin/which iris" 2> /dev/null) ]]; then
        log-output "INFO: Copying Safer Payments binary to $NODE1_NAME"
        sudo -u $ADMINUSER scp ${SCRIPT_DIR}/${BIN_FILE} $ADMINUSER@$NODE1_IP:/tmp/iris
        log-output "INFO: Installing Safer Payments on $NODE1_NAME"
        remote-install-safer-payments $NODE1_IP $ADMINUSER $ADMINUSER /tmp/iris $BIN_FILE 1
    else
        log-output "INFO: Safer Payments already installed on $NODE1_NAME"
    fi

    if [[ -z $(sudo -u $ADMINUSER ssh $ADMINUSER@$NODE2_IP "/usr/bin/which iris" 2> /dev/null) ]]; then
        log-output "INFO: Copying Safer Payments binary to $NODE2_NAME"
        sudo -u $ADMINUSER scp ${SCRIPT_DIR}/${BIN_FILE} $ADMINUSER@$NODE2_IP:/tmp/iris
        log-output "INFO: Installing Safer Payments on $NODE2_NAME"
        remote-install-safer-payments $NODE2_IP $ADMINUSER $ADMINUSER /tmp/iris $BIN_FILE 2
    else
        log-output "INFO: Safer Payments already installed on $NODE2_NAME"
    fi

    if [[ -z $(sudo -u $ADMINUSER ssh $ADMINUSER@$NODE3_IP "/usr/bin/which iris" 2> /dev/null) ]]; then    
        log-output "INFO: Copying Safer Payments binary to $NODE3_NAME"
        sudo -u $ADMINUSER scp ${SCRIPT_DIR}/${BIN_FILE} $ADMINUSER@$NODE3_IP:/tmp/iris
        log-output "INFO: Installing Safer Payments on $NODE3_NAME"
        remote-install-safer-payments $NODE3_IP $ADMINUSER $ADMINUSER /tmp/iris $BIN_FILE 3
    else
        log-output "INFO: Safer Payments already installed on $NODE3_NAME"
    fi

    # Create configuration

    log-output "INFO: Configuring cluster.iris"

    scp $ADMINUSER@$NODE1_IP:/instancePath/cfg/cluster.iris ${SCRIPT_DIR}/default-cluster.iris
    
    cat ${SCRIPT_DIR}/default-cluster.iris \
        | jq --arg IP $NODE1_IP '.configuration.irisInstances[0].interfaces[].address = $IP' \
        | jq --arg IP $NODE2_IP '.configuration.irisInstances[1].interfaces[].address = $IP' \
        | jq --arg IP $NODE3_IP '.configuration.irisInstances[2].interfaces[].address = $IP' \
        | sed 's/8002/8002/g' \
        | sed 's/8003/8003/g' > ${SCRIPT_DIR}/new-cluster.iris

    scp ${SCRIPT_DIR}/new-cluster.iris $ADMINUSER@$NODE1_IP:/tmp/iris
    remote-command $ADMINUSER $ADMINUSER $NODE1_IP "sudo cp /tmp/iris/new-cluster.iris /instancePath/cfg/cluster.iris"
    remote-command $ADMINUSER $ADMINUSER $NODE1_IP "sudo chown SPUser:SPUserGroup /instancePath/cfg/cluster.iris"

    log-output "INFO: Copying node1 configuration to local"
    scp $ADMINUSER@$NODE1_IP:/instancePath/cfg/cluster.iris ${SCRIPT_DIR} > /dev/null 2>&1
    scp $ADMINUSER@$NODE1_IP:/instancePath/cfg/settings.iris ${SCRIPT_DIR} > /dev/null 2>&1
    scp $ADMINUSER@$NODE1_IP:/instancePath/cfg/inbound* ${SCRIPT_DIR} > /dev/null 2>&1

    # Copy configuration to remote nodes
    declare -a NODES=( "$NODE2_IP" "$NODE3_IP" )
    for node in ${NODES[@]}; do
        CONNECTION_PROPERTIES="$ADMINUSER $ADMINUSER $node"
        log-output "INFO: Copying node 1 configuration from local to node at $node" 
        
        scp ${SCRIPT_DIR}/cluster.iris $ADMINUSER@$node:/tmp/iris > /dev/null 2>&1
        scp ${SCRIPT_DIR}/settings.iris $ADMINUSER@$node:/tmp/iris > /dev/null 2>&1
        scp ${SCRIPT_DIR}/inbound* $ADMINUSER@$node:/tmp/iris > /dev/null 2>&1

        remote-command $CONNECTION_PROPERTIES "sudo cp /tmp/iris/cluster.iris /instancePath/cfg/" > /dev/null 2>&1
        remote-command $CONNECTION_PROPERTIES "sudo cp /tmp/iris/settings.iris /instancePath/cfg/" > /dev/null 2>&1
        remote-command $CONNECTION_PROPERTIES "sudo cp /tmp/iris/inbound* /instancePath/cfg/" > /dev/null 2>&1
        remote-command $CONNECTION_PROPERTIES "sudo rm /instancePath/fli/*" > /dev/null 2>&1
    done

    # Start services
    start-safer-payments $NODE1_IP $NODE2_IP $NODE3_IP $ADMINUSER $ADMINUSER

else
    log-output "INFO: License not accepted. Safer Payments not installed"
fi