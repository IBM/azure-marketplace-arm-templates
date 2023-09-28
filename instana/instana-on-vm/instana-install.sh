#!/bin/bash

# Check input parameters
ENV_VAR_NOT_SET=""

if [[ -z $DOWNLOAD_KEY ]]; then ENV_VAR_NOT_SET="DOWNLOAD_KEY"; fi
if [[ -z $SALES_KEY ]]; then ENV_VAR_NOT_SET="SALES_KEY"; fi
if [[ -z $TENANT_NAME ]]; then ENV_VAR_NOT_SET="TENANT_NAME"; fi
if [[ -z $ENV_NAME ]]; then ENV_VAR_NOT_SET="ENV_NAME"; fi
if [[ -z $FQDN ]]; then ENV_VAR_NOT_SET="FQDN"; fi

if [[ -n $ENV_VAR_NOT_SET ]]; then
    echo "ERROR: $ENV_VAR_NOT_SET not set. Please set and retry."
    exit 1
fi

# Set defaults
TMP_DIR="/tmp"

# Install Docker

if [[ -z $(which docker) ]]; then

    echo "INFO: Installing docker"

    # Set defaults
    DOCKER_VERSION="24"

    # Download and install docker-ce, containerd.io and other packages
    ## TODO: Change the below to look for different versions depending upon OS and obtain latest
    wget -q -O $TMP_DIR/containerd.io.rpm https://download.docker.com/linux/centos/9/x86_64/stable/Packages/containerd.io-1.6.24-3.1.el9.x86_64.rpm
    wget -q -O $TMP_DIR/docker-ce.rpm https://download.docker.com/linux/centos/9/x86_64/stable/Packages/docker-ce-24.0.6-1.el9.x86_64.rpm
    wget -q -O $TMP_DIR/docker-cli.rpm https://download.docker.com/linux/centos/9/x86_64/stable/Packages/docker-ce-cli-24.0.6-1.el9.x86_64.rpm
    wget -q -O $TMP_DIR/docker-rootless-extras.rpm https://download.docker.com/linux/centos/9/x86_64/stable/Packages/docker-ce-rootless-extras-24.0.6-1.el9.x86_64.rpm
    wget -q -O $TMP_DIR/docker-compose.rpm https://download.docker.com/linux/centos/9/x86_64/stable/Packages/docker-compose-plugin-2.21.0-1.el9.x86_64.rpm
    wget -q -O $TMP_DIR/docker-buildx.rpm https://download.docker.com/linux/centos/9/x86_64/stable/Packages/docker-buildx-plugin-0.11.2-1.el9.x86_64.rpm

    sudo yum install -y ${TMP_DIR}/containerd.io.rpm
    sudo yum install -y ${TMP_DIR}/docker-cli.rpm
    sudo yum install -y ${TMP_DIR}/docker-rootless-extras.rpm ${TMP_DIR}/docker-ce.rpm
    sudo yum install -y ${TMP_DIR}/docker-compose.rpm
    sudo yum install -y ${TMP_DIR}/docker-buildx.rpm

    # Start the docker service
    sudo systemctl enable docker
    sudo systemctl start docker
else
    echo "INFO: Docker already installed on VM" 
fi

# Install the Instana console
if [[ -z $(which instana) ]]; then
    echo "INFO: Installing the Instana console"
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
    echo "INFO: Instana console already installed"
fi

# Create the self-signed certificates

# Open firewall ports
sudo firewall-cmd --zone=public --add-port=443/tcp --permanent
sudo firewall-cmd --zone=public --add-port=80/tcp --permanent
sudo firewall-cmd --zone=public --add-port=86/tcp --permanent
sudo firewall-cmd --zone=public --add-port=446/tcp --permanent
sudo firewall-cmd --zone=public --add-port=1444/tcp --permanent
sudo firewall-cmd --reload

# Create the Instana instance
