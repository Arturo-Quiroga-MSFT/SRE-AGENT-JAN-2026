// PIM Enablement Testbed - resource group resources
// Log Analytics + Container Apps Environment + supporting infra

@description('Azure region')
param location string

@description('Naming prefix')
param prefix string

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-${prefix}'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-${prefix}'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: law.properties.customerId
        sharedKey: law.listKeys().primarySharedKey
      }
    }
  }
}

output logAnalyticsWorkspaceId string = law.id
#disable-next-line outputs-should-not-contain-secrets
output logAnalyticsWorkspaceKey string = law.listKeys().primarySharedKey
output containerAppsEnvId string = cae.id
output containerAppsEnvName string = cae.name
