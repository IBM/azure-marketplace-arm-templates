# Marketplace plan files 

The files in this directory are uploaded into the Azure marketplace plan (as a zip file)

> IMPORTANT: The private OpenShift cluster support has been disabled pending a fix of the latest deploymentScript support for subnet attachment. Line 125 and line 183 (which should be `[steps('openshift').privateVnet]`) in the createUiDefinition is set to false until then.