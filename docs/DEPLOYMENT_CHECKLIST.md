# Azure SRE Agent PoC - Deployment Checklist

Use this checklist to track your deployment progress. Check off items as you complete them.

## Prerequisites (Before You Start)

- [ ] Azure subscription with Owner or Contributor + User Access Administrator role
- [ ] Azure CLI installed and updated (`az --version`)
- [ ] Azure Developer CLI installed (`azd version`)
- [ ] Docker Desktop installed and running
- [ ] Jira Cloud account with API access
- [ ] Jira API token created: https://id.atlassian.com/manage/api-tokens
- [ ] Firewall allows `*.azuresre.ai` domain

## Phase 1: Base Infrastructure (20-30 minutes)

- [ ] Clone the grocery-sre-demo repository
  ```bash
  cd ~/GITHUB/SRE-AGENT-JAN-2026
  # Already cloned via git clone https://github.com/dm-chelupati/grocery-sre-demo.git
  ```

- [ ] Login to Azure
  ```bash
  az login
  azd auth login
  ```

- [ ] Deploy base infrastructure
  ```bash
  cd grocery-sre-demo
  azd up
  # Environment name: sre-poc-partner
  # Location: eastus2
  ```

- [ ] Capture deployment values
  ```bash
  export RG=$(azd env get-values | grep AZURE_RESOURCE_GROUP | cut -d'=' -f2 | tr -d '"')
  export CAE_NAME=$(azd env get-values | grep AZURE_CONTAINER_APPS_ENVIRONMENT_NAME | cut -d'=' -f2 | tr -d '"')
  echo "Resource Group: $RG"
  echo "Environment: $CAE_NAME"
  ```

- [ ] Verify resources created
  ```bash
  az resource list --resource-group $RG --output table
  ```
  - [ ] Container Apps Environment
  - [ ] Grocery API (Container App)
  - [ ] Web Frontend (Container App)
  - [ ] Azure Managed Grafana
  - [ ] Container Registry

## Phase 2: Loki Deployment (10 minutes)

- [ ] Run Loki deployment script
  ```bash
  cd ..
  ./deploy-loki.sh
  ```

- [ ] Verify Loki is running
  ```bash
  LOKI_URL=$(az containerapp show --name ca-loki --resource-group $RG \
    --query "properties.configuration.ingress.fqdn" -o tsv)
  curl "https://$LOKI_URL/ready"
  # Expected: "ready"
  ```

- [ ] Verify API is configured to send logs
  ```bash
  API_NAME=$(az containerapp list -g $RG --query "[?contains(name,'api')].name" -o tsv | head -1)
  az containerapp show --name $API_NAME --resource-group $RG \
    --query "properties.template.containers[0].env[?name=='LOKI_HOST'].value" -o tsv
  # Should show Loki URL
  ```

- [ ] Save Loki configuration
  - [ ] Note Loki URL from `loki-config.txt`

## Phase 3: Grafana Configuration (15 minutes)

- [ ] Get Grafana URL
  ```bash
  AMG_NAME=$(az grafana list --resource-group $RG --query "[0].name" -o tsv)
  export AMG_URL=$(az grafana show --name $AMG_NAME --resource-group $RG \
    --query "properties.endpoint" -o tsv)
  echo "Grafana URL: $AMG_URL"
  ```

- [ ] Open Grafana in browser

- [ ] Add Loki data source
  - [ ] Go to Configuration → Data Sources → Add data source
  - [ ] Select **Loki**
  - [ ] URL: `https://$LOKI_URL` (from loki-config.txt)
  - [ ] Click **Save & Test**

- [ ] Create Grafana service account
  - [ ] Administration → Service Accounts → Add service account
  - [ ] Name: `mcp-server`
  - [ ] Role: **Admin**
  - [ ] Click **Create**

- [ ] Generate service account token
  - [ ] Click **Add service account token**
  - [ ] Name: `mcp-token`
  - [ ] **Copy and save the token** (starts with `glsa_`)
  ```bash
  export GRAFANA_TOKEN="glsa_XXXXXXXXXXXXXXXX"
  ```

- [ ] Test Loki data source in Grafana
  - [ ] Go to Explore
  - [ ] Select Loki data source
  - [ ] Query: `{app="grocery-api"}`
  - [ ] Should see logs

## Phase 4: MCP Servers Deployment (15 minutes)

- [ ] Prepare Jira credentials
  ```bash
  export JIRA_URL="https://yourorg.atlassian.net"
  export JIRA_EMAIL="your-email@example.com"
  export JIRA_TOKEN="ATATT3xXXXXXXXXXX"
  ```

- [ ] Run MCP servers deployment script
  ```bash
  ./deploy-mcp-servers.sh
  ```
  - [ ] Enter Resource Group name
  - [ ] Enter Container Apps Environment name
  - [ ] Enter Grafana URL
  - [ ] Paste Grafana service account token
  - [ ] Enter Jira URL
  - [ ] Enter Jira email
  - [ ] Paste Jira API token

- [ ] Verify MCP endpoints deployed
  ```bash
  # Check Grafana MCP
  MCP_GRAFANA_URL=$(az containerapp show --name ca-mcp-grafana --resource-group $RG \
    --query "properties.configuration.ingress.fqdn" -o tsv)
  echo "Grafana MCP: https://$MCP_GRAFANA_URL/mcp"
  
  # Check Jira MCP
  MCP_JIRA_URL=$(az containerapp show --name ca-mcp-jira --resource-group $RG \
    --query "properties.configuration.ingress.fqdn" -o tsv)
  echo "Jira MCP: https://$MCP_JIRA_URL/mcp"
  ```

- [ ] Test MCP endpoints
  ```bash
  # Test Grafana MCP
  curl -X POST "https://$MCP_GRAFANA_URL/mcp" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
  
  # Test Jira MCP
  curl -X POST "https://$MCP_JIRA_URL/mcp" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
  ```

- [ ] Save MCP endpoints from `mcp-endpoints.txt`

## Phase 5: SRE Agent Setup (20 minutes)

### Main Agent Creation

- [ ] Open Azure SRE Agent portal: https://aka.ms/sreagent/portal

- [ ] Create SRE Agent
  - [ ] Click **Create**
  - [ ] Subscription: (select yours)
  - [ ] Resource Group: Create new `rg-sre-agent`
  - [ ] Agent name: `sre-agent-partner-poc`
  - [ ] Region: **East US 2**
  - [ ] Click **Choose resource groups**
  - [ ] Select the grocery app resource group (from Phase 1)
  - [ ] Click **Save** → **Create**
  - [ ] Wait for deployment (3-5 minutes)

- [ ] Assign permissions to agent
  ```bash
  # Get agent's managed identity
  AGENT_PRINCIPAL_ID=$(az resource show \
    --resource-group rg-sre-agent \
    --name sre-agent-partner-poc \
    --resource-type "Microsoft.SreAgent/agents" \
    --query "identity.principalId" \
    -o tsv 2>/dev/null)
  
  # If command fails, get from portal: SRE Agent → Settings → Identity
  # Then run:
  az role assignment create \
    --assignee $AGENT_PRINCIPAL_ID \
    --role "Reader" \
    --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RG"
  ```

### Sub-Agent Configuration

- [ ] Create sub-agent
  - [ ] In SRE Agent portal, go to **Sub-agents** tab
  - [ ] Click **Create sub-agent**
  - [ ] Name: `DiagnosticExpert`
  - [ ] Description: "Diagnoses application issues using Grafana logs and creates Jira tickets"
  - [ ] Click **Create**

- [ ] Upload knowledge file
  - [ ] Go to **Knowledge** tab in sub-agent
  - [ ] Click **Upload file**
  - [ ] Upload: `grocery-sre-demo/knowledge/loki-queries.md`

- [ ] Add Grafana MCP tool
  - [ ] Go to **Tools** tab
  - [ ] Click **Add MCP Server**
  - [ ] Select **Remotely hosted**
  - [ ] Name: `grafana-mcp`
  - [ ] URL: (paste from mcp-endpoints.txt)
  - [ ] Transport: **Streamable HTTP**
  - [ ] Click **Test** (should succeed)
  - [ ] Click **Save**

- [ ] Add Jira MCP tool
  - [ ] Click **Add MCP Server**
  - [ ] Select **Remotely hosted**
  - [ ] Name: `jira-mcp`
  - [ ] URL: (paste from mcp-endpoints.txt)
  - [ ] Transport: **Streamable HTTP**
  - [ ] Click **Test** (should succeed)
  - [ ] Click **Save**

- [ ] Configure sub-agent instructions
  - [ ] Go to **Instructions** tab
  - [ ] Paste instructions from PARTNER_POC_GUIDE.md Section 6.4
  - [ ] Click **Save**

## Phase 6: Testing (15 minutes)

### Trigger Test Incident

- [ ] Get API URL
  ```bash
  API_URL=$(az containerapp show --name $API_NAME --resource-group $RG \
    --query "properties.configuration.ingress.fqdn" -o tsv)
  echo "API URL: https://$API_URL"
  ```

- [ ] Trigger rate limit scenario
  ```bash
  curl -X POST "https://$API_URL/api/demo/trigger-rate-limit"
  ```

- [ ] Verify logs in Grafana
  - [ ] Open Grafana → Explore
  - [ ] Query: `{app="grocery-api", level="error"} |= "429"`
  - [ ] Should see rate limit error logs

### Test SRE Agent

- [ ] Open SRE Agent in Azure Portal

- [ ] Invoke sub-agent with test prompt:
  ```
  @DiagnosticExpert: My container app ca-api in resource group [YOUR_RG] is experiencing rate limit errors from a supplier API when checking product inventory. Can you investigate?
  ```

- [ ] Verify agent actions:
  - [ ] Agent reads loki-queries.md knowledge file
  - [ ] Agent queries Loki via Grafana MCP
  - [ ] Agent identifies rate limit errors
  - [ ] Agent creates Jira ticket

- [ ] Check Jira for created ticket
  - [ ] Go to your Jira project
  - [ ] Verify ticket contains:
    - [ ] Root cause analysis
    - [ ] Log query results
    - [ ] Timeline of issue
    - [ ] Remediation recommendations
    - [ ] Appropriate priority and labels

## Phase 7: Partner Handoff

- [ ] Review documentation with partner
  - [ ] Walk through [README.md](README.md)
  - [ ] Review [PARTNER_POC_GUIDE.md](PARTNER_POC_GUIDE.md)
  - [ ] Show scenario examples in `/scenarios`

- [ ] Demonstrate key workflows
  - [ ] Show MCP server architecture
  - [ ] Query logs in Grafana UI
  - [ ] Modify knowledge file
  - [ ] Test different prompts with sub-agent
  - [ ] Review created Jira tickets

- [ ] Discuss customization
  - [ ] How to adapt for partner's real application
  - [ ] Update knowledge file with partner's log schema
  - [ ] Configure Jira project and issue types
  - [ ] Add monitoring and alerts

## Success Criteria

- [x] ✅ All infrastructure deployed successfully
- [x] ✅ Loki receiving logs from demo application
- [x] ✅ Grafana can query Loki logs
- [x] ✅ MCP servers responding to requests
- [x] ✅ SRE Agent can query logs via Grafana MCP
- [x] ✅ SRE Agent can create Jira tickets
- [x] ✅ End-to-end incident flow works
- [x] ✅ Partner understands how to customize for their needs

## Troubleshooting Reference

### MCP Endpoints Not Responding
```bash
# Check logs
az containerapp logs show --name ca-mcp-grafana --resource-group $RG --follow

# Restart container
az containerapp revision restart \
  --name ca-mcp-grafana \
  --resource-group $RG \
  --revision $(az containerapp revision list -n ca-mcp-grafana -g $RG --query "[0].name" -o tsv)
```

### No Logs in Loki
```bash
# Check API logs
az containerapp logs show --name $API_NAME --resource-group $RG --follow | grep -i loki

# Test Loki push
curl -X POST "https://$LOKI_URL/loki/api/v1/push" \
  -H "Content-Type: application/json" \
  -d '{"streams":[{"stream":{"app":"test"},"values":[["'$(date +%s)'000000000","test message"]]}]}'
```

### Agent Can't Access Resources
```bash
# Check role assignment
az role assignment list \
  --assignee $AGENT_PRINCIPAL_ID \
  --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RG"
```

## Next Steps After PoC

1. **Adapt for Production**
   - Replace demo app with partner's real Container App
   - Update knowledge file with partner's log schema
   - Configure autoscaling and monitoring

2. **Expand Capabilities**
   - Add more sub-agents for different teams
   - Integrate with ServiceNow if needed
   - Create custom runbooks for remediation

3. **Measure Success**
   - Track MTTR improvements
   - Measure reduction in manual toil
   - Quantify time saved on incident response

---

**Last Updated:** January 26, 2026  
**Deployment Time Estimate:** ~90 minutes  
**Complexity:** Medium
