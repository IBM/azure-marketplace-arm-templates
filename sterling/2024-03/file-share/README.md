# Create a private file share

Deploys a private fileshare on Azure as a sub-deployment of the BYOL Sterling OMS marketplace listing.

## Resources

Deploys the following resources:
- Storage account 
- Subnet (if required, can be referred to if already existing, use the `createSubnet` parameter to create a subnet)
- Private DNS Zone for the private endpoint
- Virtual network link for the private endpoint
- Private endpoint
- Private DNS Zone group
- File services
- File share
- Analytics Workspace (can be created by setting the `createAnalyticsWorkspace` or provided)
- Diagnostic Settings (if required)
