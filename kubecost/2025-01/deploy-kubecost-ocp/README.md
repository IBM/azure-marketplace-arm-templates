# Deploy Kubecost on OpenShift script

This script is designed to run in an Azure CLI container. 

At a high level, it will,
1. download the OpenShift CLI tool, oc
1. log into the OpenShift cluster
1. get the default operator CSV if not defined
1. get the example operand if not defined
1. create the namespace
1. create the operator group
1. create the operator subscription and wait for the CSV to be exist
1. if the license is accepted it will create the cost analyzer operand
1. create the route to the operand