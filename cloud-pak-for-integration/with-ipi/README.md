# IBM Cloud Pak for Integration deployment with Self-Managed OpenShift

Azure marketplace listing that: 
1. Creates and uses existing virtual network
2. Creates Azure resources needed for solution including KeyVault, storage account and managed identity
3. Creates a self-managed Installer-Provisioned-Infrastructure (IPI) OpenShift cluster
4. Installs Red Hat OpenShift Data Foundation onto the OpenShift cluster 
5. Creates a storage cluster on the OpenShift cluster
6. Installs IBM Cloud Pak for Integration operators onto the OpenShift cluster
7. If license is accepted, creates an IBM Cloud Pak for Integration Navigator instance on the OpenShift cluster

## Installation

From the Azure Marketplace search for the `IBM Cloud Pak for Integration (BYOL) on Red Hat OpenShift` tile.

Choose the `New self-managed cluster` plan and click on `Create`.

### Basics tab

On the Basics tab,
- Choose the subscription
- Select an existing or create a new resource group for the non-OpenShift resources.
- Select the region to deploy into
- Choose a name to be used to prefix the created resources

### Network Setting stab

On the Network Settings tab,
- Leave as default to create a new virtual network or select an existing virtual network. 

If using an existing virtual network, it must be based in the same location as the region selected on the Basics tab. The virtual network and subnet addresses can be modified as necessary. Avoid overlap with `10.128.0.0/14` (`10.128.0.0` through `10.131.255.255`) and `172.30.0.0/16` (`172.30.0.0` through `172.30.255.255`) which are used internally by OpenShift.

Also, if using an existing virtual network, ensure that the subnets either do not exist, or if they do, that they have no network security group or delegations in place.

The Control Subnet is used for the OpenShift control plane nodes. 

The Worker Subnet is used for the OpenShift compute nodes.

The Endpoint Subnet is used by the deployment script containers to build the environment. It can be used for other Azure services to use the local virtual network post build.

### OpenShift Cluster tab

On the OpenShift cluster tab, 
- Select the required OpenShift version. At the time of writing, only 4.12 is supported and available.
- Select the DNS Zone from the existing ones in the subscription. For details, refer [here](https://docs.openshift.com/container-platform/4.12/installing/installing_azure/installing-azure-account.html#installation-azure-network-config_installing-azure-account) for details on configuring a public DNS zone in Azure for the OpenShift cluster. This must be done prior to deployment.
- Select to use either an new or existing resource group.
- The resource group name box will vary depending upon whether the prior selection is new or existing resource group. 
    - If an existing resource group, a list of the available resource groups in the same region as the region selected on the Basics tab. **The existing resource group must be emtpy.** It must also have contributor and user access administrator roles assigned to the service principal selected later. 
    - If using a new resource group, a text box is provided with a suggested resource group name. Overwrite this as necessary. Be sure to not use the name of an existing resource group.
- Select the Control VM Size using the VM selection dialog, or leave as default
- Select the Worker VM size using the VM selection dialog, or leave as default. The ODF storage cluster will be deployed onto the same nodes, so the minimum size aligns with the minimum ODF node size of 16 vCPU and 64GiB memory.
- Use the slider to select the number of required worker nodes. A minimum of 3 is required.
- The checkbox determines whether host encryption will be used for the control and worker nodes. This feature needs to be enabled in the subscription prior to being used. Refer [here](https://learn.microsoft.com/en-us/azure/virtual-machines/disks-enable-host-based-encryption-portal?tabs=azure-cli) for details on enabling this feature.

Service Principal
- Select whether to use a new or existing service principal. If using a new service principal, your user needs to have permissions to create a new user.
- Use the service prinicpal dialog to either create a new service principal or select an existing one.
- If using an existing service principal, you will be prompted for the service principal's password or certificate thumbprint.

- Enter your Red Hat pull secret for the OpenShift subscription. This will be used to log into the Red Hat container registry to pull the OpenShift images. Refer [here](https://access.redhat.com/documentation/en-us/openshift_cluster_manager/2023/html/managing_clusters/assembly-managing-clusters#downloading_and_updating_pull_secrets) for details on obtaining a Red Hat pull secret.

- Select the ODF size per node. This will translate into the approximate capacity available on ODF as each node has a full copy the ODF data. The total provisioned storage will be 3 times this amount as the storage is replicated across 3 nodes. So for example, 2 TiB per node will have approximately 2 TiB available (actual will be less than this to allow for management overhead and is typically closer to 90% of this) and 6 TiB of total provisioned capacity.

### Cloud Pak for Integration tab

- Enter your IBM Entitlement key for the IBM container registry (icr.io) 
- Confirm the key in the next text box

- Select the version of IBM Cloud Pak for Integration to install and the associated license identification.
- Select to accept the license to create a new instance of the Platform Navigator as part of the deployment. If not accepted, the deployment will still proceed, however, no Platform Navigator instance will be created
- Enter the namespace to use for the Platform Navigator.

### Tags tab

- Enter key pairs for all or some of the resources that will be created.

Note that the OpenShift deployed resources will not be tagged but do exist in a separate resource group.

## Credentials

The OpenShift cluster login credentials are saved to the created KeyVault as part of the deployment. In order to access the credentials, it is necessary to add yourself as a secrets user. To do so, locate the KeyVault created as part of the deployment. It will be named '<name_prefix>-<random_letters>-keyvault' and located in the resource group selected in the Basics tab of the deployment. 

1. Open the KeyVault and go to `Access control (IAM)` from the items on the left menu.
2. Select `+ Add` from the top menu and choose `Add role assignment`
3. Search for the Job Function role `Key Vault Secrets User` and select this role
4. Move to `Members` by selecting it or pressing `Next`
5. From the members tab, click on `+Select members` to bring up the select members dialog
6. Seach for your user name and select it
7. When you see your user name in the select members list, press the `Select` button
8. Press the `Review + assign` button to create the assignment

After a short while, you should be able to see a list of secrets under `Objects` -> `Secrets` from the left hand menu. If you get an error stating that you do not have permission, try the `Refresh` button. You should see the following list of secrets.
|  Secret Name      | Description                                                                      |
|-------------------|----------------------------------------------------------------------------------|
| cluster-metadata  | Contains the cluster's metadata used for cluster removal. |
| cluster-password  | Password for the kubeadmin user to allow access to the OpenShift console |
| *-sshkey          | Private key for ssh access to the cluster's nodes / virtual machines |
| kubeconfig        | Access file for the command line with the oc tool. |

To view the contents of a secret, select the secret and open the current version. You should then be able to either see the secret's value by pressing the `Show Secret Value` button or copy to clipboard with the copy button to the right of the secret.

## Cluster removal

To cleanly remove the provisioned OpenShift cluster it is recommended to follow these instructions to ensure the DNS zone is also cleaned up.

1. Obtain access to the secrets in the KeyVault if not already.
2. Locate the metadata secret in the KeyVault. Copy and save the secret to a local file with the name 'metadata.json'
3. If not already, download the `openshift-install` command line tool to your local workstation. The version does not matter for destroying the cluster. The repository for the openshift command line tools can be found [here](https://mirror.openshift.com/pub/openshift-v4). 
4. If not already, create the service principal credential file on your local workstation. This can be created with the following command lines (these commands require the Azure CLI tools to be installed on your workstation, refer [here](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) , or put the values in manually):
```shell
SUBSCRIPTION_ID="$(az account show --query 'id' -o tsv)"
TENANT_ID="$(az account show --query 'tenantId' -o tsv)"
CLIENT_ID="$(az deployment group show -g $RESOURCE_GROUP -n deployOpenShift --query 'properties.parameters.clientId.value' -o tsv)"
CLIENT_SECRET="<client_secret>"    # Put the secret for the service principal here

cat << EOF > ~/.azure/osServicePrincipal.json
{
    "subscriptionId":"$SUBSCRIPTION_ID",
    "clientId":"$CLIENT_ID",    
    "clientSecret":"$CLIENT_SECRET",
    "tenantId":"$TENANT_ID"
}
EOF
chmod 600 ~/.azure/osServicePrincipal.json
```
5. From the same directory that you saved the metadata.json file, run the following to remove the OpenShift cluster and clean up the DNS Zone.
```shell
openshift-install destroy cluster --dir ./ --log-level=debug
```