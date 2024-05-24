#!/bin/bash

# Wait for cloud-init to finish
count=0
until [[ $(/usr/bin/ps xua | grep cloud-init | grep -v grep) == "" ]]; do
    echo "INFO: Waiting for cloud init to finish. Waited $count minutes. Will wait 15 minutes."
    sleep 60
    count=$(( $count + 1 ))
    if (( $count > 15 )); then
        echo "ERROR: Timeout waiting for cloud-init to finish"
        exit 1;
    fi
done