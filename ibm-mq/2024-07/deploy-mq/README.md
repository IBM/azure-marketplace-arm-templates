# Deployment files for IBM MQ on OpenShift

This folder contains the files that are downloaded at runtime by the Azure marketplace template.

The `wait-for-cloud-init.sh` script is used to wait for the Ansible runtimes to be deployed by the cloud-init process.

The `azuredeploy.json` file is an ARM template that is called by the Azure marketplace. It deploys a virtual machine, runs the `cloud-init` process, downloads the ansible playbook files, runs the `wait-for-cloud-init.sh` script and then executes the ansible playbook `main.yaml`.