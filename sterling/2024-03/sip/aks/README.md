# Azure ARM Template that uses a deployment script to create an SIP instance on AKS

This ARM template will create a deployment script and then run a script in that deployment script container to deploy Sterling Intelligent Promising to Azure Kubernetes Service (AKS).

If a keyvault is not utilized to store a generated JWT Key, the private key can be obtained with the following command.

```shell
az resource show -n siptest-script -g $RESOURCE_GROUP --resource-type Microsoft.Resources/deploymentScripts | jq .properties.outputs.jwtKey.privateKey -r 
```