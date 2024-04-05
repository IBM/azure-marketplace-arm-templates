# Create Network Security Groups (NSG) for the OpenShift deployment

This ARM template will create the network security groups needed for the control and worker subnets of an OpenShift deployment. It does not assign them to subnets.

The following rules are created for the NSG's.

- Control Subnet
    - Allow port 6443 inbound from any (for API access)
    - Allow port 22623 inbound from any (this can be removed post deployment)

- Worker Subnet
    - Allow port 443 inbound from any 
    - Allow port 80 inbound from any

It will return the Azure identifier for the created NSG's.