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
   echo "Usage: ${0} -i INSTANCE -b BINARY_URL -a [-m -s STORAGE_ACCOUNT -p SHARE -k KEY] [-h]"
   echo "  options:"
   echo "  -i     the instance of node to deploy (1, 2, 3)"
   echo "  -b     the URL to the safer payments binary"
   echo "  -a     accept the Safer Payments license terms"
   echo "  -m     (optional) will attempt to mount CIFS drive with provided storage account, share name and key."
   echo "  -s     (optional) the name of the Azure file share storage account"
   echo "  -p     (optional) the Azure file share name to mount"
   echo "  -k     (optional) the Azure file storage access key."
   echo "  -h     Print this help"
   echo
}

log-output "INFO: Script started"

# Get the options
while getopts ":i:b:ams:p:k:h" option; do
   case $option in
      h) # display Help
         usage
         exit 1;;
      b) # URL to binary
         BINARY=$OPTARG;;
      a) # Accept license   
         ACCEPT_LICENSE="yes";;
      m) # mount drive
         MOUNT_DRIVE="yes";;
      i) # Instance of node to deploy
         INSTANCE=$OPTARG;;
      s) # storage account for mount
         STORAGE_ACCOUNT=$OPTARG;;
      p) # Share name for mount
         SHARE=$OPTARG;;
      k) # Storage account key for mount
         KEY=$OPTARG;;
     \?) # Invalid option
         echo "Error: Invalid option"
         usage
         exit 1;;
   esac
done

# Set Defaults
if [[ -z $SCRIPT_DIR ]]; then export SCRIPT_DIR="$(pwd)"; fi
if [[ -z $BIN_FILE ]]; then export BIN_FILE="Safer_Payments_6.5_mp_ml.tar"; fi
export TIMESTAMP=$(date +"%y%m%d-%H%M%S")
if [[ -z $TMP_DIR ]]; then export TMP_DIR="tmp-$TIMESTAMP"; fi
if [[ -z $OUTPUT_DIR ]]; then export OUTPUT_DIR="${TMP_DIR}"; fi

log-output "INFO: Setting up node as $INSTANCE"

# Wait for cloud-init to finish
count=0
while [[ $(ps xua | grep cloud-init | grep -v grep) ]]; do
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
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
if [[ $(/usr/bin/cat /etc/redhat-release | grep "8.") ]]; then
    sudo dnf install -y https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm
elsif [[ $(/usr/bin/cat /etc/redhat-release | grep "9.") ]]; then
    sudo dnf install -y https://packages.microsoft.com/config/rhel/9.0/packages-microsoft-prod.rpm
else
    log-output "ERROR: RHEL version not supported"
    exit 1
fi
sudo dnf install azure-cli -y

#######
# Log into az cli with managed identity
if [[ -f "/usr/bin/az" ]]; then
    log-output "INFO: Logging into az cli"
    az login --identity
else
    log-output "ERROR: AZ CLI not properly installed"
    exit 1
fi

######
# Get configuration parameters
#
######################################

######
# Download and extract safer payments binary

if [[ $ACCEPT_LICENSE == "yes" ]]; then

    # Download the binary
    log-output "INFO: Downloading the Safer Payments binary"
    wget -O ${SCRIPT_DIR}/${BIN_FILE} $BIN_URL

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

    # On primary create custom cluster.iris
    if [[ $INSTANCE = "1" ]]; then
        log-output "INFO: Configuring initial instance $INSTANCE"
        cd /instancePath/cfg && sudo -u SPUser iris id=$INSTANCE createinstances=3 &
        # Allow time for service to start
        sleep 120
        PROCESS_ID=$(/usr/bin/ps xua | grep -v grep | grep iris | grep -v sudo | awk '{print $2}') 
        sudo kill $PROCESS_ID
        # Allow time for service to shutdown
        sleep 120

        log-output "INFO: Configuring cluster.iris"

        sudo -u SPUser cp /instancePath/cfg/cluster.iris /instancePath/cfg/default-cluster.iris
        
        sudo -u SPUser cat /instancePath/cfg/cluster.iris \
         | jq '.configuration.irisInstances[0].interfaces[].address = "10.0.0.4"' \
         | jq '.configuration.irisInstances[1].interfaces[].address = "10.0.0.5"' \
         | jq '.configuration.irisInstances[2].interfaces[].address = "10.0.0.6"' > ./new-cluster.iris

        sudo -u SPUser cp /instancePath/cfg/new-cluster.iris /instancePath/cfg/cluster.iris

    fi

    # Write custom /instancePath/cfg/cluster.iris to primary node


    # Copy instancePath/* to other nodes

    # Start instance
    cd /instancePath/cfg && sudo -u SPUser iris console id=${INSTANCE}
else
    log-output "INFO: License not accepted. Safer Payments not installed"
fi

# Shutdown node if standby
if [[ $TYPE = "4" ]]; then
    log-output "INFO: Shutting down"
    sudo shutdown -h 0
fi