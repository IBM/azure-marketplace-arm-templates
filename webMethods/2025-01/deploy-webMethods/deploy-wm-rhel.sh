#!/bin/bash
#
# Script to deploy webMethods on a virtual machine
#

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
VNC_USER="$(echo $PARAMETERS | jq -r '.vnc.user' )"
VNC_USER="$(echo $PARAMETERS | jq -r '.vnc.password' )"
VNC_DISPLAY="$(echo $PARAMETERS | jq -r '.vnc.display')"

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
cp ${WORK_DIR}/${INSTALLER_NAME} ${INSTALL_DIR}/bin

### VNC Configuration

# Install xvnc-server
yum install -y tigervnc-server

# Set vnc display, user and password
sudo cp /usr/lib/systemd/system/vncserver@.service /etc/systemd/system/vncserver@:${VNC_DISPLAY}.service
echo ":${VNC_DISPLAY}=${VNC_USER}" >> /etc/tigervnc/vncserver.users
mkdir /home/${VNC_USER}/.vnc
echo ${VNC_PASSWORD} | vncpasswd -f > /home/${VNC_USER}/.vnc/passwd
chown -R ${VNC_USER}:${VNC_USER} /home/${VNC_USER}/.vnc
chmod 0600 /home/${VNC_USER}/.vnc/passwd

# Configure gnome for session
echo "gnome-session" > /home/${VNC_USER}/.session

echo << EOF > /home/${VNC_USER}/.vnc/config
session=gnome
securitytypes=vncauth,tlsvnc
geometry=1280x720
EOF

# Enable the service
systemctl enable vncserver@:${VNC_DISPLAY}.service
systemctl start vncserver@:${VNC_DISPLAY}.service

# Add firewall rule
firewall-cmd --permanent --add-service=vnc-server
firewall-cmd --permanent --add-port=590${VNC_DISPLAY}/tcp
firewall-cmd --reload

### Clean up

# Clean up the install script
log-info "Removing the installer script"
rm ${WORK_DIR}/${SCRIPT_NAME}

log-info "From GUI, run the following to configure products"
log-info "/bin/sh ${INSTALL_DIR}/bin/${INSTALLER_NAME}"

log-info "Install completed"