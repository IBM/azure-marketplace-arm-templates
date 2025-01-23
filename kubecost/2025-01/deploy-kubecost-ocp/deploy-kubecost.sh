#!/bin/bash
#
# Script to install kubecost onto an OpenShift cluster.
# Designed to be run from an Azure CLI container
#
# Tested with image mcr.microsoft.com/azure-cli:2.60.0 and OpenShift CLI version 4.17

function log-output() {
    MSG=${1}

    if [[ -z $OUTPUT_DIR ]]; then
        OUTPUT_DIR="/mnt/azscripts/azscriptoutput"
    fi
    mkdir -p $OUTPUT_DIR

    if [[ -z $OUTPUT_FILE ]]; then
        OUTPUT_FILE="script-output.log"
    fi

    echo "$(date -u +"%Y-%m-%d %T") ${MSG}" >> ${OUTPUT_DIR}/${OUTPUT_FILE}
    echo ${MSG}
}

function log-info() {
    MSG=${1}

    log-output "INFO: $MSG"    
}

function log-error() {
    MSG=${1}

    log-output "ERROR: $MSG"
}

function oc-login() {
# Login to an OpenShift cluster. 
# Usage:
#        oc-login API_SERVER OCP_USERNAME OCP_PASSWORD BIN_DIR 
#

    if [[ -z ${1} ]] || [[ -z $API_SERVER ]]; then
        log-error "API_SERVER not passed to function oc-login"
        exit 1
    elif [[ ${1} != "" ]]; then
        API_SERVER=${1}
    fi

    if [[ -z ${2} ]] || [[ -z $OCP_USERNAME ]]; then
        log-error "OCP_USERNAME not passed to function oc-login"
        exit 1
    elif [[ ${2} != "" ]]; then
        OCP_USERNAME=${2}
    fi

    if [[ -z ${3} ]] || [[ -z $OCP_PASSWORD ]]; then
        log-error "OCP_PASSWORD not passed to function oc-login"
        exit 1
    elif [[ ${3} != "" ]]; then
        OCP_PASSWORD=${3}
    fi

    if [[ -z ${4} ]] || [[ -z $BIN_DIR ]]; then
        BIN_DIR="/usr/local/bin"
    elif [[ ${4} != "" ]]; then
        BIN_DIR="${4}"
    fi

    if ! ${BIN_DIR}/oc status 1> /dev/null 2> /dev/null; then
        log-info "Logging into OpenShift cluster $API_SERVER"

        # Below loop added to allow authentication service to start on new clusters
        count=0
        while ! ${BIN_DIR}/oc login $API_SERVER -u $OCP_USERNAME -p $OCP_PASSWORD --insecure-skip-tls-verify=true 1> /dev/null 2> /dev/null ; do
            log-info "Waiting to log into cluster. Waited $count minutes. Will wait up to 15 minutes."
            sleep 60
            count=$(( $count + 1 ))
            if (( $count > 15 )); then
                log-error "Timeout waiting to log into cluster"
                exit 1;    
            fi
        done
        log-info "Successfully logged into cluster $API_SERVER"
    else   
        CURRENT_SERVER=$(${BIN_DIR}/oc status | grep server | awk '{printf $6}' | sed -e 's#^https://##; s#/##')

        if [[ $CURRENT_SERVER == $API_SERVER ]]; then
            log-info "Already logged into cluster"
        else

            # Below loop added to allow authentication service to start on new clusters
            count=0
            while ! ${BIN_DIR}/oc login $API_SERVER -u $OCP_USERNAME -p $OCP_PASSWORD --insecure-skip-tls-verify=true > /dev/null 2>&1 ; do
                log-info "Waiting to log into cluster. Waited $count minutes. Will wait up to 15 minutes."
                sleep 60
                count=$(( $count + 1 ))
                if (( $count > 15 )); then
                    log-error "Timeout waiting to log into cluster"
                    exit 1;    
                fi
            done
            log-info "Successfully logged into cluster $API_SERVER"
        fi
    fi
}

function oc-download() {
# Download and install the Red Hat OpenShift oc cli tool 
# Usage:
#        oc-download BIN_DIR TMP_DIR OC_VERSION 
#
    
    if [[ -z ${1} ]]; then
        local BIN_DIR="/usr/local/bin"
    else
        local BIN_DIR=${1}
    fi

    if [[ -z ${2} ]]; then
        local TMP_DIR="/tmp"
    else
        local TMP_DIR=${2}
    fi

    if [[ -z ${3} ]] || [[ ${3}  == "4" ]] || [[ ${3} == "stable" ]]; then
        # Install the latest stable version. Using 4.12 to avoid issues with container compatibility.
        local OC_VERSION="stable-4.12"
        local OCP_RELEASE=12
    elif [[ ${VERSION} =~ [0-9][.][0-9]+[.][0-9]+ ]]; then
        # Install a specific version and patch level
        local OC_VERSION="${VERSION}"
        local OCP_RELEASE=$(( $(echo $VERSION | awk -F'.' '{print $2}') ))
    else
        # Install the latest stable subversion
        local OC_VERSION="stable-${3}"
        local OCP_RELEASE=$(( $(echo ${3} | awk -F'.' '{print $2}') ))
    fi

    local ARCH=$(uname -m)
    local OC_FILETYPE="linux"
    local OC_URL="https://mirror.openshift.com/pub/openshift-v4/${ARCH}/clients/ocp/${OC_VERSION}/openshift-client-${OC_FILETYPE}.tar.gz"

    if [[ -f ${BIN_DIR}/oc ]]; then
        log-info "Openshift client binary already installed"
    else
        log-info "Downloading and installing oc"
        wget -O $TMP_DIR/openshift-client.tgz $OC_URL

        if ! error=$(tar xzf ${TMP_DIR}/openshift-client.tgz -C ${TMP_DIR} oc 2>&1) ; then
            log-error "Unable to extract oc from tar file"
            log-error "$error"
            exit 1
        fi

        if ! error=$(mv ${TMP_DIR}/oc ${BIN_DIR}/oc 2>&1) ; then
            log-error "Unable to move oc to $BIN_DIR"
            log-error "$error"
            exit 1
        fi
    fi

}

function subscription_status() {
    SUB_NAMESPACE=${1}
    SUBSCRIPTION=${2}

    CSV=$(${BIN_DIR}/oc get subscription -n ${SUB_NAMESPACE} ${SUBSCRIPTION} -o json | jq -r '.status.currentCSV')
    if [[ "$CSV" == "null" ]]; then
        STATUS="PendingCSV"
    else
        STATUS=$(${BIN_DIR}/oc get csv -n ${SUB_NAMESPACE} ${CSV} -o json | jq -r '.status.phase')
    fi
    echo $STATUS
}

function wait_for_subscription() {
    SUB_NAMESPACE=${1}
    export SUBSCRIPTION=${2}
    
    # Set default timeout of 15 minutes
    if [[ -z ${3} ]]; then
        TIMEOUT=15
    else
        TIMEOUT=${3}
    fi

    export TIMEOUT_COUNT=$(( $TIMEOUT * 60 / 30 ))

    count=0;
    while [[ $(subscription_status $SUB_NAMESPACE $SUBSCRIPTION) != "Succeeded" ]]; do
        log-output "INFO: Waiting for subscription $SUBSCRIPTION to be ready. Waited $(( $count * 30 )) seconds. Will wait up to $(( $TIMEOUT_COUNT * 30 )) seconds."
        sleep 30
        count=$(( $count + 1 ))
        if (( $count > $TIMEOUT_COUNT )); then
            log-output "ERROR: Timeout exceeded waiting for subscription $SUBSCRIPTION to be ready"
            exit 1
        fi
    done
}

log-info "Script starting"

######
# Set defaults
if [[ -z $OCP_USERNAME ]]; then OCP_USERNAME="kubeadmin"; fi
if [[ -z $LICENSE ]]; then LICENSE="decline"; fi
if [[ -z $WORKSPACE_DIR ]]; then WORKSPACE_DIR="/mnt/azscripts/azscriptinput"; fi
if [[ -z $BIN_DIR ]]; then export BIN_DIR="/usr/local/bin"; fi
if [[ -z $TMP_DIR ]]; then TMP_DIR="${WORKSPACE_DIR}/tmp"; fi
if [[ -z $OC_VERSION ]]; then OC_VERSION="4.17"; fi    
if [[ -z $HELM_VERSION ]]; then HELM_VERSION="v3.4.1"; fi
if [[ -z $NAMESPACE ]]; then NAMESPACE="kubecost"; fi
if [[ -z $CLUSTER_NAME ]]; then CLUSTER_NAME="myCluster"; fi
if [[ -z $OC_VERSION ]]; then OC_VERSION="4.17"; fi

######
# Check environment variables
ENV_VAR_NOT_SET=""

if [[ -z $API_SERVER ]]; then ENV_VAR_NOT_SET="API_SERVER"; fi
if [[ -z $OCP_PASSWORD ]]; then ENV_VAR_NOT_SET="OCP_PASSWORD"; fi

if [[ -n $ENV_VAR_NOT_SET ]]; then
    log-output "ERROR: $ENV_VAR_NOT_SET not set. Please set and retry."
    exit 1
fi

### Configure environment
# Create tmp directory
mkdir -p ${TMP_DIR}

# Install tools - oc
if [[ -f ${BIN_DIR}/oc ]]; then
    log-info "oc already installed"
else
    oc-download $BIN_DIR $TMP_DIR $OC_VERSION
fi

# Log into cluster
oc-login $API_SERVER $OCP_USERNAME $OCP_PASSWORD $BIN_DIR

# Create the namespace
${BIN_DIR}/oc get ns ${NAMESPACE} > /dev/null 2> /dev/null
if [[ $? != 0  ]]; then
    log-info "Creating namespace"
    ${BIN_DIR}/oc create ns ${NAMESPACE} 
    if [[ $? != 0 ]]; then
        log-error "Unable to create namespace ${NAMESPACE}"
        exit 1
    else
        log-info "Successfully created namespace ${NAMESPACE}"
    fi
else
    log-info "Namespace ${NAMESPACE} already exists"
fi

# Create operatorGroup
${BIN_DIR}/oc get operatorgroup -n ${NAMESPACE} kubecost-nngns > /dev/null 2> /dev/null
if [[ $? != 0 ]]; then
    log-info "Creating Kubecost operator group"
    cat << EOF | ${BIN_DIR}/oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: kubecost-nngns
  namespace: ${NAMESPACE}
spec:
  targetNamespaces:
  - kubecost
  upgradeStrategy: Default
EOF
    if [[ $? != 0 ]]; then
        log-error "Unable to create operator group"
        exit 1
    else
        log-info "Successfully installed operator group"
    fi
else
    log-info "Operator group already installed"
fi

# Create subscription
${BIN_DIR}/oc get subscription -n ${KUBECOST} kubecost-operator > /dev/null 2> /dev/null
if [[ $? != 0 ]]; then
    log-info "Create Kubecost subscription"
    cat << EOF | ${BIN_DIR}/oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: kubecost-operator
  namespace: ${NAMESPACE}
spec:
  channel: alpha
  installPlanApproval: Automatic
  name: kubecost-operator
  source: certified-operators
  sourceNamespace: openshift-marketplace
  startingCSV: kubecost-operator.v2.5.2
EOF
    if [[ $? != 0 ]]; then
        log-error "Unable to create subscription"
        exit 1
    else
        log-info "Subscription created"
    fi
else
    log-info "Kubecost subscription already in place"
fi

# Wait for subscription to bind to CSV
wait_for_subscription ${NAMESPACE} kubecost-operator 15
log-info "Subscription ready"

# Create operand
${BIN_DIR}/oc get costanalyzer -n ${NAMESPACE} kubecost > /dev/null 2> /dev/null
if [[ $? != 0 ]]; then
    if [[ $LICENSE == "accept" ]]; then
        log-info "Creating Kubecost operand"
        cat << EOF | ${BIN_DIR}/oc apply -f -
kind: CostAnalyzer
apiVersion: charts.kubecost.com/v1alpha1
metadata:
  name: kubecost
  namespace: ${NAMESPACE}
spec:
  affinity: {}
  awsstore:
    annotations: {}
    createServiceAccount: false
    nodeSelector: {}
    priorityClassName: ''
    useAwsStore: false
  clusterController:
    actionConfigs:
      clusterRightsize: null
      clusterTurndown: []
      containerRightsize: null
      namespaceTurndown: null
    affinity: {}
    annotations: {}
    enabled: false
    image:
      repository: registry.connect.redhat.com/kubecost/kubecost-cluster-controller@sha256
      tag: 067923686d0d7db22d96ca68c11605845ba1e3ea7ebd175eebdc64296c75e649
    imagePullPolicy: IfNotPresent
    kubescaler:
      defaultResizeAll: false
    namespaceTurndown:
      rbac:
        enabled: true
    nodeSelector: {}
    priorityClassName: ''
    resources:
      limits:
        cpu: 500m
        memory: 500Mi
      requests:
        cpu: 100m
        memory: 100Mi
    tolerations: []
  costEventsAudit:
    enabled: false
  diagnostics:
    collectHelmValues: false
    deployment:
      affinity: {}
      annotations: {}
      containerSecurityContext: {}
      enabled: false
      env: {}
      labels: {}
      nodeSelector: {}
      resources:
        limits:
          cpu: 100m
          memory: 200Mi
        requests:
          cpu: 10m
          memory: 20Mi
      securityContext: {}
      tolerations: []
    enabled: true
    keepDiagnosticHistory: false
    pollingInterval: 300s
    primary:
      enabled: false
      readonly: false
      retention: 7d
  etlUtils:
    affinity: {}
    annotations: {}
    enabled: false
    env: {}
    fullImageName: null
    nodeSelector: {}
    resources: {}
    tolerations: []
  extraObjects: []
  extraVolumeMounts: []
  extraVolumes: []
  federatedETL:
    agentOnly: false
    federatedCluster: false
    readOnlyPrimary: false
    redirectS3Backup: false
    useMultiClusterDB: false
  forecasting:
    affinity: {}
    annotations: {}
    enabled: true
    env:
      GUNICORN_CMD_ARGS: '--log-level info -t 1200'
    fullImageName: 'registry.connect.redhat.com/kubecost/kubecost-modeling@sha256:ef6be6b1e7be57d85a54c115ad15fd201fe7fee86ddb7eb6394f119358a04b59'
    imagePullPolicy: IfNotPresent
    livenessProbe:
      enabled: true
      failureThreshold: 200
      initialDelaySeconds: 10
      periodSeconds: 10
    nodeSelector: {}
    priority:
      enabled: false
      name: ''
    readinessProbe:
      enabled: true
      failureThreshold: 200
      initialDelaySeconds: 10
      periodSeconds: 10
    resources:
      limits:
        cpu: 1500m
        memory: 1Gi
      requests:
        cpu: 200m
        memory: 300Mi
    tolerations: []
  global:
    additionalLabels: {}
    ammsp:
      aadAuthProxy:
        aadClientId: $<AZURE_MANAGED_IDENTITY_CLIENT_ID>
        aadTenantId: $<AZURE_MANAGED_IDENTITY_TENANT_ID>
        audience: 'https://prometheus.monitor.azure.com/.default'
        enabled: false
        identityType: userAssigned
        image: null
        imagePullPolicy: IfNotPresent
        name: aad-auth-proxy
        port: 8081
      enabled: false
      prometheusServerEndpoint: 'http://localhost:8081/'
      queryEndpoint: $<AMMSP_QUERY_ENDPOINT>
      remoteWriteService: $<AMMSP_METRICS_INGESTION_ENDPOINT>
    amp:
      enabled: false
      prometheusServerEndpoint: 'http://localhost:8005/workspaces/<workspaceId>/'
      remoteWriteService: 'https://aps-workspaces.us-west-2.amazonaws.com/workspaces/<workspaceId>/api/v1/remote_write'
      sigv4:
        region: us-west-2
    annotations: {}
    assetReports:
      enabled: false
      reports:
        - accumulate: false
          aggregateBy: type
          filters:
            - property: cluster
              value: ${CLUSTER_NAME}
          title: Example Asset Report 0
          window: today
    cloudCostReports:
      enabled: false
      reports:
        - accumulate: false
          aggregateBy: service
          title: Cloud Cost Report 0
          window: today
    containerSecurityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - ALL
      privileged: false
      readOnlyRootFilesystem: true
    gcpstore:
      enabled: false
    gmp:
      enabled: false
    grafana:
      domainName: cost-analyzer-grafana.default.svc
      enabled: false
      proxy: false
      scheme: http
    integrations:
      postgres:
        databaseHost: ''
        databaseName: ''
        databasePassword: ''
        databasePort: ''
        databaseSecretName: ''
        databaseUser: ''
        enabled: false
        queryConfigs:
          allocations: []
          assets: []
          cloudCosts: []
        runInterval: 12h
      turbonomic:
        clientId: ''
        clientSecret: ''
        enabled: false
        host: ''
        insecureClient: false
        role: ''
    mimirProxy:
      annotations: {}
      enabled: false
      mimirEndpoint: $mimir_endpoint
      name: mimir-proxy
      orgIdentifier: $your_tenant_ID
      port: 8085
    notifications:
      alertmanager:
        enabled: false
        fqdn: 'http://cost-analyzer-prometheus-server.default.svc'
    platforms:
      cicd:
        enabled: false
        skipSanityChecks: false
      openshift:
        createMonitoringClusterRoleBinding: true
        createMonitoringResourceReaderRoleBinding: true
        enabled: true
        monitoringServiceAccountName: prometheus-k8s
        monitoringServiceAccountNamespace: openshift-monitoring
        route:
          annotations: {}
          enabled: false
        scc:
          networkCosts: true
          nodeExporter: true
        securityContext:
          runAsNonRoot: true
          seccompProfile:
            type: RuntimeDefault
    podAnnotations: {}
    prometheus:
      enabled: false
      fqdn: 'https://prometheus-k8s.openshift-monitoring.svc.cluster.local:9091'
      insecureSkipVerify: false
      kubeRBACProxy: true
    savedReports:
      enabled: false
      reports:
        - accumulate: false
          aggregateBy: namespace
          chartDisplay: category
          filters:
            - key: cluster
              operator: ':'
              value: dev
          idle: separate
          rate: cumulative
          title: Example Saved Report 0
          window: today
        - accumulate: false
          aggregateBy: controllerKind
          chartDisplay: category
          filters:
            - key: namespace
              operator: '!:'
              value: kubecost
          idle: share
          rate: monthly
          title: Example Saved Report 1
          window: month
        - accumulate: true
          aggregateBy: service
          chartDisplay: category
          filters: []
          idle: hide
          rate: daily
          title: Example Saved Report 2
          window: '2020-11-11T00:00:00Z,2020-12-09T23:59:59Z'
    securityContext:
      fsGroup: 1001
      fsGroupChangePolicy: OnRootMismatch
      runAsGroup: 1001
      runAsNonRoot: true
      runAsUser: 1001
      seccompProfile:
        type: RuntimeDefault
    updateCaTrust:
      caCertsMountPath: /etc/pki/ca-trust/source/anchors
      caCertsSecret: ca-certs-secret
      enabled: false
      resources: {}
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        runAsGroup: 0
        runAsNonRoot: false
        runAsUser: 0
        seccompProfile:
          type: RuntimeDefault
  grafana:
    adminPassword: strongpassword
    adminUser: admin
    affinity: {}
    annotations: {}
    dashboardProviders: {}
    dashboards: {}
    dashboardsConfigMaps: {}
    deploymentStrategy: RollingUpdate
    env: {}
    envFromSecret: ''
    extraSecretMounts: []
    grafana.ini:
      analytics:
        check_for_updates: true
      auth.anonymous:
        enabled: true
        org_name: Main Org.
        org_role: Editor
      grafana_net:
        url: 'https://grafana.net'
      log:
        mode: console
      paths:
        data: /var/lib/grafana/data
        logs: /var/log/grafana
        plugins: /var/lib/grafana/plugins
        provisioning: /etc/grafana/provisioning
      server:
        root_url: '%(protocol)s://%(domain)s:%(http_port)s/grafana'
        serve_from_sub_path: false
    image:
      pullPolicy: IfNotPresent
      repository: registry.redhat.io/rhel9/grafana@sha256
      tag: d9a0e6646f970db628f171ec78a508e6ac329c4457aec85f0a88894ab3d5f734
    livenessProbe:
      failureThreshold: 10
      httpGet:
        path: /api/health
        port: 3000
      initialDelaySeconds: 60
      timeoutSeconds: 30
    nodeSelector: {}
    persistence:
      enabled: false
    plugins: []
    podAnnotations: {}
    priorityClassName: ''
    rbac:
      create: true
    readinessProbe:
      httpGet:
        path: /api/health
        port: 3000
    replicas: 1
    resources:
      limits:
        cpu: 100m
        memory: 128Mi
      requests:
        cpu: 100m
        memory: 128Mi
    securityContext: {}
    service:
      annotations: {}
      labels: {}
      port: 80
      type: ClusterIP
    serviceAccount:
      create: true
      name: ''
    sidecar:
      dashboards:
        annotations: {}
        enabled: true
        error_throttle_sleep: 0
        folder: /tmp/dashboards
        label: grafana_dashboard
        labelValue: '1'
      datasources:
        enabled: false
        error_throttle_sleep: 0
        label: grafana_datasource
      image:
        pullPolicy: IfNotPresent
        repository: 'quay.io/kiwigrid/k8s-sidecar@sha256:636290ab9e852814b21af53fbd909f4a8ac88f26ed4cc4dca032d88bf6c788a9'
        tag: 1.28.1
      resources: {}
    tolerations: []
  ingress:
    annotations: null
    enabled: false
    hosts:
      - cost-analyzer.local
    labels: null
    pathType: ImplementationSpecific
    paths:
      - /
    tls: []
  initChownData:
    resources: {}
  initChownDataImage: busybox
  kubecostAdmissionController:
    caBundle: '${CA_BUNDLE}'
    enabled: false
    secretName: webhook-server-tls
  kubecostAggregator:
    aggregatorDbStorage:
      storageClass: ''
      storageRequest: 128Gi
    cloudCost:
      readinessProbe:
        enabled: true
        failureThreshold: 200
        initialDelaySeconds: 10
        periodSeconds: 10
      resources:
        limits:
          cpu: 500m
          memory: 500Mi
        requests:
          cpu: 100m
          memory: 100Mi
    containerResourceUsageRetentionDays: 1
    dbConcurrentIngestionCount: 1
    dbMemoryLimit: 0GB
    dbReadThreads: 1
    dbTrimMemoryOnClose: true
    dbWriteMemoryLimit: 0GB
    dbWriteThreads: 1
    deployMethod: singlepod
    enabled: false
    etlDailyStoreDurationDays: 91
    etlHourlyStoreDurationHours: 49
    fullImageName: 'registry.connect.redhat.com/kubecost/kubecost-cost-model@sha256:922644bb9a7469fb8e131513527729a3b2be5eae94b4c61eece934c0ff95260d'
    imagePullPolicy: IfNotPresent
    jaeger:
      enabled: false
    logLevel: info
    numDBCopyPartitions: 25
    persistentConfigsStorage:
      storageClass: ''
      storageRequest: 1Gi
    readinessProbe:
      enabled: true
      failureThreshold: 200
      initialDelaySeconds: 10
      periodSeconds: 10
    replicas: 1
    resources:
      limits:
        cpu: 2000m
        memory: 40Gi
      requests:
        cpu: 500m
        memory: 1Gi
    service:
      labels: {}
    stagingEmptyDirSizeLimit: 2Gi
  kubecostDeployment:
    annotations: {}
    labels: {}
    replicas: 1
  kubecostFrontend:
    deployMethod: singlepod
    deploymentStrategy: {}
    enabled: true
    fullImageName: 'registry.connect.redhat.com/kubecost/kubecost-frontend@sha256:70dc1dc12ef87026a035b9320173a54d5c600c4a6c182462249cbb53066e3fe5'
    haReplicas: 2
    imagePullPolicy: IfNotPresent
    ipv6:
      enabled: true
    livenessProbe:
      enabled: true
      failureThreshold: 6
      initialDelaySeconds: 1
      periodSeconds: 5
    readinessProbe:
      enabled: true
      failureThreshold: 6
      initialDelaySeconds: 1
      periodSeconds: 5
    resources:
      limits:
        cpu: 20m
        memory: 110Mi
      requests:
        cpu: 10m
        memory: 55Mi
    useDefaultFqdn: false
  kubecostMetrics: null
  kubecostModel:
    allocation: null
    containerStatsEnabled: true
    etlDailyStoreDurationDays: 91
    etlHourlyStoreDurationHours: 49
    etlReadOnlyMode: false
    extraArgs: []
    extraPorts: []
    federatedStorageConfig: null
    fullImageName: 'registry.connect.redhat.com/kubecost/kubecost-cost-model@sha256:922644bb9a7469fb8e131513527729a3b2be5eae94b4c61eece934c0ff95260d'
    imagePullPolicy: IfNotPresent
    livenessProbe:
      enabled: true
      failureThreshold: 200
      initialDelaySeconds: 10
      periodSeconds: 10
    logLevel: info
    maxQueryConcurrency: 5
    plugins:
      enabled: false
      enabledPlugins: []
      existingCustomSecret:
        enabled: false
        name: ''
      folder: /opt/opencost/plugin
      install:
        enabled: false
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
              - ALL
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          runAsUser: 1001
          seccompProfile:
            type: RuntimeDefault
      secretName: kubecost-plugin-secret
    readinessProbe:
      enabled: true
      failureThreshold: 200
      initialDelaySeconds: 10
      periodSeconds: 10
    resources:
      limits:
        cpu: 500m
        memory: 500Mi
      requests:
        cpu: 200m
        memory: 100Mi
  kubecostProductConfigs:
    alibabaServiceKeyName: null
    alibabaServiceKeyPassword: null
    carbonEstimates: true
    cloudAccountMapping: null
    cloudIntegrationJSON: null
    clusterName: ${CLUSTER_NAME}
    clusterProfile: null
    clusters: null
    currencyCode: USD
    customPricesEnabled: false
    defaultIdle: false
    defaultModelPricing: null
    discount: null
    gpuLabel: null
    gpuLabelValue: false
    grafanaURL: null
    hideBellIcon: false
    hideCloudIntegrationsUI: false
    hideDiagnostics: false
    hideKubecostActions: false
    hideOrphanedResources: false
    hideReservedInstances: false
    hideSpotCommander: false
    hideTeams: false
    hideUnclaimedVolumes: false
    labelMappingConfigs: null
    negotiatedDiscount: null
    savingsRecommendationsAllowLists: null
    shareTenancyCosts: false
    sharedNamespaces: null
    sharedOverhead: null
    smtp: null
    spotLabel: null
    spotLabelValue: null
    standardDiscount: null
  networkCosts:
    additionalLabels: {}
    additionalSecurityContext: {}
    affinity: {}
    annotations: {}
    config:
      destinations:
        cross-region: []
        direct-classification: []
        in-region: []
        in-zone:
          - 127.0.0.0/8
          - 169.254.0.0/16
          - 10.0.0.0/8
          - 172.16.0.0/12
          - 192.168.0.0/16
        internet: []
      services:
        amazon-web-services: true
        azure-cloud-services: true
        google-cloud-services: true
    enabled: false
    extraArgs: []
    healthCheckProbes: {}
    image:
      repository: registry.connect.redhat.com/kubecost/kubecost-network-costs@sha256
      tag: c36342ddc8b3acd2cb5bccfc4a46f9a2a26e34b9683406875ebedabf569a0806
    imagePullPolicy: IfNotPresent
    logLevel: info
    nodeSelector: {}
    podMonitor:
      additionalLabels: {}
      enabled: false
    port: 3001
    priorityClassName: ''
    prometheusScrape: false
    resources:
      limits:
        cpu: 500m
        memory: 200Mi
      requests:
        cpu: 50m
        memory: 20Mi
    service:
      annotations: {}
      labels: {}
    tolerations: []
    trafficLogging: true
    updateStrategy:
      type: RollingUpdate
  nodeSelector: {}
  oidc:
    authURL: ''
    clientID: ''
    clientSecret: ''
    discoveryURL: ''
    enabled: false
    existingCustomSecret:
      enabled: false
      name: ''
    hostedDomain: ''
    loginRedirectURL: ''
    rbac:
      enabled: false
    secretName: kubecost-oidc-secret
    skipOnlineTokenValidation: false
    useClientSecretPost: false
  persistentVolume:
    annotations: {}
    enabled: true
    labels: {}
    size: 32Gi
  pricingCsv:
    enabled: false
    location:
      URI: 's3://kc-csv-test/pricing_schema.csv'
      csvAccessCredentials: pricing-schema-access-secret
      provider: AWS
      region: us-east-1
  priority:
    enabled: false
    name: ''
  prometheus:
    alertRelabelConfigs: null
    alertmanager:
      affinity: {}
      annotations: {}
      baseURL: 'http://localhost:9093'
      configFileName: alertmanager.yml
      configFromSecret: ''
      configMapOverrideName: ''
      enabled: false
      extraArgs: {}
      extraEnv: {}
      extraSecretMounts: []
      ingress:
        annotations: {}
        enabled: false
        extraLabels: {}
        extraPaths: []
        hosts: []
        tls: []
      name: alertmanager
      nodeSelector: {}
      persistentVolume:
        accessModes:
          - ReadWriteOnce
        annotations: {}
        enabled: true
        existingClaim: ''
        mountPath: /data
        size: 2Gi
        subPath: ''
      podAnnotations: {}
      podDisruptionBudget:
        enabled: false
        maxUnavailable: 1
      podLabels: {}
      prefixURL: ''
      priorityClassName: ''
      replicaCount: 1
      resources: {}
      securityContext:
        fsGroup: 1001
        runAsGroup: 1001
        runAsNonRoot: true
        runAsUser: 1001
      service:
        annotations: {}
        clusterIP: ''
        externalIPs: []
        labels: {}
        loadBalancerIP: ''
        loadBalancerSourceRanges: []
        servicePort: 80
        sessionAffinity: None
        type: ClusterIP
      statefulSet:
        annotations: {}
        enabled: false
        headless:
          annotations: {}
          labels: {}
          servicePort: 80
        podManagementPolicy: OrderedReady
      strategy:
        rollingUpdate: null
        type: Recreate
      tolerations: []
    alertmanagerFiles:
      alertmanager.yml:
        global: {}
        receivers:
          - name: default-receiver
        route:
          group_interval: 5m
          group_wait: 10s
          receiver: default-receiver
          repeat_interval: 3h
    configmapReload:
      alertmanager:
        enabled: false
        extraArgs: {}
        extraConfigmapMounts: []
        extraVolumeDirs: []
        name: configmap-reload
        resources: {}
      prometheus:
        containerSecurityContext: {}
        enabled: false
        extraArgs: {}
        extraConfigmapMounts: []
        extraVolumeDirs: []
        name: configmap-reload
        resources: {}
    extraScrapeConfigs: |
      - job_name: kubecost
        honor_labels: true
        scrape_interval: 1m
        scrape_timeout: 60s
        metrics_path: /metrics
        scheme: http
        dns_sd_configs:
        - names:
          - 
          type: 'A'
          port: 9003
      - job_name: kubecost-networking
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
        # Scrape only the the targets matching the following metadata
          - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_instance]
            action: keep
            regex:  kubecost
          - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_name]
            action: keep
            regex:  network-costs
      - job_name: kubecost-aggregator
        scrape_interval: 1m
        scrape_timeout: 60s
        metrics_path: /metrics
        scheme: http
        dns_sd_configs:
        - names:
          - 
          type: 'A'
          port: 9008
          port: 9004
      ## Enables scraping of NVIDIA GPU metrics via dcgm-exporter. Scrapes all
      ## endpoints which contain "dcgm-exporter" in labels "app",
      ## "app.kubernetes.io/component", or "app.kubernetes.io/name" with a case
      ## insensitive match. The label must be present on the K8s service endpoints and not just pods.
      ## Refs:
      ## https://github.com/NVIDIA/gpu-operator/blob/d4316a415bbd684ce8416a88042305fc1a093aa4/assets/state-dcgm-exporter/0600_service.yaml#L7
      ## https://github.com/NVIDIA/dcgm-exporter/blob/54fd1ca137c66511a87a720390613680b9bdabdd/deployment/templates/service.yaml#L23
      - job_name: kubecost-dcgm-exporter
        kubernetes_sd_configs:
          - role: endpoints
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_label_app, __meta_kubernetes_pod_label_app_kubernetes_io_component, __meta_kubernetes_pod_label_app_kubernetes_io_name]
            action: keep
            regex: (?i)(.*dcgm-exporter.*|.*dcgm-exporter.*|.*dcgm-exporter.*)
    imagePullSecrets: null
    networkPolicy:
      enabled: false
    rbac:
      create: true
    server:
      affinity: {}
      alertmanagers: []
      annotations: {}
      baseURL: ''
      configMapOverrideName: ''
      configPath: /etc/config/prometheus.yml
      containerSecurityContext: {}
      emptyDir:
        sizeLimit: ''
      enabled: true
      env: []
      extraArgs:
        query.max-concurrency: 1
        query.max-samples: 100000000
      extraConfigmapMounts: []
      extraFlags:
        - web.enable-lifecycle
      extraHostPathMounts: []
      extraInitContainers: []
      extraSecretMounts: []
      extraVolumeMounts: []
      extraVolumes: []
      global:
        evaluation_interval: 1m
        external_labels:
          cluster_id: ${CLUSTER_NAME}
        scrape_interval: 1m
        scrape_timeout: 60s
      ingress:
        annotations: {}
        enabled: false
        extraLabels: {}
        extraPaths: []
        hosts: []
        pathType: Prefix
        tls: []
      livenessProbeFailureThreshold: 3
      livenessProbeInitialDelay: 5
      livenessProbeSuccessThreshold: 1
      livenessProbeTimeout: 3
      name: server
      nodeSelector: {}
      persistentVolume:
        accessModes:
          - ReadWriteOnce
        annotations: {}
        enabled: true
        existingClaim: ''
        mountPath: /data
        size: 32Gi
        subPath: ''
      podAnnotations: {}
      podDisruptionBudget:
        enabled: false
        maxUnavailable: 1
      podLabels: {}
      prefixURL: ''
      priorityClassName: ''
      readinessProbeFailureThreshold: 3
      readinessProbeInitialDelay: 5
      readinessProbeSuccessThreshold: 1
      readinessProbeTimeout: 3
      remoteRead: {}
      remoteWrite: {}
      replicaCount: 1
      resources: {}
      retention: 97h
      securityContext: {}
      service:
        annotations: {}
        clusterIP: ''
        externalIPs: []
        gRPC:
          enabled: false
          servicePort: 10901
        labels: {}
        loadBalancerIP: ''
        loadBalancerSourceRanges: []
        servicePort: 80
        sessionAffinity: None
        statefulsetReplica:
          enabled: false
          replica: 0
        type: ClusterIP
      sidecarContainers: null
      statefulSet:
        annotations: {}
        enabled: false
        headless:
          annotations: {}
          labels: {}
          servicePort: 80
        labels: {}
        podManagementPolicy: OrderedReady
      strategy:
        rollingUpdate: null
        type: Recreate
      terminationGracePeriodSeconds: 300
      tolerations: []
      verticalAutoscaler:
        enabled: false
    serverFiles:
      alerting_rules.yml: {}
      prometheus.yml:
        rule_files:
          - /etc/config/recording_rules.yml
          - /etc/config/alerting_rules.yml
        scrape_configs:
          - job_name: prometheus
            static_configs:
              - targets:
                  - 'localhost:9090'
          - bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
            job_name: kubernetes-nodes-cadvisor
            kubernetes_sd_configs:
              - role: node
            metric_relabel_configs:
              - action: keep
                regex: (container_cpu_usage_seconds_total|container_memory_working_set_bytes|container_network_receive_errors_total|container_network_transmit_errors_total|container_network_receive_packets_dropped_total|container_network_transmit_packets_dropped_total|container_memory_usage_bytes|container_cpu_cfs_throttled_periods_total|container_cpu_cfs_periods_total|container_fs_usage_bytes|container_fs_limit_bytes|container_cpu_cfs_periods_total|container_fs_inodes_free|container_fs_inodes_total|container_fs_usage_bytes|container_fs_limit_bytes|container_cpu_cfs_throttled_periods_total|container_cpu_cfs_periods_total|container_network_receive_bytes_total|container_network_transmit_bytes_total|container_fs_inodes_free|container_fs_inodes_total|container_fs_usage_bytes|container_fs_limit_bytes|container_spec_cpu_shares|container_spec_memory_limit_bytes|container_network_receive_bytes_total|container_network_transmit_bytes_total|container_fs_reads_bytes_total|container_network_receive_bytes_total|container_fs_writes_bytes_total|container_fs_reads_bytes_total|cadvisor_version_info|kubecost_pv_info)
                source_labels:
                  - __name__
              - action: replace
                regex: (.+)
                source_labels:
                  - container
                target_label: container_name
              - action: replace
                regex: (.+)
                source_labels:
                  - pod
                target_label: pod_name
            relabel_configs:
              - action: labelmap
                regex: __meta_kubernetes_node_label_(.+)
              - replacement: 'kubernetes.default.svc:443'
                target_label: __address__
              - regex: (.+)
                replacement: /api/v1/nodes/$1/proxy/metrics/cadvisor
                source_labels:
                  - __meta_kubernetes_node_name
                target_label: __metrics_path__
            scheme: https
            tls_config:
              ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
              insecure_skip_verify: true
          - bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
            job_name: kubernetes-nodes
            kubernetes_sd_configs:
              - role: node
            metric_relabel_configs:
              - action: keep
                regex: (kubelet_volume_stats_used_bytes)
                source_labels:
                  - __name__
            relabel_configs:
              - action: labelmap
                regex: __meta_kubernetes_node_label_(.+)
              - replacement: 'kubernetes.default.svc:443'
                target_label: __address__
              - regex: (.+)
                replacement: /api/v1/nodes/$1/proxy/metrics
                source_labels:
                  - __meta_kubernetes_node_name
                target_label: __metrics_path__
            scheme: https
            tls_config:
              ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
              insecure_skip_verify: true
          - job_name: kubernetes-service-endpoints
            kubernetes_sd_configs:
              - role: endpoints
            metric_relabel_configs:
              - action: keep
                regex: (container_cpu_allocation|container_cpu_usage_seconds_total|container_fs_limit_bytes|container_fs_writes_bytes_total|container_gpu_allocation|container_memory_allocation_bytes|container_memory_usage_bytes|container_memory_working_set_bytes|container_network_receive_bytes_total|container_network_transmit_bytes_total|DCGM_FI_DEV_GPU_UTIL|deployment_match_labels|kube_daemonset_status_desired_number_scheduled|kube_daemonset_status_number_ready|kube_deployment_spec_replicas|kube_deployment_status_replicas|kube_deployment_status_replicas_available|kube_job_status_failed|kube_namespace_annotations|kube_namespace_labels|kube_node_info|kube_node_labels|kube_node_status_allocatable|kube_node_status_allocatable_cpu_cores|kube_node_status_allocatable_memory_bytes|kube_node_status_capacity|kube_node_status_capacity_cpu_cores|kube_node_status_capacity_memory_bytes|kube_node_status_condition|kube_persistentvolume_capacity_bytes|kube_persistentvolume_status_phase|kube_persistentvolumeclaim_info|kube_persistentvolumeclaim_resource_requests_storage_bytes|kube_pod_container_info|kube_pod_container_resource_limits|kube_pod_container_resource_limits_cpu_cores|kube_pod_container_resource_limits_memory_bytes|kube_pod_container_resource_requests|kube_pod_container_resource_requests_cpu_cores|kube_pod_container_resource_requests_memory_bytes|kube_pod_container_status_restarts_total|kube_pod_container_status_running|kube_pod_container_status_terminated_reason|kube_pod_labels|kube_pod_owner|kube_pod_status_phase|kube_replicaset_owner|kube_statefulset_replicas|kube_statefulset_status_replicas|kubecost_cluster_info|kubecost_cluster_management_cost|kubecost_cluster_memory_working_set_bytes|kubecost_load_balancer_cost|kubecost_network_internet_egress_cost|kubecost_network_region_egress_cost|kubecost_network_zone_egress_cost|kubecost_node_is_spot|kubecost_pod_network_egress_bytes_total|node_cpu_hourly_cost|node_cpu_seconds_total|node_disk_reads_completed|node_disk_reads_completed_total|node_disk_writes_completed|node_disk_writes_completed_total|node_filesystem_device_error|node_gpu_count|node_gpu_hourly_cost|node_memory_Buffers_bytes|node_memory_Cached_bytes|node_memory_MemAvailable_bytes|node_memory_MemFree_bytes|node_memory_MemTotal_bytes|node_network_transmit_bytes_total|node_ram_hourly_cost|node_total_hourly_cost|pod_pvc_allocation|pv_hourly_cost|service_selector_labels|statefulSet_match_labels|kubecost_pv_info|up)
                source_labels:
                  - __name__
            relabel_configs:
              - action: keep
                regex: true
                source_labels:
                  - __meta_kubernetes_service_annotation_prometheus_io_scrape
              - action: keep
                regex: (.*node-exporter|kubecost-network-costs)
                source_labels:
                  - __meta_kubernetes_endpoints_name
              - action: replace
                regex: (https?)
                source_labels:
                  - __meta_kubernetes_service_annotation_prometheus_io_scheme
                target_label: __scheme__
              - action: replace
                regex: (.+)
                source_labels:
                  - __meta_kubernetes_service_annotation_prometheus_io_path
                target_label: __metrics_path__
              - action: replace
                regex: '([^:]+)(?::\d+)?;(\d+)'
                replacement: '$1:$2'
                source_labels:
                  - __address__
                  - __meta_kubernetes_service_annotation_prometheus_io_port
                target_label: __address__
              - action: labelmap
                regex: __meta_kubernetes_service_label_(.+)
              - action: replace
                source_labels:
                  - __meta_kubernetes_namespace
                target_label: kubernetes_namespace
              - action: replace
                source_labels:
                  - __meta_kubernetes_service_name
                target_label: kubernetes_name
              - action: replace
                source_labels:
                  - __meta_kubernetes_pod_node_name
                target_label: kubernetes_node
      recording_rules.yml: {}
      rules:
        groups:
          - name: CPU
            rules:
              - expr: 'sum(rate(container_cpu_usage_seconds_total{container!=""}[5m]))'
                record: 'cluster:cpu_usage:rate5m'
              - expr: 'rate(container_cpu_usage_seconds_total{container!=""}[5m])'
                record: 'cluster:cpu_usage_nosum:rate5m'
              - expr: 'avg(irate(container_cpu_usage_seconds_total{container!="POD", container!=""}[5m])) by (container,pod,namespace)'
                record: kubecost_container_cpu_usage_irate
              - expr: 'sum(container_memory_working_set_bytes{container!="POD",container!=""}) by (container,pod,namespace)'
                record: kubecost_container_memory_working_set_bytes
              - expr: 'sum(container_memory_working_set_bytes{container!="POD",container!=""})'
                record: kubecost_cluster_memory_working_set_bytes
          - name: Savings
            rules:
              - expr: 'sum(avg(kube_pod_owner{owner_kind!="DaemonSet"}) by (pod) * sum(container_cpu_allocation) by (pod))'
                labels:
                  daemonset: 'false'
                record: kubecost_savings_cpu_allocation
              - expr: 'sum(avg(kube_pod_owner{owner_kind="DaemonSet"}) by (pod) * sum(container_cpu_allocation) by (pod)) / sum(kube_node_info)'
                labels:
                  daemonset: 'true'
                record: kubecost_savings_cpu_allocation
              - expr: 'sum(avg(kube_pod_owner{owner_kind!="DaemonSet"}) by (pod) * sum(container_memory_allocation_bytes) by (pod))'
                labels:
                  daemonset: 'false'
                record: kubecost_savings_memory_allocation_bytes
              - expr: 'sum(avg(kube_pod_owner{owner_kind="DaemonSet"}) by (pod) * sum(container_memory_allocation_bytes) by (pod)) / sum(kube_node_info)'
                labels:
                  daemonset: 'true'
                record: kubecost_savings_memory_allocation_bytes
    serviceAccounts:
      alertmanager:
        create: true
        name: null
      nodeExporter:
        create: true
        name: null
      server:
        annotations: {}
        create: true
        name: null
  prometheusRule:
    additionalLabels: {}
    enabled: true
  reporting:
    errorReporting: true
    logCollection: true
    productAnalytics: true
    valuesReporting: true
  saml:
    enabled: false
    rbac:
      enabled: false
  service:
    annotations: {}
    labels: {}
    nodePort: {}
    port: 9090
    sessionAffinity:
      enabled: false
      timeoutSeconds: 10800
    targetPort: 9090
    type: ClusterIP
  serviceAccount:
    annotations: {}
    create: true
  serviceMonitor:
    additionalLabels: {}
    aggregatorMetrics:
      additionalLabels: {}
      enabled: false
      interval: 1m
      metricRelabelings: []
      relabelings:
        - action: replace
          sourceLabels:
            - __meta_kubernetes_namespace
          targetLabel: namespace
      scrapeTimeout: 10s
    enabled: true
    interval: 1m
    metricRelabelings: []
    networkCosts:
      additionalLabels: {}
      enabled: false
      interval: 1m
      metricRelabelings: []
      relabelings: []
      scrapeTimeout: 10s
    relabelings: []
    scrapeTimeout: 10s
  sigV4Proxy:
    extraEnv: null
    host: aps-workspaces.us-west-2.amazonaws.com
    image: null
    imagePullPolicy: IfNotPresent
    name: aps
    port: 8005
    region: us-west-2
    resources: {}
  supportNFS: false
  systemProxy:
    enabled: false
    httpProxyUrl: ''
    httpsProxyUrl: ''
    noProxy: ''
  tolerations: []
  topologySpreadConstraints: []
  upgrade:
    toV2: false
EOF
        if [[ $? != 0 ]]; then
            log-error "Unable to create Kubecost operand"
            exit 1
        else
            log-info "Kubecost operand created"
        fi

        # Wait for operand to be ready
        count=0;
        while [[ $(${BIN_DIR}/oc get CostAnalyzer -n ${NAMESPACE} kubecost -o json | jq -r '.status.conditions[] | select(.type=="Ready").status') != "True" ]]; do
            log-info "Waiting for Kubecost operand to be ready. Waited $count minutes. Will wait up to 15 minutes"
            sleep 60
            count=$(( $count + 1 ))
            if (( $count > 15)); then    # Timeout set to 15 minutes
                log-error "Timeout waiting for Kubecost operand to be ready"
                exit 1
            fi
        done
    else
        log-info "License not accepted. Kubecost operand not created"
    fi
else
    log-info "Kubecost operand already in place"
fi

# Create route
log-info "Creating route"
${BIN_DIR}/oc get route -n ${NAMESPACE} kubecost-ui > /dev/null 2> /dev/null
if [[ $? != 0 ]] && [[ $LICENSE == "accept" ]]; then
    log-info "Creating Kubecost route"
    cat << EOF | ${BIN_DIR}/oc apply -f -
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: kubecost-ui
  namespace: ${NAMESPACE}
spec:
  path: /
  to:
    name: kubecost-cost-analyzer
    weight: 100
    kind: Service
  host: ''
  port:
    targetPort: tcp-frontend
  alternateBackends: []
EOF
    if [[ $? != 0 ]]; then
        log-error "Unable to create Kubecost route"
        exit 1
    else
        log-info "Created Kubecost route"
    fi
else
    log-info "Kubecost route already exists"
fi

log-info "Script completed"