// PIM Enablement Testbed - PIM MCP Container App (gap-filler, ACTIVE)
//
// Hosts the single-tool ``pim-mcp`` FastMCP server that exposes
// ``list_pending_pim_requests``. This is the one Graph endpoint the
// Microsoft Enterprise MCP server cannot reach in current preview
// (delegated ReadWrite scope required; see mcp-servers/pim-mcp/README.md).
//
// Auth: User-Assigned Managed Identity, app-only Graph token.
// Required Graph app role on the MI: RoleAssignmentSchedule.Read.Directory.

@description('Azure region')
param location string

@description('Naming prefix')
param prefix string

@description('Container image (e.g. <acr>.azurecr.io/pim-mcp:0.2.0). Required.')
param image string

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: 'cae-${prefix}'
}

resource agentMi 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: 'mi-${prefix}-agent'
}

resource pimMcp 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ca-${prefix}-pimmcp'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${agentMi.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: cae.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8000
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: split(image, '/')[0]
          identity: agentMi.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'pim-mcp'
          image: image
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'AZURE_CLIENT_ID'
              value: agentMi.properties.clientId
            }
            {
              name: 'GRAPH_BASE_URL'
              value: 'https://graph.microsoft.com/v1.0'
            }
            {
              name: 'LOG_LEVEL'
              value: 'INFO'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 2
      }
    }
  }
}

output endpoint string = 'https://${pimMcp.properties.configuration.ingress.fqdn}'
output appName string = pimMcp.name
