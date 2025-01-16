# Bring-your-own Azure Red Hat OpenShift

These are the plan files uploaded to the Azure marketplace that deploy IBM sip onto an existing Azure Red Hat OpenShift cluster. They call a sub-deployment from this same repository that creates a virtual machine, installs Ansible, downloads the Ansible playbooks and then executes them.

The files in this folder are:
- `createUiDefinition.json` the user interface definition for the Azure marketplace.
- `mainTemplate.json` the ARM template that is called by the Azure marketplace.
- `byo-aro-<version>.zip` a zip file containing the mainTemplate.json and createUiDefinition.json that is uploaded into the Azure marketplace plan. Where `<version>` is the version in the Azure marketplace plan.
- `README.md` this file.