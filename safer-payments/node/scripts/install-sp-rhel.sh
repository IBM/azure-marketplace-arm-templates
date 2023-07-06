#!/bin/bash

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
   echo "Usage: ${0} -i INSTANCE -p PARAMETERS [-a] [-m -k KEY] [-h]"
   echo "  options:"
   echo "  -i     the instance of node to deploy (1, 2, 3)"
   echo "  -p     install parameters in json format"
   echo "  -a     (optional) accept the Safer Payments license terms"
   echo "  -m     (optional) will attempt to mount CIFS drive with provided storage account, share name and key."
   echo "  -k     (optional) the Azure file storage access key."
   echo "  -h     Print this help"
   echo
}

log-output "INFO: Script started"

# Get the options
while getopts ":i:p:amsh" option; do
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
      i) # Instance of node to deploy
         INSTANCE=$OPTARG;;
      k) # Storage account key for mount
         KEY=$OPTARG;;
     \?) # Invalid option
         echo "Error: Invalid option"
         usage
         exit 1;;
   esac
done

# Parse parameters and check for readiness to proceed
if [[ -z $INSTANCE ]]; then 
    log-output "ERROR: Instance number not provided"
    exit 1
fi

if [[ -z $PARAMS ]]; then
    log-output "ERROR: No parameters provided"
    exit 1
fi

BINARY_URL=$(echo $PARAMS | jq -r '.binaryPath' )
RESOURCE_GROUP=$(echo $PARAMS | jq -r '.resourceGroup')

if [[ $INSTANCE = "1" ]]; then
    NODE1_NAME=$(echo $PARAMS | jq -r '.nodes[] | select(.instance == "1") | .vmName')
    NODE2_NAME=$(echo $PARAMS | jq -r '.nodes[] | select(.instance == "2") | .vmName')
    NODE3_NAME=$(echo $PARAMS | jq -r '.nodes[] | select(.instance == "3") | .vmName')
fi

if [[ $ACCEPT_LICENSE ]] && [[ -z $BINARY_URL ]]; then
    log-output "ERROR: License accepted but binary path not provided"
    exit 1
fi

# Set Defaults
if [[ -z $SCRIPT_DIR ]]; then export SCRIPT_DIR="$(pwd)"; fi
if [[ -z $BIN_FILE ]]; then export BIN_FILE="Safer_Payments_6.5_mp_ml.tar"; fi
export TIMESTAMP=$(date +"%y%m%d-%H%M%S")
if [[ -z $TMP_DIR ]]; then export TMP_DIR="tmp-$TIMESTAMP"; fi
if [[ -z $OUTPUT_DIR ]]; then export OUTPUT_DIR="${TMP_DIR}"; fi

log-output "INFO: Setting up node as $INSTANCE"

# Log parameters
log-output "INFO: Binary path is $BINARY_URL"
log-output "INFO: RESOURCE_GROUP is $RESOURCE_GROUP"

if [[ $INSTANCE = "1" ]]; then
    log-output "INFO: Node 1 Name is $NODE1_NAME"
    log-output "INFO: Node 2 Name is $NODE2_NAME"
    log-output "INFO: Node 3 Name is $NODE3_NAME"
fi

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
# Get configuration parameters

# IP Addresses
if [[ $INSTANCE = "1" ]]; then
    log-output "INFO: Getting VM IP Addresses"

    NODE1_IP=$(az vm list-ip-addresses -g $RESOURCE_GROUP -n $NODE1_NAME | jq -r '.[].virtualMachine.network.privateIpAddresses[0]' )
    log-output "INFO: Node 1 IP address is $NODE1_IP"

    NODE2_IP=$(az vm list-ip-addresses -g $RESOURCE_GROUP -n $NODE2_NAME | jq -r '.[].virtualMachine.network.privateIpAddresses[0]' )
    

    if [[ -z $NODE2_IP ]]; then 
        NODE2_IP="127.0.0.1"
        log-output "INFO: $NODE2_NAME not found. Setting Node 2 IP Address to $NODE2_IP"
    else
        log-output "INFO: Node 2 IP address is $NODE2_IP"
    fi

    NODE3_IP=$(az vm list-ip-addresses -g $RESOURCE_GROUP -n $NODE3_NAME | jq -r '.[].virtualMachine.network.privateIpAddresses[0]' )
    if [[ -z $NODE3_IP ]]; then 
        NODE3_IP="127.0.0.1"
        log-output "INFO: $NODE3_NAME not found. Setting Node 2 IP Address to $NODE3_IP"
    else
        log-output "INFO: Node 3 IP address is $NODE3_IP"
    fi
fi

#####
# Configure RHEL firewall

# Below uses the default firewall rules

if [[ $INSTANCE == "1" ]]; then
    sudo firewall-cmd --zone=public --add-port=8001/tcp --permanent
    sudo firewall-cmd --zone=public --add-port=27921/tcp --permanent
    sudo firewall-cmd --zone=public --add-port=27931/tcp --permanent
    sudo firewall-cmd --zone=public --add-port=27941/tcp --permanent
    sudo firewall-cmd --reload
elif [[ $INSTANCE == "2" ]]; then
    sudo firewall-cmd --zone=public --add-port=8002/tcp --permanent
    sudo firewall-cmd --zone=public --add-port=27922/tcp --permanent
    sudo firewall-cmd --zone=public --add-port=27932/tcp --permanent
    sudo firewall-cmd --zone=public --add-port=27942/tcp --permanent
    sudo firewall-cmd --reload
elif [[ $INSTANCE == "3" ]]; then
    sudo firewall-cmd --zone=public --add-port=8003/tcp --permanent
    sudo firewall-cmd --zone=public --add-port=27923/tcp --permanent
    sudo firewall-cmd --zone=public --add-port=27933/tcp --permanent
    sudo firewall-cmd --zone=public --add-port=27943/tcp --permanent
    sudo firewall-cmd --reload
else
    log-output "ERROR: Instance $INSTANCE not found"
    exit 1
fi

######
# Download and extract safer payments binary

if [[ $ACCEPT_LICENSE == "yes" ]]; then

    # Download the binary
    log-output "INFO: Downloading the Safer Payments binary"
    wget -O ${SCRIPT_DIR}/${BIN_FILE} "$BINARY_URL"

    # Extract the files
    log-output "INFO: Extracting the files from the binary"
    mkdir -p ${SCRIPT_DIR}/${TMP_DIR}
    tar xf ${SCRIPT_DIR}/${BIN_FILE} -C ${SCRIPT_DIR}/${TMP_DIR}

    # Get zip file and unzip
    zipFiles=( $( cd ${SCRIPT_DIR}/${TMP_DIR} && find SaferPayments*.zip ) )
    if (( ${#zipFiles[@]} > 0 )); then 
        cd ${SCRIPT_DIR}/${TMP_DIR} && unzip ./${zipFiles[0]}
    else
        log-output "ERROR: Safer Payments zip file not found in ${BIN_FILE}"
        exit 1
    fi

    #######
    # Setup the Java Runtime Environment

    log-output "INFO: Setting up the Java Runtime Environment"
    jreFiles=( $( cd ${SCRIPT_DIR}/${TMP_DIR} && find ibm_jre*.vm ) )
    if (( ${#jreFiles[@]} > 0 )); then
        cd ${SCRIPT_DIR}/${TMP_DIR} && unzip ./${jreFiles[0]}
    else
        log-output "ERROR: ibm_jre file not found"
        exit 1
    fi

    if [[ -f ${SCRIPT_DIR}/${TMP_DIR}/vm.tar.Z ]]; then
        tar xf vm.tar.Z
    else
        log-output "ERROR: vm.tar.z not found in binary file"
        exit 1
    fi

    chmod +x ${SCRIPT_DIR}/${TMP_DIR}/jre/bin/java
    chmod +x ${SCRIPT_DIR}/${TMP_DIR}/SaferPayments.bin

    #######
    # Run safer payments installation

    log-output "INFO: Installing Safer Payments"
    # Accept the license
    sed -i 's/LICENSE_ACCEPTED=FALSE/LICENSE_ACCEPTED=TRUE/g' ${SCRIPT_DIR}/${TMP_DIR}/installer.properties

    # Change install path to be under /usr
    sed -i 's/\/opt\//\/usr\//g' ${SCRIPT_DIR}/${TMP_DIR}/installer.properties

    sudo env "PATH=${SCRIPT_DIR}/${TMP_DIR}/jre/bin:$PATH" ${SCRIPT_DIR}/${TMP_DIR}/SaferPayments.bin -i silent

    # Create user and group to run safer payments
    sudo groupadd SPUserGroup
    sudo adduser SPUser -g SPUserGroup

    # Run safer payments postrequisites
    INSTALL_PATH=$(cat ${SCRIPT_DIR}/${TMP_DIR}/installer.properties | grep USER_INSTALL_DIR | awk '{split($0,value,"="); print value[2]}')
    sudo mkdir -p /instancePath
    sudo cp -R ${INSTALL_PATH}/factory_reset/* /instancePath 
    sudo chown -R SPUser:SPUserGroup /instancePath

    # Configure safer payments as a service

    log-output "INFO: Configuring initial instance $INSTANCE"
    cd /instancePath/cfg && sudo -u SPUser iris id=$INSTANCE createinstances=3 &
    # Allow time for service to start
    log-output "INFO: Sleeping for 2 minutes to let process finish"
    sleep 120
    log-output "INFO: Killing initial process"
    PROCESS_ID=$(/usr/bin/ps xua | grep -v grep | grep iris | grep -v sudo | awk '{print $2}') 
    sudo kill $PROCESS_ID
    # Allow time for service to shutdown
    log-output "INFO: Sleeping for 2 minutes to let shutdown complete"
    sleep 120

    log-output "INFO: Configuring cluster.iris"

    sudo cp /instancePath/cfg/cluster.iris ${SCRIPT_DIR}/${TMP_DIR}/default-cluster.iris
    
    sudo cat /instancePath/cfg/cluster.iris \
        | jq --arg IP $NODE1_IP '.configuration.irisInstances[0].interfaces[].address = $IP' \
        | jq --arg IP $NODE2_IP '.configuration.irisInstances[1].interfaces[].address = $IP' \
        | jq --arg IP $NODE3_IP '.configuration.irisInstances[2].interfaces[].address = $IP' > ${SCRIPT_DIR}/${TMP_DIR}/new-cluster.iris

    sudo cp ${SCRIPT_DIR}/${TMP_DIR}/new-cluster.iris /instancePath/cfg/cluster.iris

    sudo chown SPUser:SPUserGroup /instancePath/cfg/cluster.iris

    # Start instance
    # Change the below to a system process
    log-output "INFO: Starting Safer Payments process"
    cd /instancePath/cfg && sudo -u SPUser iris console id=${INSTANCE} &
else
    log-output "INFO: License not accepted. Safer Payments not installed"
fi