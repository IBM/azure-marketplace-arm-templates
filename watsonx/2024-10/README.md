# Azure Resource Manager (ARM) Template for watsonx.ai

This sub-directory contains an Azure Resource Manager (ARM) Template and associated files that deploys an Azure Red Hat OpenShift (ARO) cluster with watsonx.ai and foundation models deployed.

Key Components:
- Virtual Network (new or existing)
- Azure Red Hat OpenShift with ingress and/or API public or private together with the ability to deploy different sized nodes
- Deployment VM

![Automation Overview](./images/automation-architecture.png)