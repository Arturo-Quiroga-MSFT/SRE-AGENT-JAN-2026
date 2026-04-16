targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment (used in resource naming)')
param environmentName string

@minLength(1)
@description('Primary Azure region for all resources')
param location string

@description('Override for the resource group name')
param resourceGroupName string = ''

@description('Object ID of the SRE Agent managed identity to grant read-only access')
param sreAgentPrincipalId string = ''

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = {
  'azd-env-name': environmentName
  purpose: 'sre-agent-aca-locked-testbed'
}

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

module resources './resources.bicep' = {
  name: 'resources'
  scope: rg
  params: {
    location: location
    tags: tags
    resourceToken: resourceToken
    sreAgentPrincipalId: sreAgentPrincipalId
  }
}

// ──────────────────────────────────────────────────────────────
// Outputs consumed by deploy scripts and SRE Agent setup
// ──────────────────────────────────────────────────────────────
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output ACA_ENVIRONMENT_NAME string = resources.outputs.acaEnvironmentName
output ACA_API_APP_NAME string = resources.outputs.acaApiAppName
output ACA_WEB_APP_NAME string = resources.outputs.acaWebAppName
output ACR_LOGIN_SERVER string = resources.outputs.acrLoginServer
output ACR_NAME string = resources.outputs.acrName
output LOG_ANALYTICS_WORKSPACE_ID string = resources.outputs.logAnalyticsWorkspaceId
output LOG_ANALYTICS_RESOURCE_ID string = resources.outputs.logAnalyticsResourceId
output VNET_NAME string = resources.outputs.vnetName
