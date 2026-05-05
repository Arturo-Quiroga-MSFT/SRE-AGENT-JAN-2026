// PIM Enablement Testbed - main orchestrator
// Scope: subscription
//
// May 4 2026 update (post live-test): hybrid model.
// - PIM reads (~90%) go through the Microsoft-hosted MCP Server for Enterprise
//   (https://mcp.svc.cloud.microsoft/enterprise).
// - The one Graph endpoint Enterprise MCP cannot reach today
//   (roleAssignmentScheduleRequests) is served by a tiny custom MCP server
//   in pim-mcp-aca.bicep, deployed only when ``pimMcpImage`` is supplied.
//
// Deploys: resource group, Log Analytics + CAE, agent Managed Identity, and
// (optionally) the gap-filler pim-mcp Container App.

targetScope = 'subscription'

@description('Azure region for all resources')
param location string = 'eastus2'

@description('Resource group name')
param rgName string = 'rg-pim-enablement-testbed'

@description('Short prefix for resource naming (3-8 lowercase chars)')
@minLength(3)
@maxLength(8)
param prefix string = 'pimtest'

@description('Container image for the gap-filler pim-mcp server (e.g. <acr>.azurecr.io/pim-mcp:0.2.0). Leave empty to skip deployment of the gap-filler ACA.')
param pimMcpImage string = ''

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
}

module rgResources 'pim-test-rg.bicep' = {
  name: 'pim-test-rg'
  scope: rg
  params: {
    location: location
    prefix: prefix
  }
}

module agentMi 'agent-mi.bicep' = {
  name: 'agent-mi'
  scope: rg
  params: {
    location: location
    prefix: prefix
  }
}

module pimMcp 'pim-mcp-aca.bicep' = if (!empty(pimMcpImage)) {
  name: 'pim-mcp-aca'
  scope: rg
  dependsOn: [
    rgResources
    agentMi
  ]
  params: {
    location: location
    prefix: prefix
    image: pimMcpImage
  }
}

output resourceGroupName string = rg.name
output agentMiClientId string = agentMi.outputs.miClientId
output agentMiPrincipalId string = agentMi.outputs.miPrincipalId
output logAnalyticsWorkspaceId string = rgResources.outputs.logAnalyticsWorkspaceId
output enterpriseMcpEndpoint string = 'https://mcp.svc.cloud.microsoft/enterprise'
output pimMcpEndpoint string = empty(pimMcpImage) ? '' : pimMcp!.outputs.endpoint
