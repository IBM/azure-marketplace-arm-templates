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
   echo "Usage: ${0} -t TYPE [-m -s STORAGE_ACCOUNT -p SHARE -k KEY] [-h]"
   echo "  options:"
   echo "  -t     the type of node to deploy (primary, ha, dr, standby)"
   echo "  -m     (optional) will attempt to mount CIFS drive with provided storage account, share name and key."
   echo "  -s     (optional) the name of the Azure file share storage account"
   echo "  -p     (optional) the Azure file share name to mount"
   echo "  -k     (optional) the Azure file storage access key."
   echo "  -h     Print this help"
   echo
}

log-output "INFO: Script started"

# Get the options
while getopts ":t:ms:p:k:h" option; do
   case $option in
      h) # display Help
         usage
         exit 1;;
      m) # mount drive
         MOUNT_DRIVE="yes";;
      t) # Type of node to deploy
         TYPE=$OPTARG;;
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

log-output "INFO: Setting up node as $TYPE"

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

# Download safer payments binary

# Extract the files
# mkdir -p ${SCRIPT_DIR}/${TMP_DIR}
# tar xf ${SCRIPT_DIR}/${BIN_FILE} -C ${SCRIPT_DIR}/${TMP_DIR}

# Get zip file and unzip
# zipFiles=( $( cd ${SCRIPT_DIR}/${TMP_DIR} && find SaferPayments*.zip
# if (( ${#zipFiles[@]} > 0 )); then 
#   unzip ${SCRIPT_DIR}/${TMP_DIR}/${zipFiles[0]}
# else
#   log-output "ERROR: Safer Payments zip file not found in ${BIN_FILE}"
#    exit 1
# fi

# Setup the Java Runtime Environment

# jreFiles=( $( cd ${SCRIPT_DIR}/${TMP_DIR} && find ibm_jre*.vm ))
# if (( ${#jreFiles[@]} > 0 )); then
#   unzip ${SCRIPT_DIR}/${TMP_DIR}/${jreFiles[0]}
# else
#   log-output "ERROR: ibm_jre file not found"
#   exit 1
# fi
# tar xf vm.tar.Z
# chmod +x jre/bin/java
# chmod +x SaferPayments.bin

# Run safer payments installation
# Accept the license
# sed -i 's/LICENSE_ACCEPTED=FALSE/LICENSE_ACCEPTED=TRUE/g' installer.properties

# Change install path to be under /usr
# sed -i 's/\/opt\//\/usr\//g' installer.properties

# sudo env "PATH=$(pwd)/jre/bin:$PATH" ./SaferPayments.bin -i silent

# Create user and group to run safer payments
# sudo adduser 

# Run safer payments postrequisites
# cp -R /installationPath/factory_reset/* /instancePath 
# chown -R SPUser:SPUserGroup /instancePath

# Configure safer payments as a service

# On primary

# Write custom /instancePath/cfg/cluster.iris to primary node
# Copy instancePath/* to other nodes

# Shutdown node if standby
if [[ $TYPE = "standby" ]]; then
    log-output "INFO: Shutting down"
    sudo shutdown -h 0
fi