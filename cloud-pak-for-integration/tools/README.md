# Tools to help with the management of the IBM Cloud Pak for Integration marketplace listing

## Generate version specification file

Generates the version specification file containing the catalog image details and the operator configurations. 

### Prerequisites

- A Linux or Mac workstation with the following tools installed.
- Access to the `icr.io` repository via port 443
- The following tools installed
    - Podman or Docker runtime
    - OpenShift command line tool, oc
    - ibm-pak extension for oc (refer [here](https://github.com/IBM/ibm-pak#download-and-verify-software))
    - jq
    - yq (refer [here](https://mikefarah.gitbook.io/yq/))


### Instructions

Start by reviewing and changing any of the default values in the start of the script. These will be added to the version specification file.

```shell
NAMESPACE="cp4i"                # Namespace for the operators
INSTANCE_NAMESPACE="cp4i"       # Namespace for the platform navigator instance
CLUSTER_SCOPED="false"          # Whether the operators are scoped for the cluster or a specific namespace
REPLICAS=1                      # Number of platform navigator instance replicas
STORAGE_CLASS="ocs-storagecluster-cephfs"       # Storage class to be used
PN_INSTANCE_YAML="pn-instance-2023-4-1.yaml"    # File containing the platform navigator instance YAML
```

The PN_INSTANCE_YAML file is to be located in the version-files directory together with the version specification file.

The version specification file needs to have the format `specs-<version>.json`. For example, `specs-2022.2.1.json`.

The input file needs to be in YAML format with a list of the operator packages to install with each in the following format.
```yaml
- name: Operator name
  operatorPackageName: operator-package-name
  operatorVersion: operator-version
  operatorChannel: operator-channel
```

For example, the following.
```yaml
- name: IBM Cloud Pak for Integration Platform Navigator
  operatorPackageName: ibm-integration-platform-navigator
  operatorVersion: 7.2.1
  operatorChannel: v7.2
```

Samples are available in the version-files directory of this repository.

The operator channel will revert to the minor release of the operator version if not specified. For example an operatorVersion of 7.2.1 will assume an operator channel of v7.2 if none is specified.

To run the tool, specify the input version file and the output specification file. For example,
```shell
generate-spec-file.sh version-2023-1.yaml spec-2023.4.1.json
```

>**IMPORTANT**
As a final check, review the details in the specifications file before use and test prior to use with the marketplace listing. 

In particular, check the subscription details. Some operators have a different operator image than what is generated. A list of available operator literals is [here](https://www.ibm.com/docs/en/cloud-paks/cp-integration/2023.4?topic=operators-installing-by-using-cli#operators-available__title__1). A well known one is the Aspera subscription which will generate a spec with `ibm-aspera-hsts-operator` when it the literal is `aspera-hsts-operator`.
