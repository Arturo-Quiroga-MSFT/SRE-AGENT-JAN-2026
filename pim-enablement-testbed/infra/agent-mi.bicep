// PIM Enablement Testbed - Agent Managed Identity
//
// May 4 2026 scope change: PIM reads now flow through the Microsoft-hosted
// MCP Server for Enterprise using DELEGATED auth (a service-account user),
// NOT this Managed Identity. See docs/enterprise-mcp-setup.md.
//
// This MI is retained for non-Graph-PIM paths only:
//   - Calling the existing Jira MCP server (if it accepts MI auth)
//   - Pushing to Azure Key Vault for the Teams webhook secret
//   - Future writes (when Enterprise MCP adds write support, we may
//     still keep PIM writes off the MI for compliance)
//
// No Microsoft Graph PIM permissions are required on this MI.

@description('Azure region')
param location string

@description('Naming prefix')
param prefix string

resource agentMi 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'mi-${prefix}-agent'
  location: location
}

output miId string = agentMi.id
output miClientId string = agentMi.properties.clientId
output miPrincipalId string = agentMi.properties.principalId
output miName string = agentMi.name
