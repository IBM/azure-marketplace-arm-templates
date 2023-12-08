# ARM Template to deploy and configure a developer VM

This ARM Template deploys a develop virtual machine as part of the Sterling OMS BYOL marketplace.

## Login

An admin user and password need to be provided. It is recommended that this VM is only used within a secure environment with a bastion service as the access point.

## Tools

The following tools are installed:
- docker
- helm
- openshift client (oc)

## Networking

An existing subnet can be provided, or a new one can be created. If creating a new subnet, specify the subnet name and the NAT gateway to attach to the subnet.

The VM only has an internal IP address for the VNet. No public IP address.