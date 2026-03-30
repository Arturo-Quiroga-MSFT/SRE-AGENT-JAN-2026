// ──────────────────────────────────────────────────────────────
// resources.bicep — AKS Private VNet Test Bed
//
// Resources created:
//   - User-assigned Managed Identity (AKS control plane)
//   - VNet with AKS subnet + private-endpoint subnet
//   - Log Analytics Workspace (Container Insights destination)
//   - Azure Container Registry (Basic, RBAC-only)
//   - Private AKS cluster (private API server, Azure CNI Overlay)
//   - Role assignments: Network Contributor, AcrPull
//   - Azure Monitor metric alerts (CPU, memory)
//   - Log Analytics scheduled query alert (pod restarts / CrashLoopBackOff)
// ──────────────────────────────────────────────────────────────

param location string
param tags object
param resourceToken string

var abbrs = loadJsonContent('./abbreviations.json')

// ──────────────────────────────────────────────────────────────
// Managed Identity — AKS control plane
// Using user-assigned identity is best practice: it persists if
// the cluster is deleted and re-created.
// ──────────────────────────────────────────────────────────────
resource aksIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${abbrs.managedIdentities}aks-${resourceToken}'
  location: location
  tags: tags
}

// ──────────────────────────────────────────────────────────────
// Virtual Network
//   snet-aks  10.42.0.0/22  — 1 022 IPs for nodes
//   snet-pe   10.42.8.0/27  — 32 IPs for future private endpoints
// ──────────────────────────────────────────────────────────────
resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: '${abbrs.virtualNetworks}${resourceToken}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: ['10.42.0.0/16']
    }
    subnets: [
      {
        name: 'snet-aks'
        properties: {
          addressPrefix: '10.42.0.0/22'
        }
      }
      {
        // Reserved for ACR / Key Vault private endpoints when needed
        name: 'snet-pe'
        properties: {
          addressPrefix: '10.42.8.0/27'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// AKS control-plane identity needs Network Contributor on the VNet
// so it can manage load balancers and NIC attachments.
resource aksNetworkContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vnet.id, aksIdentity.id, 'NetworkContributor')
  scope: vnet
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '4d97b98b-1d4f-4787-a291-c67834d212e7' // Network Contributor
    )
    principalId: aksIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ──────────────────────────────────────────────────────────────
// Log Analytics Workspace
// Container Insights (omsagent addon) writes all cluster telemetry
// here: KubePodInventory, KubeNodeInventory, ContainerLog, Perf.
// This is also what the SRE Agent queries via Log Analytics MCP/KQL.
// ──────────────────────────────────────────────────────────────
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${abbrs.logAnalyticsWorkspaces}${resourceToken}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// ──────────────────────────────────────────────────────────────
// Azure Container Registry
// Basic SKU — no private endpoint (nodes pull over outbound LB).
// Admin user disabled; AKS kubelet identity gets AcrPull below.
// ──────────────────────────────────────────────────────────────
resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  // 'acrsre' prefix (6 chars) ensures static analysis confirms min-length 5 is met.
  // resourceToken adds 13 more chars at runtime (uniqueString output is always 13).
  name: 'acrsre${resourceToken}'
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    anonymousPullEnabled: false
  }
}

// ──────────────────────────────────────────────────────────────
// Private AKS Cluster
//
// Key settings that prove the SRE Agent design pattern:
//   enablePrivateCluster: true  → API server has no public endpoint
//   enablePrivateClusterPublicFQDN: false → fully private
//   outboundType: loadBalancer  → nodes can reach internet (ACR pull)
//   omsagent addon enabled      → Container Insights → Log Analytics
//
// The SRE Agent manages this cluster via ARM/Azure CLI — it never
// needs to be inside the VNet because ARM reaches the AKS control
// plane through Azure Private Link backbone.
// ──────────────────────────────────────────────────────────────
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-02-01' = {
  name: '${abbrs.managedClusters}${resourceToken}'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${aksIdentity.id}': {}
    }
  }
  properties: {
    dnsPrefix: 'sre-${resourceToken}'
    agentPoolProfiles: [
      {
        name: 'system'
        count: 2
        vmSize: 'Standard_D2s_v3'
        osType: 'Linux'
        osDiskSizeGB: 64
        osDiskType: 'Managed'
        mode: 'System'
        vnetSubnetID: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-aks')
        type: 'VirtualMachineScaleSets'
        enableAutoScaling: true
        minCount: 1
        maxCount: 3
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'      // Azure CNI Overlay — pods don't consume node subnet IPs
      podCidr: '192.168.0.0/16'        // Overlay pod address space (never routed in VNet)
      serviceCidr: '172.16.0.0/16'
      dnsServiceIP: '172.16.0.10'
      outboundType: 'loadBalancer'     // Standard outbound LB for internet egress
    }
    apiServerAccessProfile: {
      enablePrivateCluster: true
      enablePrivateClusterPublicFQDN: false
    }
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalytics.id
        }
      }
    }
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
  }
  dependsOn: [aksNetworkContributor]
}

// Grant the AKS kubelet identity AcrPull on the registry.
// The kubelet identity is auto-created by AKS and is separate from
// the control-plane identity above.
resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, aksCluster.id, 'AcrPull')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '7f951dda-4ed3-4680-a7ca-43fe172d538d' // AcrPull
    )
    principalId: aksCluster.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}

// ──────────────────────────────────────────────────────────────
// Azure Monitor Alerts — test bed incident triggers
//
// These three alerts let you validate the SRE Agent end-to-end:
//   1. Pod restart alert → simulates CrashLoopBackOff
//   2. Node CPU alert    → simulates resource pressure
//   3. No ready pods     → simulates full service outage
//
// Fire them by deploying the crashing workload in k8s/grocery-api-crash.yaml
// or by running the load generator.
// ──────────────────────────────────────────────────────────────

// Alert 1: Pod restart count (log-based, Container Insights)
resource podRestartAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-pod-restarts-${resourceToken}'
  location: location
  tags: tags
  properties: {
    description: 'Grocery API pods restarted more than 3 times in 15 minutes — likely CrashLoopBackOff'
    severity: 1
    enabled: true
    scopes: [logAnalytics.id]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          query: '''
            KubePodInventory
            | where Namespace == "grocery"
            | where isnotempty(PodRestartCount)
            | summarize MaxRestarts = max(toint(PodRestartCount)) by Name, Namespace
            | where MaxRestarts > 3
          '''
          timeAggregation: 'Maximum'
          threshold: 3
          operator: 'GreaterThan'
          metricMeasureColumn: 'MaxRestarts'
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: []
    }
  }
}

// Alert 2: Node CPU > 80% for 5 minutes (metric alert)
resource highCpuAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-node-cpu-${resourceToken}'
  location: 'global'
  tags: tags
  properties: {
    description: 'AKS node CPU utilization exceeds 80% — investigate workload pressure'
    severity: 2
    enabled: true
    scopes: [aksCluster.id]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighNodeCPU'
          metricName: 'node_cpu_usage_percentage'
          metricNamespace: 'Microsoft.ContainerService/managedClusters'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    actions: []
  }
}

// Alert 3: No ready pods in grocery namespace (log-based)
resource noReadyPodsAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-no-ready-pods-${resourceToken}'
  location: location
  tags: tags
  properties: {
    description: 'No ready pods in the grocery namespace — potential full service outage'
    severity: 0 // Critical
    enabled: true
    scopes: [logAnalytics.id]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          query: '''
            KubePodInventory
            | where Namespace == "grocery"
            | where PodStatus == "Running"
            | summarize ReadyPods = count() by bin(TimeGenerated, 5m)
          '''
          timeAggregation: 'Minimum'
          threshold: 1
          operator: 'LessThan'
          metricMeasureColumn: 'ReadyPods'
          failingPeriods: {
            numberOfEvaluationPeriods: 2
            minFailingPeriodsToAlert: 2
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: []
    }
  }
}

// ──────────────────────────────────────────────────────────────
// Outputs
// ──────────────────────────────────────────────────────────────
output aksClusterName string = aksCluster.name
output aksClusterId string = aksCluster.id
output acrLoginServer string = acr.properties.loginServer
output acrName string = acr.name
output logAnalyticsWorkspaceId string = logAnalytics.properties.customerId
output logAnalyticsResourceId string = logAnalytics.id
output vnetName string = vnet.name
output aksIdentityPrincipalId string = aksIdentity.properties.principalId
