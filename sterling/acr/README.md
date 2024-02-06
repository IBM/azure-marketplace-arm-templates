# Private Container Registry

Deploys a private Azure container registry. This is used as a sub-deployment of the BYOL Sterling OMS marketplace listing.

## Resources

Deploys the following resources:
- Registry
- Subnet (use `createSubnet` if to be built, otherwise provide `subnetName` of existing subnet)
- Private DNS Zones
- Private DNS Zone Groups
- Virtual network link for the private endpoint
- Private endpoint
- Analytics workspace (use `createAnalyticsWorkspace` if required, otherwise provide `workspaceName` )