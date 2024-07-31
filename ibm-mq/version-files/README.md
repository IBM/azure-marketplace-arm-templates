# Version files for IBM MQ

These files are downloaded by the deployment scripts at runtime and define the catalog and subscription definitions to be deployed for that version. The file name format must be  `specs-<version>.json` where `<version>` is the version specified when calling the deployment. For example, if the deployment script were to deploy version `1.1` then the specification filename would be `specs-1.1.json`. 

> The deployment scope can only be cluster (all-namespaces) or namespaced for *all* subscriptions. It is not possible to have some subscriptions all-namespaces and others by namespace.

Each file is in JSON format and has the following specification.

```json
{
  "version": "string",  // The version identifier
  "defaults": {
    "namespace": "string",   // Default namespace if not specified (may not be used in some deployment versions)
    "clusterScoped": "boolean" // Default subscription type if not specified (may not be used in some deployment versions)
  },
  "catalogSources": [
    // List of catalog sources to create with each entry per the below
    {
      "name": "string",  // The catalog identified
      "displayName": "string",  // The display name for the catalog
      "image": "string",  // Catalog image to install, including registry and relevant tags or SHA
      "publisher": "string",   // The publisher's identifier
      "sourceType": "string",  // The catalog source type (e.g. grpc)
      "registryUpdate": "string"  // How often to check for catalog source updates 
    }
  ],
  "subscriptions": [
    // List of subscriptions to create with each entry per the below
    {
      "name": "string",  // The display name of the subscription definition
      "metadata": {
        "name": "string"   // The name of the subscription
      },
      "spec": {
        "name": "string",  // The name of the subscription
        "channel": "string",   // The update channel for the subscription
        "source": "string",    // The catalog source for the subscription
        "installPlanApproval": "string"  // Whether updates should be automatically applied or have user approval
      }
    }
  ]
}

```