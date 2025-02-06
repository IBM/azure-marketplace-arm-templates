#!/bin/bash
#
# Script to deploy webMethods on a virtual machine
#
# NOTE: The script needs to run as root (this is the default behaviour with the Azure CLI custom script extension)

function log-output() {
    MSG=${1}

    if [[ -z $OUTPUT_DIR ]]; then
        OUTPUT_DIR="/mnt/azscripts/azscriptoutput"
    fi
    mkdir -p $OUTPUT_DIR

    if [[ -z $OUTPUT_FILE ]]; then
        OUTPUT_FILE="script-output.log"
    fi

    echo "$(date -u +"%Y-%m-%d %T") ${MSG}" >> ${OUTPUT_DIR}/${OUTPUT_FILE}
    echo ${MSG}
}

function log-info() {
    MSG=${1}

    log-output "INFO: $MSG"
}

function log-error() {
    MSG=${1}

    log-output "ERROR: $MSG"
    echo $MSG >&2
}

function install-xrdp() {
    # Usage install-xrdp $rdp_password

    if [[ !${1} ]]; then
        log-error "No password provided for XRDP configuration. Continuing."
    else
        local RDP_PASSWORD=${1}
    fi

    # Update the system
    log-info "Updating the system's packages"
    yum update -y
    if [[ $? != 0 ]]; then
        log-error "Unable to update system packages. Continuing"
    fi

    # Install remote GUI package
    log-info "Configuring remote GUI package"
    sudo dnf -y group install "Server with GUI"
    if [[ $? != 0 ]]; then
        log-error "Unable to configure the remote GUI package"
        exit 1
    fi

    # Install the additional package addon for RHEL
    log-info "Installing the additional packages addon for RHEL"
    dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
    dnf makecache
    if [[ $? != 0 ]]; then
        log-error "Unable to install the addon packages required for XRDP"
        exit 1
    fi

    # Install XRDP
    log-info "Installing XRDP"
    dnf install -y xrdp
    if [[ $? != 0 ]]; then
        log-error "Unable to install XRDP"
        exit 1
    fi

    # Enable and start the XRDP service
    log-info "Enabling the XRDP service"
    systemctl enable xrdp
    if [[ $? != 0 ]]; then
        log-error "Unable to enable the XRDP service"
        exit 1
    fi

    log-info "Starting the XRDP service"
    systemctl start xrdp
    if [[ $? != 0 ]]; then
        log-error "Unable to start the XRDP service"
        exit 1
    fi

    # Open the firewall ports for RDP
    log-info "Opening RDP ports"
    firewall-cmd --permanent --add-port=3389/tcp
    if [[ $? != 0 ]]; then
        log-error "Unable to open firewall port for RDP. Continuing"
    fi

    firewall-cmd --reload
    if [[ $? != 0 ]]; then
        log-error "Unable to restart firewall. Continuing"
    fi

    # Set the local user account password
    if [[ $RDP_PASSWORD ]]; then
        log-info "Adding password for local user"
        echo $RDP_PASSWORD | passwd $RDP_USER --stdin
        if [[ $? != 0 ]]; then
            log-error "Unable to set local user password."
            exit 1
        fi
    else
        log-info "No local password set."
    fi
}

# Define internal defaults
export SCRIPT_NAME="wm-install"
export OUTPUT_DIR="./"

# Wait for jq
count=0
while [[ ! $(which jq) ]]; do
    log-info "INFO: Waiting for cloud init to finish installing jq. Waited $count minutes. Will wait 30 minutes."
    sleep 60
    count=$(( $count + 1 ))
    if (( $count > 30 )); then
        log-error "ERROR: Timeout waiting for cloud-init to install jq"
        exit 1;
    fi
done

# Parse parameters
PARAMETERS="$1"

EMAIL_ADDRESS="$(echo $PARAMETERS | jq -r '.emailAddress' )"
IBM_ENTITLEMENT_KEY="$(echo $PARAMETERS | jq -r '.entitlementKey' )"
INSTALL_DIR="$(echo $PARAMETERS | jq -r '.installDirectory' )"
INSTALL_PRODUCTS="$(echo $PARAMETERS | jq -r '.installProducts' )"
SELECTED_FIXES="$(echo $PARAMETERS | jq -r '.selectedFixes' )"
INSTALLER_URL="$(echo $PARAMETERS | jq -r '.installerURL' )"
INSTALLER_NAME="$(echo $PARAMETERS | jq -r '.installerName' )"
WM_URL="$(echo $PARAMETERS | jq -r '.wmServerUrl' )"
LICENSE_ACCEPTED="$(echo $PARAMETERS | jq -r '.licenseAccepted' )"
WORK_DIR="$(echo $PARAMETERS | jq -r '.workDirectory' )"
CONFIGURE_RDP="$(echo $PARAMETERS | jq -r '.xrdp.enable' )"
RDP_PASSWORD="$(echo $PARAMETERS | jq -r '.xrdp.password' )"
RDP_USER="$(echo $PARAMETERS | jq -r '.vmUser' )"

### XRDP Configuration
if [[ $CONFIGURE_RDP == "True" ]]; then
    log-info "Configuring RDP"
    install-xrdp $RDP_PASSWORD
else
    log-info "RDP not configured"
fi

### webMethods base installation

# Download the installer
if [[ ! -f ${WORK_DIR}/${INSTALLER_NAME} ]]; then
    log-info "INFO: Downloading the webMethods installer"
    wget -O ${WORK_DIR}/${INSTALLER_NAME} "$INSTALLER_URL"
    if [[ $? != 0 ]]; then
        log-error "Failed to download webMethods installer from $INSTALLER_URL"
        exit 1
    else
        log-info "Successfully downloaded webMethods installer"
    fi
else
    log-info "INFO: Installer already downloaded"
fi

# Create the installer script
log-info "Creating installation configuration script"
cat << EOF > ${WORK_DIR}/${SCRIPT_NAME}
ServerURL=${WM_URL}
selectedFixes=${SELECTED_FIXES}
Username=${EMAIL_ADDRESS}
HostName=$(hostname -A)
InstallProducts=${INSTALL_PRODUCTS}
Password=${IBM_ENTITLEMENT_KEY}
InstallDir=${INSTALL_DIR}
EOF

# Run the installer
if [[ $LICENSE_ACCEPTED == "True" ]]; then
    log-info "Installing webMethods"
    sudo sh ${WORK_DIR}/${INSTALLER_NAME} \
        -readScript ${WORK_DIR}/${SCRIPT_NAME} -console
    if [[ $? != 0 ]]; then
        log-error "Failure installing webMethods products"
        exit 1
    else
        log-info "Successfully installed webMethods"
    fi
else
    log-error "License not accepted. Software not installed"
fi

# Copy webMethods installer binary to permanent directory
log-info "Copying installer to webMethods install directory"
cp ${WORK_DIR}/${INSTALLER_NAME} ${INSTALL_DIR}/bin
if [[ $? != 0 ]]; then
    log-error "Unable to copy the installer to the install directory. Continuing"
else
    chmod +x ${INSTALL_DIR}/bin/${INSTALLER_NAME}
fi

# Clean up the install script
log-info "Removing the installer script"
rm ${WORK_DIR}/${SCRIPT_NAME}


log-info "From GUI, run the following to configure products"
log-info "/bin/sh ${INSTALL_DIR}/bin/${INSTALLER_NAME}"

log-info "Install completed"