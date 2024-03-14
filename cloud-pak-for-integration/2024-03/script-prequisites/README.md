# Deploy the prequisite resources for running Azure Deployment Scripts

This ARM template will deploy the prerequisite resources necessary to run Azure deployment scripts. This is useful when running more than one deployment script as they can share the same resources.

Deployed resources include,
- Storage account (used to store the temporary file used by the deployment script container)
- Managed identity (used by the deployment script to perform actions)
- Managed identity role assignment to the resource group
- A subnet added to an existing virtual network to be used by the script container to provide local access