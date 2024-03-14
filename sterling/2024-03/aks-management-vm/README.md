# ARM Template to deploy and configure a management VM for AKS

This ARM Template deploys a develop virtual machine as part of the Sterling BYOL marketplace.

## Login

An admin user and password need to be provided. 

## Tools

The following tools are installed:
- docker
- helm
- kubectl (via the az aks cli)
- kubelogin

## Networking

An existing subnet can be provided, or a new one can be created. If creating a new subnet, specify the subnet name and the NAT gateway to attach to the subnet.

Public IP address is optional.