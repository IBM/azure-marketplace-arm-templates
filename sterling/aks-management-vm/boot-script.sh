#!/bin/bash
# Basic script to update the OS and setup to manage an AKS cluster.

# Update the OS
sudo apt update
sudo apt -y dist-upgrade

# Install the az CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Log into the VM
az login --identity

# Enable the firewall
sudo ufw allow "openSSH"
sudo ufw enable