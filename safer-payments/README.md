# Deploy a base Safer Payments cluster on Azure

## Track the deployment

- SSH into the jumpbox or use the bastion host to access
- track progress

```bash
sudo tail -f /var/lib/waagent/custom-script/download/0/script-output.log
```

## Log into the Safer Payments console

## Log into the safer payments 

## Add yourself as a secret user for the private key

This will enable you to be able to use the private key in the keyvault to access the virtual machines

1. Navigate to the key vault
2. Go to access control
3. Select `+ Add`
4. Search for `Key Vault Secrets User` and select it
5. Press next or `Members`
6. Select `+Select Members`
7. Locate your user and select it
8. Press `Review + assign` 
9. Press `Review + assign` again to confirm

You can now use the private key to access the virtual machines