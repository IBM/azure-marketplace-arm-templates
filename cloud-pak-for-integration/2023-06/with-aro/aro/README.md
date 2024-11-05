# Deploy ARO cluster

***To do: Ensure that the service principal has contributor access to the resource group***

```bash
az role assignment create --assignee $CLIENT_ID --role Contributor --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP
```