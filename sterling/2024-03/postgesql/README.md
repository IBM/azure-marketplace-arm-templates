# Azure PostgreSQL server

Deploys an Azure PostgreSQL server instance with a private link. This is a sub-deployment of the BYOL Sterling OMS marketplace listing.

## Resources

Deploys the following resources:
- Subnet (if not provided)
- Private DNS Zone
- Virtual network link for private DNS zone
- Diagnostics Workspace (if required)
- Diagnostic Analytics (if required)