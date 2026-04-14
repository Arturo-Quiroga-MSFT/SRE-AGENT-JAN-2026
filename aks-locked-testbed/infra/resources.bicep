// ──────────────────────────────────────────────────────────────
// resources.bicep — AKS Locked-Down (Zoya-Style) Test Bed
//
// This variant mirrors the Zafin partner pattern exactly:
//   - Public API server endpoint (NOT fully private)
//   - Authorized IP ranges restrict who can reach the API server
//   - Azure RBAC enabled, local accounts disabled
//   - Standard SKU tier
//   - 4 roles assigned to SRE Agent MI:
//       1. Reader (built-in)
//       2. AKS ReadOnly Command Invoke (custom)
//       3. Log Analytics Reader (built-in)
//       4. Azure Kubernetes Service RBAC Reader (built-in)
//   - Container Insights enabled → Log Analytics
//
// Source: partner-context/Zafin-AKSDetails/
// ──────────────────────────────────────────────────────────────

param location string
param tags object
param resourceToken string

@description('Object ID of the SRE Agent managed identity')
param sreAgentPrincipalId string = ''

var abbrs = loadJsonContent('./abbreviations.json')

// ──────────────────────────────────────────────────────────────
// Managed Identity — AKS control plane
// ──────────────────────────────────────────────────────────────
resource aksIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${abbrs.managedIdentities}aks-${resourceToken}'
  location: location
  tags: tags
}

// ──────────────────────────────────────────────────────────────
// Virtual Network
//   snet-aks  10.42.0.0/22  — nodes
//   snet-pe   10.42.8.0/27  — future private endpoints
//
// Note: Zafin does NOT use an NSG on the AKS subnet.
// Security is enforced via authorized IP ranges on the API server
// + Azure RBAC + disabled local accounts.
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
          serviceEndpoints: [
            { service: 'Microsoft.Storage' }
            { service: 'Microsoft.KeyVault' }
          ]
        }
      }
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: '10.42.8.0/27'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// AKS identity needs Network Contributor on the VNet
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
// ──────────────────────────────────────────────────────────────
resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
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
// AKS Cluster — Public endpoint with authorized IP ranges
//
// Matches Zafin's aksCluster.tf pattern:
//   enablePrivateCluster: false  → API server IS publicly reachable
//   authorizedIPRanges: [...]    → only listed CIDRs can call the API
//   disableLocalAccounts: true   → no local/certificate auth
//   aadProfile + Azure RBAC      → all access via Entra ID
//   sku.tier: Standard           → production-grade uptime SLA
//   networkPlugin: azure         → Azure CNI (matches Zafin)
//   networkPolicy: azure         → Azure network policy
//
// The SRE Agent accesses via ARM invoke command (az aks command invoke)
// which goes through Azure backbone — unaffected by IP whitelisting.
// ──────────────────────────────────────────────────────────────
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-02-01' = {
  name: '${abbrs.managedClusters}${resourceToken}'
  location: location
  tags: tags
  sku: {
    name: 'Base'
    tier: 'Standard'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${aksIdentity.id}': {}
    }
  }
  properties: {
    dnsPrefix: 'sre-${resourceToken}'
    disableLocalAccounts: true
    aadProfile: {
      managed: true
      enableAzureRBAC: true
    }
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
      networkPolicy: 'azure'
      loadBalancerSku: 'standard'
      serviceCidr: '172.16.0.0/16'
      dnsServiceIP: '172.16.0.10'
      outboundType: 'loadBalancer'
    }
    apiServerAccessProfile: {
      // PUBLIC endpoint with IP restrictions (Zafin pattern)
      enablePrivateCluster: false
      // Allow Azure Cloud Shell, Azure Portal, and common Microsoft ranges.
      // Add your own IP / the SRE Agent's outbound IP after deployment:
      //   az aks update -g <rg> -n <aks> --api-server-authorized-ip-ranges "<ip>/32"
      authorizedIPRanges: [
        // Azure Portal and Cloud Shell service tag (not a CIDR — AKS resolves it)
        // Placeholder: replace with your actual IPs after deployment.
        // You can also add IPs post-deployment with:
        //   az aks update --api-server-authorized-ip-ranges "x.x.x.x/32,y.y.y.y/32"
      ]
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

// Grant AKS kubelet identity AcrPull
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
// Custom RBAC Role — AKS ReadOnly Command Invoke
//
// Exact match of Zoya's custom role from SRE_MI_Roles.json.
// Allows az aks command invoke with no write permissions.
// This is the only custom role; the rest are built-in.
// ──────────────────────────────────────────────────────────────
resource aksReadOnlyCommandInvoke 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(subscription().id, 'AKS-ReadOnly-Command-Invoke-${resourceToken}')
  properties: {
    roleName: 'AKS ReadOnly Command Invoke (${resourceToken})'
    description: 'Allows az aks command invoke with no write permissions'
    type: 'CustomRole'
    permissions: [
      {
        actions: [
          'Microsoft.ContainerService/managedClusters/read'
          'Microsoft.ContainerService/managedClusters/listClusterUserCredential/action'
          'Microsoft.ContainerService/managedClusters/runcommand/action'
          'Microsoft.ContainerService/managedClusters/commandResults/read'
        ]
        notActions: []
        dataActions: []
        notDataActions: []
      }
    ]
    assignableScopes: [
      resourceGroup().id
    ]
  }
}

// ──────────────────────────────────────────────────────────────
// SRE Agent Role Assignments (conditional on principalId)
// ──────────────────────────────────────────────────────────────

// 1. AKS ReadOnly Command Invoke (custom) on the AKS cluster
resource sreAgentCommandInvokeAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(sreAgentPrincipalId)) {
  name: guid(aksCluster.id, sreAgentPrincipalId, aksReadOnlyCommandInvoke.id)
  scope: aksCluster
  properties: {
    roleDefinitionId: aksReadOnlyCommandInvoke.id
    principalId: sreAgentPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// 2. Reader on the resource group (for resource discovery)
resource sreAgentReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(sreAgentPrincipalId)) {
  name: guid(resourceGroup().id, sreAgentPrincipalId, 'Reader')
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'acdd72a7-3385-48ef-bd42-f606fba81ae7' // Reader
    )
    principalId: sreAgentPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// 3. Log Analytics Reader on the workspace
resource sreAgentLogReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(sreAgentPrincipalId)) {
  name: guid(logAnalytics.id, sreAgentPrincipalId, 'LogAnalyticsReader')
  scope: logAnalytics
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '73c42c96-874c-492b-b04d-ab87d138a893' // Log Analytics Reader
    )
    principalId: sreAgentPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// 4. Azure Kubernetes Service RBAC Reader on the AKS cluster
//    Built-in role 7f6c6a51-bcf8-42ba-9220-52d62157d7db
//    Provides read-only dataActions for pods, deployments, events, etc.
resource sreAgentAksRbacReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(sreAgentPrincipalId)) {
  name: guid(aksCluster.id, sreAgentPrincipalId, 'AKS-RBAC-Reader')
  scope: aksCluster
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '7f6c6a51-bcf8-42ba-9220-52d62157d7db' // Azure Kubernetes Service RBAC Reader
    )
    principalId: sreAgentPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ──────────────────────────────────────────────────────────────
// Azure Monitor Alerts
// ──────────────────────────────────────────────────────────────

resource podRestartAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-pod-restarts-${resourceToken}'
  location: location
  tags: tags
  properties: {
    description: 'Pods restarted more than 3 times in 15 minutes — likely CrashLoopBackOff'
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
  }
}

resource nodeCpuAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-node-cpu-${resourceToken}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Node CPU utilization exceeded 85% for 5 minutes'
    severity: 2
    enabled: true
    scopes: [aksCluster.id]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighCPU'
          metricName: 'node_cpu_usage_percentage'
          metricNamespace: 'Microsoft.ContainerService/managedClusters'
          operator: 'GreaterThan'
          threshold: 85
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
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
output sreAgentCustomRoleId string = aksReadOnlyCommandInvoke.id
