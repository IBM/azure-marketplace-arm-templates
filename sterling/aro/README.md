# Deploy Azure Red Hat OpenShift cluster

Deploys an Azure Red Hat OpenShift cluster. This is called as a sub-deployment of the Sterling OMS BYOL marketplace listing.

Run the following command from the target subscription to obtain the Red Hat resource provider Id

```shell
az ad sp list --display-name "Azure Red Hat OpenShift RP" --query '[0].id' -o tsv 
```