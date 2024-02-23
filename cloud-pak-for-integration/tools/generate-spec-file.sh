#!/bin/bash
# Script to generate the CP4I specifications file from the CASE package and version

# Default values
NAMESPACE="cp4i"
INSTANCE_NAMESPACE="cp4i"
CLUSTER_SCOPED="false"
REPLICAS=1
STORAGE_CLASS="ocs-storagecluster-cephfs"
PN_INSTANCE_YAML="pn-instance-2023-4-1.yaml"

TEMP_FILE="temp.json"
export ARCH="amd64"

function usage() {
    echo "Usage: generate-spec-file.sh VERSION_FILE [OUTPUT_FILE]"
    echo "    where:"
    echo "      VERSION_FILE = filename containing version information"
    echo "      OUTPUT_FILE (optional) = name of the json file to output (e.g. spec-2023.4.1.json)"
}

# Parse comamnd line
if [[ -z $1 ]]; then
    echo "ERROR: VERSION_FILE not provided"
    echo
    usage
    exit 1
else
    VERSION_FILE="$1"
fi

if [[ -z $2 ]]; then
    OUTPUT_FILE="spec-file.json"
else
    OUTPUT_FILE="$2"
fi

# Check podman or docker is available
if [[ $(which docker) ]]; then
    RUNTIME="docker"
elif [[  $(which podman) ]]; then
    RUNTIME="podman"
else
    echo "ERROR: Neither podman nor docker found"
    exit 1
fi

# Check that jq is installed
if [[ -z $(which jq) ]]; then
    echo "ERROR: jq not installed"
    exit 1
fi

# Check that yq is installed
if [[ -z $(which yq) ]]; then
    echo "ERROR: yq is not installed"
    exit 1
fi

# Check oc installed
if [[ -z $(which oc) ]]; then
    echo "ERROR: oc not installed"
    exit 1
fi

# Check ibm-pak extension is installed
if [[ -z $(which oc-ibm_pak) ]]; then
    echo "ERROR: oc-ibm_pak not installed"
    exit 1
fi

# Generate base file
cat << EOF > $OUTPUT_FILE
{
    "defaults": {
        "namespace": "$NAMESPACE",
        "instanceNamespace": "$INSTANCE_NAMESPACE",
        "clusterScoped": "$CLUSTER_SCOPED",
        "replicas": $REPLICAS,
        "storage_class": "$STORAGE_CLASS",
        "pnInstanceYaml": "$PN_INSTANCE_YAML"
    },
    "catalogSources": [
    ],
    "subscriptions" : [
    ]
}
EOF

# Generate catalog details
cat $VERSION_FILE | yq -r '.[].name' | while read package;
do
    CASE_NAME="$(cat $VERSION_FILE | yq -o=json | jq --arg PACKAGE "$package" -r '.[] | select(.name==$PACKAGE) | .operatorPackageName')"
    CASE_VERSION="$(cat $VERSION_FILE | yq -o=json | jq --arg PACKAGE "$package" -r '.[] | select(.name==$PACKAGE) | .operatorVersion')"
    OUTPUT=$(oc ibm-pak get $CASE_NAME --version $CASE_VERSION) 
    if (( $? != 0 )); then echo "ERROR: Unable to get $CASE_NAME version $CASE_VERSION details"; exit 1; fi
    OUTPUT=$(oc ibm-pak generate mirror-manifests $CASE_NAME icr.io --version $CASE_VERSION) 
    if (( $? != 0 )); then echo "ERROR: Unable to generate manifest for $CASE_NAME version $CASE_VERSION"; exit 1; fi
    
    # Determine the catalog source file to use
    if [[ -f $HOME/.ibm-pak/data/mirror/${CASE_NAME}/${CASE_VERSION}/catalog-sources.yaml ]]; then
        CATALOG_SOURCE="$HOME/.ibm-pak/data/mirror/${CASE_NAME}/${CASE_VERSION}/catalog-sources.yaml"
    elif [[ -f $HOME/.ibm-pak/data/mirror/${CASE_NAME}/${CASE_VERSION}/catalog-sources-linux-${ARCH}.yaml ]]; then
        CATALOG_SOURCE="$HOME/.ibm-pak/data/mirror/${CASE_NAME}/${CASE_VERSION}/catalog-sources-linux-${ARCH}.yaml"
    else
        echo "Could not locate catalog source yaml"
        exit 1
    fi

    # Read the list of cases, including dependencies
    #CASE_LIST=$()

    # Create the catalog source entries
    i=0;
    while [[ $(cat $CATALOG_SOURCE | yq "select(documentIndex == $i)") ]];
    do
        # Create the catalog source entry
        cat << EOF | jq '.catalogSources += [input]' $OUTPUT_FILE - > $TEMP_FILE
    {
        "name": "$(cat $CATALOG_SOURCE | yq -r "select(documentIndex == $i) | .metadata.name")",
        "displayName": "$(cat $CATALOG_SOURCE | yq -r "select(documentIndex == $i) | .spec.displayName")",
        "image": "$(cat $CATALOG_SOURCE | yq -r "select(documentIndex == $i) | .spec.image")",
        "publisher": "$(cat $CATALOG_SOURCE | yq -r "select(documentIndex == $i) | .spec.publisher")",
        "sourceType": "$(cat $CATALOG_SOURCE | yq -r "select(documentIndex == $i) | .spec.sourceType")",
        "registryUpdate": "$(cat $CATALOG_SOURCE | yq -r "select(documentIndex == $i) | .spec.updateStrategy.registryPoll.interval")"
    }
EOF
        mv $TEMP_FILE $OUTPUT_FILE

        # Create the operator entry
        CHANNEL="$(cat $VERSION_FILE | yq -o=json | jq --arg PACKAGE "$package" -r '.[] | select(.name==$PACKAGE) | .operatorChannel')"
        if [[ -z $CHANNEL ]]; then
            CHANNEL="$(echo "v$(echo ${CASE_VERSION} | awk -F"." '{print $1}').$(echo ${CASE_VERSION} | awk -F"." '{print $2}')")"
        fi
        
        # Set the operator name and if a dependency, use the catalog displayName
        if (( $i > 0 )); then 
            OPERATOR_NAME="$(cat $CATALOG_SOURCE | yq -r "select(documentIndex == $i) | .spec.displayName")"
        else 
            OPERATOR_NAME="$package" 
        fi

        cat << EOF | jq '.subscriptions += [input]' $OUTPUT_FILE - > $TEMP_FILE
    {
        "name": "$OPERATOR_NAME",
        "metadata": {
            "name": "$(cat $CATALOG_SOURCE | yq -r "select(documentIndex == $i) | .metadata.name")"
        },
        "spec": {
            "name": "${CASE_NAME}",
            "channel": "${CHANNEL}",
            "source": "$(cat $CATALOG_SOURCE | yq -r "select(documentIndex == $i) | .metatdata.name")",
            "installPlanApproval": "Automatic"
        }
    }
EOF
        mv $TEMP_FILE $OUTPUT_FILE

        # Increment for next document
        i=$(( $i + 1 ))
    done
done

echo 
echo "Completed. Version specification file saved to $OUTPUT_FILE"
