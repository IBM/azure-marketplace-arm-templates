# Deploy IBM Cloud Pak for Integration on OpenShift

This ARM template will deploy IBM Cloud Pak for Integration onto an OpenShift cluster.

## Prerequisites

- OpenShift cluster. Either Azure Red Hat OpenShift (ARO) or OpenShift Container Platform (OCP) are supported.
- Create or have a a version specification file with a filename `specs-${VERSION}.json` when VERSION is the IBM Cloud Pak for Integration version to deploy such as `2022.2.1`.
