# Tools for watsonx.ai deployment

## api-test.yaml

This Ansible playbook allows the watsonx.ai light-weight engine to be tested with a simple text generation query.

Prequisites:
- ansible core installed on the local workstation
- access to the OpenShift ingress where the watsonx.ai instance is installed
- an API Key for the watsonx.ai platform. Refer [here](https://www.ibm.com/docs/en/cloud-paks/cp-data/5.0.x?topic=steps-generating-api-keys#api-keys__platform__title__1) for details. The web client is available at the zen URL, for example, `https://cpd-cpd-instance.apps.mydomain.australiaeast.aroapp.io/zen`

Usage:

```shell
ansible-playbook ./api-test.yaml
```