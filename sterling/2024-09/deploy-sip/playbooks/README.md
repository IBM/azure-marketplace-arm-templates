# Ansible playbook to deploy IBM sip on OpenShift

This folder contains the Ansible playbook that is executed to deploy IBM sip catalog and operator on OpenShift. It will:
1. download the latest stable version of the OpenShift command line, oc;
2. log into the OpenShift cluster;
3. create the IBM entitlement key secret if required (`create-secret` parameter is set true)
4. create the catalog source/s
5. if namespace scope for deployment:
    a. create the namespace if not present
    b. create the operator group
    c. create the subscription/s
6. if all-namespaces (cluster) scoped:
    a. create the subscription/s

The input parameters are as follows:

```yaml
ansible_python_interpreter: "/usr/bin/python3"   # The python runtime to be utilized
log_level: "info"     # The log level either info or debug (generates additional debugging output)
create_secret: false    # Flag on whether to create a the cp.icr.io registry credentials secret
entitlementKey: ""     # The IBM entitlement key to be used for the secret if creating
sip:
    version: "sip"    # The version file to download specs-<version>.json
    branch: "main"   # github branch for the version file
    version_uri: "https://raw.githubusercontent.com/IBM/azure-marketplace-arm-templates"
    version_path: "ibm-sip/version-files"   # path to the version files
operator:
    scope: "namespace"     # The scope to deploy the subscriptions. Either namespace or cluster.
    namespace: "sip"        # The namespace for the operator to be deployed into
cluster:
    api_server: ""     # The API URL for the (e.g. https://api.mycluster.org:6443)
    username: ""       # The administrator username (ignored if using token != "")
    password: ""       # The administrator password (ignored if using token != "")
    token: ""          # A login token with administrator rights
directories:
    bin_dir: "/usr/local/bin"   # Path to the Ansible and oc binaries
    tmp_dir: "/tmp"             # Temporary directory for files
default:
    retries: 60            # Number of retries for wait tasks
    retry_delay: 15        # Delay in seconds between each retry for wait tasks
```