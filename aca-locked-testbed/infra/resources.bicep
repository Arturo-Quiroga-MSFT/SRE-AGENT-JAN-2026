// ──────────────────────────────────────────────────────────────
// resources.bicep — ACA Locked-Down (Internal VNet) Test Bed
//
// This testbed provisions a fully locked-down ACA environment:
//   - VNet-injected Container Apps Environment (internal only)
//   - No public ingress — apps reachable only within the VNet
//   - Managed identity auth (no admin credentials)
//   - Log Analytics for container app logs + system logs
//   - ACR with RBAC-only auth (admin disabled)
//   - NSG on the ACA infrastructure subnet
//   - SRE Agent roles:
//       1. Reader (built-in) — RG scope
//       2. Contributor on ACA apps — for restart, revision mgmt
//       3. Log Analytics Reader — KQL queries
//
// Purpose: Prove SRE Agent can manage locked-down ACA apps
//          through ARM without needing VNet connectivity.
// ──────────────────────────────────────────────────────────────

param location string
param tags object
param resourceToken string

@description('Object ID of the SRE Agent managed identity')
param sreAgentPrincipalId string = ''

var abbrs = loadJsonContent('./abbreviations.json')

// ──────────────────────────────────────────────────────────────
// Virtual Network
//   snet-aca    10.44.0.0/21  — Container Apps infrastructure
//                               (ACA requires minimum /23, /21 gives room)
//   snet-pe     10.44.8.0/27  — Private endpoints (ACR, etc.)
//
// The ACA infrastructure subnet is delegated to
// Microsoft.App/environments — ACA manages the IPs.
// ──────────────────────────────────────────────────────────────
resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: '${abbrs.virtualNetworks}${resourceToken}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: ['10.44.0.0/16']
    }
    subnets: [
      {
        name: 'snet-aca'
        properties: {
          addressPrefix: '10.44.0.0/21'
          delegations: [
            {
              name: 'aca-delegation'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
          networkSecurityGroup: {
            id: acaNsg.id
          }
        }
      }
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: '10.44.8.0/27'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
  dependsOn: [acaNsg]
}

// ──────────────────────────────────────────────────────────────
// NSG for ACA infrastructure subnet
// Allows required ACA platform traffic and denies everything else
// inbound from public internet.
// ──────────────────────────────────────────────────────────────
resource acaNsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: '${abbrs.networkSecurityGroups}aca-${resourceToken}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowVnetInbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '*'
        }
      }
      {
        name: 'AllowAzureLoadBalancer'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// ──────────────────────────────────────────────────────────────
// Log Analytics Workspace
// Container Apps system + app logs land here.
// SRE Agent queries these via KQL.
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
// Basic SKU, no admin user, RBAC-only auth.
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
// Container Apps Environment — INTERNAL ONLY (VNet-injected)
//
// Key locked-down settings:
//   vnetConfiguration.internal: true  → no public endpoint
//   infrastructureSubnetId            → apps run inside the VNet
//   workloadProfiles: Consumption     → serverless, cost-effective
//
// The ACA environment has NO public IP. All traffic must come
// from within the VNet or through ARM management operations.
// The SRE Agent manages through ARM — it never enters the VNet.
// ──────────────────────────────────────────────────────────────
resource acaEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: '${abbrs.containerAppsEnvironments}${resourceToken}'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    vnetConfiguration: {
      internal: true
      infrastructureSubnetId: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-aca')
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    zoneRedundant: false
  }
}

// ──────────────────────────────────────────────────────────────
// User-Assigned Managed Identity for the container apps
// Used instead of admin credentials for ACR pull.
// ──────────────────────────────────────────────────────────────
resource acaIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${abbrs.managedIdentities}aca-${resourceToken}'
  location: location
  tags: tags
}

// Grant ACA identity AcrPull on the registry
resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, acaIdentity.id, 'AcrPull')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '7f951dda-4ed3-4680-a7ca-43fe172d538d' // AcrPull
    )
    principalId: acaIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ──────────────────────────────────────────────────────────────
// API Container App — internal only
//
// Uses the hello-world image initially. Post-provision scripts
// replace with the grocery-api image from ACR.
// Ingress is internal — only reachable within the VNet.
// ──────────────────────────────────────────────────────────────
resource apiApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${abbrs.containerApps}api-${resourceToken}'
  location: location
  tags: union(tags, { 'azd-service-name': 'api' })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${acaIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: acaEnvironment.id
    workloadProfileName: 'Consumption'
    configuration: {
      ingress: {
        external: false
        targetPort: 3100
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      registries: [
        {
          server: acr.properties.loginServer
          identity: acaIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'api'
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          env: [
            {
              name: 'PORT'
              value: '3100'
            }
            {
              name: 'SUPPLIER_RATE_LIMIT'
              value: '5'
            }
          ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
      }
    }
  }
}

// ──────────────────────────────────────────────────────────────
// Web Container App — internal only
// ──────────────────────────────────────────────────────────────
resource webApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${abbrs.containerApps}web-${resourceToken}'
  location: location
  tags: union(tags, { 'azd-service-name': 'web' })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${acaIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: acaEnvironment.id
    workloadProfileName: 'Consumption'
    configuration: {
      ingress: {
        external: false
        targetPort: 3000
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      registries: [
        {
          server: acr.properties.loginServer
          identity: acaIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'web'
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          env: [
            {
              name: 'PORT'
              value: '3000'
            }
            {
              name: 'API_URL'
              value: 'https://${apiApp.properties.configuration.ingress.fqdn}'
            }
          ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
      }
    }
  }
}

// ──────────────────────────────────────────────────────────────
// SRE Agent Role Assignments (conditional on principalId)
//
// ACA management is purely ARM-based. The SRE Agent needs:
//   1. Reader — discover resources, list apps, show revisions
//   2. Contributor on the ACA apps — restart, revision management,
//      replica listing, console exec (all ARM operations)
//   3. Log Analytics Reader — KQL queries on container logs
//
// Note: Unlike AKS, there is no separate data-plane RBAC layer.
// ACA authorization is entirely ARM-based. No custom roles needed.
// ──────────────────────────────────────────────────────────────

// 1. Reader on the resource group
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

// 2. Contributor scoped to the ACA environment (covers app management)
resource sreAgentAcaContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(sreAgentPrincipalId)) {
  name: guid(acaEnvironment.id, sreAgentPrincipalId, 'Contributor')
  scope: acaEnvironment
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'b24988ac-6180-42a0-ab88-20f7382dd24c' // Contributor
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

// ──────────────────────────────────────────────────────────────
// Azure Monitor Alerts
//
// NOTE: Scheduled query rules are NOT created here because
// Log Analytics validates KQL at creation time. The tables
// (ContainerAppConsoleLogs, ContainerAppSystemLogs) don't exist
// until the apps start generating logs. Use the post-provision
// script scripts/05-create-alerts.sh after logs are flowing.
// ──────────────────────────────────────────────────────────────

// ──────────────────────────────────────────────────────────────
// Outputs
// ──────────────────────────────────────────────────────────────
output acaEnvironmentName string = acaEnvironment.name
output acaEnvironmentId string = acaEnvironment.id
output acaApiAppName string = apiApp.name
output acaWebAppName string = webApp.name
output acrLoginServer string = acr.properties.loginServer
output acrName string = acr.name
output logAnalyticsWorkspaceId string = logAnalytics.properties.customerId
output logAnalyticsResourceId string = logAnalytics.id
output vnetName string = vnet.name
output acaIdentityPrincipalId string = acaIdentity.properties.principalId
