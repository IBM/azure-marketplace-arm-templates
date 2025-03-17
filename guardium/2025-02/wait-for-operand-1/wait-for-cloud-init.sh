#!/bin/bash

# Wait for cloud-init to finish installing ansible
count=0
while [[ ! -f /usr/local/bin/ansible-playbook ]]; do
    echo "INFO: Waiting for cloud init to finish installing ansible. Waited $count minutes. Will wait 30 minutes."
    sleep 60
    count=$(( $count + 1 ))
    if (( $count > 30 )); then
        echo "ERROR: Timeout waiting for cloud-init to install ansible"
        exit 1;
    fi
done