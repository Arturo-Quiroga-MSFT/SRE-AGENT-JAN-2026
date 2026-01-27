# Azure SRE Agent PoC Implementation Guide for Partner

**Date:** January 26, 2026  
**Architect:** Arturo Quiroga  
**Reference Blog:** [Blog8.docx](docs_from_Deepthi%20Chelupati/Blog8.docx)  
**Reference Demo:** [grocery-sre-demo](https://github.com/dm-chelupati/grocery-sre-demo)

---

## 🎯 Objective

Build an end-to-end SRE Agent environment that mimics real-world incident response scenarios for the partner team to:
- Integrate non-Azure tools (Grafana/Loki, Jira) into SRE Agent using MCP (Model Context Protocol)
- Automate incident detection, log analysis, and ticket creation
- Enable hands-on experience with Azure SRE Agent capabilities

---

## 📋 Prerequisites

### Required Tools
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) (v2.50+)
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Docker Desktop](https://docs.docker.com/get-docker/)
- Active Azure subscription with Owner or Contributor + User Access Administrator role

### Azure Permissions Required
- `Microsoft.Authorization/roleAssignments/write` (for SRE Agent setup)
- Ability to create resource groups, Container Apps, and Managed Grafana

### External Accounts
- **Grafana:** Azure Managed Grafana instance (created via deployment)
- **Jira Cloud:** For ticket creation
  - Jira API token: https://id.atlassian.com/manage/api-tokens
  - Your Jira URL: `https://[your-org].atlassian.net`
  - Your Jira email

### Network Configuration
- Ensure firewall allows `*.azuresre.ai` domain (required for SRE Agent)

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         AZURE SUBSCRIPTION                           │
│                                                                       │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                 Container Apps Environment                      │ │
│  │                                                                 │ │
│  │  ├─ Grocery API (Node.js)        ────┐                       │ │
│  │  ├─ Web Frontend                      │ Logs                  │ │
│  │  ├─ Loki (Log Aggregation)      ◀─────┘                       │ │
│  │  ├─ MCP Grafana Server (Port /mcp)                            │ │
│  │  └─ MCP Jira Server (Port /mcp)                               │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │          Azure Managed Grafana                                 │ │
│  │                                                                 │ │
│  │  ├─ Loki Data Source (logs)                                   │ │
│  │  ├─ Prometheus Data Source (metrics)                          │ │
│  │  └─ Service Account + Token (for MCP)                         │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │          Azure SRE Agent                                       │ │
│  │                                                                 │ │
│  │  ├─ Main Agent (monitors resource groups)                     │ │
│  │  └─ Sub-Agent "DiagnosticExpert"                              │ │
│  │      ├─ MCP Grafana Tool (queries Loki)                       │ │
│  │      ├─ MCP Jira Tool (creates tickets)                       │ │
│  │      └─ Knowledge File: loki-queries.md                       │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                       │
└───────────────────────────────┬───────────────────────────────────────┘
                                ▼
                    ┌──────────────────────┐
                    │   Jira Cloud         │
                    │   (External SaaS)    │
                    └──────────────────────┘
```

---

## 📝 Phase 1: Deploy Base Infrastructure

### Step 1.1: Clone the Demo Repo

```bash
cd ~/projects
git clone https://github.com/dm-chelupati/grocery-sre-demo.git
cd grocery-sre-demo
```

### Step 1.2: Authenticate with Azure

```bash
# Login to Azure
az login

# Login to Azure Developer CLI
azd auth login

# Set subscription (if you have multiple)
az account set --subscription "<your-subscription-id>"
```

### Step 1.3: Deploy Infrastructure with azd

```bash
# Initialize environment (creates resource group, Container Apps, Grafana)
azd up

# Follow prompts:
# - Environment name: "sre-poc-partner" (or custom)
# - Location: "eastus2" (required for SRE Agent)
```

**What gets deployed:**
- Resource Group: `rg-sre-poc-partner`
- Container Apps Environment: `cae-<token>`
- Container Registry: `cr<token>`
- Grocery API (Container App)
- Web Frontend (Container App)
- Azure Managed Grafana: `amg-<token>`

**Capture these values:**
```bash
# List all resources
az resource list --resource-group rg-sre-poc-partner --output table

# Save these for later
export RG="rg-sre-poc-partner"
export CAE_NAME="cae-<token>"
export ACR_NAME="cr<token>"
export AMG_URL="https://amg-<token>.grafana.azure.com"
```

---

## 📝 Phase 2: Deploy Loki for Log Aggregation

### Step 2.1: Deploy Loki as Container App

```bash
az containerapp create \
  --name ca-loki \
  --resource-group $RG \
  --environment $CAE_NAME \
  --image grafana/loki:2.9.0 \
  --target-port 3100 \
  --ingress external \
  --min-replicas 1 \
  --max-replicas 1 \
  --cpu 0.5 \
  --memory 1Gi \
  --args "-config.file=/etc/loki/local-config.yaml"
```

**Capture Loki URL:**
```bash
export LOKI_URL=$(az containerapp show \
  --name ca-loki \
  --resource-group $RG \
  --query "properties.configuration.ingress.fqdn" \
  -o tsv)

echo "Loki URL: https://$LOKI_URL"
```

### Step 2.2: Configure API to Send Logs to Loki

```bash
# Get API container app name
API_NAME=$(az containerapp list --resource-group $RG \
  --query "[?contains(name, 'ca-api')].name" -o tsv | head -1)

# Update environment variable
az containerapp update \
  --name $API_NAME \
  --resource-group $RG \
  --set-env-vars "LOKI_HOST=https://$LOKI_URL"

echo "API now sends logs to Loki"
```

---

## 📝 Phase 3: Configure Grafana Data Sources

### Step 3.1: Add Loki Data Source to Grafana

1. Open Azure Managed Grafana:
   ```bash
   echo "Grafana URL: $AMG_URL"
   az grafana show --name amg-<token> --resource-group $RG
   ```

2. In Grafana UI:
   - Go to **Configuration** → **Data Sources** → **Add data source**
   - Select **Loki**
   - Set URL: `https://$LOKI_URL`
   - Click **Save & Test**

### Step 3.2: Create Grafana Service Account for MCP

1. In Grafana:
   - **Administration** → **Service Accounts** → **Add service account**
   - Name: `mcp-server`
   - Role: **Admin**
   - Click **Create**

2. Generate token:
   - Click **Add service account token**
   - Name: `mcp-token`
   - Copy the token (starts with `glsa_`)

```bash
export GRAFANA_TOKEN="glsa_XXXXXXXXXXXXXXXX"
```

---

## 📝 Phase 4: Deploy MCP Servers

### Step 4.1: Deploy Grafana MCP Server

```bash
az containerapp create \
  --name ca-mcp-grafana \
  --resource-group $RG \
  --environment $CAE_NAME \
  --image ghcr.io/grafana/mcp-grafana:latest \
  --target-port 8000 \
  --ingress external \
  --min-replicas 1 \
  --max-replicas 2 \
  --cpu 0.25 \
  --memory 0.5Gi \
  --env-vars \
    "GRAFANA_URL=$AMG_URL" \
    "GRAFANA_SERVICE_ACCOUNT_TOKEN=$GRAFANA_TOKEN" \
  --command "/usr/local/bin/mcp-server-grafana" \
  --args "-transport" "streamable-http" "-address" "0.0.0.0:8000"
```

**Capture MCP Grafana endpoint:**
```bash
export MCP_GRAFANA_URL=$(az containerapp show \
  --name ca-mcp-grafana \
  --resource-group $RG \
  --query "properties.configuration.ingress.fqdn" \
  -o tsv)

echo "MCP Grafana: https://$MCP_GRAFANA_URL/mcp"
```

**Test the endpoint:**
```bash
curl -X POST "https://$MCP_GRAFANA_URL/mcp" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
```

### Step 4.2: Deploy Jira MCP Server

**Get Jira credentials:**
```bash
# Prompt for credentials
read -p "Enter your Jira URL (e.g., https://yourorg.atlassian.net): " JIRA_URL
read -p "Enter your Jira email: " JIRA_EMAIL
read -sp "Enter your Jira API token: " JIRA_TOKEN
echo
```

```bash
az containerapp create \
  --name ca-mcp-jira \
  --resource-group $RG \
  --environment $CAE_NAME \
  --image ghcr.io/sooperset/mcp-atlassian:latest \
  --target-port 8000 \
  --ingress external \
  --min-replicas 1 \
  --max-replicas 2 \
  --cpu 0.25 \
  --memory 0.5Gi \
  --env-vars \
    "JIRA_URL=$JIRA_URL" \
    "JIRA_USERNAME=$JIRA_EMAIL" \
    "JIRA_API_TOKEN=$JIRA_TOKEN" \
    "TRANSPORT=streamable-http" \
    "HOST=0.0.0.0" \
    "PORT=8000"
```

**Capture MCP Jira endpoint:**
```bash
export MCP_JIRA_URL=$(az containerapp show \
  --name ca-mcp-jira \
  --resource-group $RG \
  --query "properties.configuration.ingress.fqdn" \
  -o tsv)

echo "MCP Jira: https://$MCP_JIRA_URL/mcp"
```

---

## 📝 Phase 5: Create and Configure SRE Agent

### Step 5.1: Create Main SRE Agent

1. Open Azure Portal: https://aka.ms/sreagent/portal
2. Click **Create**
3. Fill in details:
   - **Subscription:** Your subscription
   - **Resource Group:** Create new: `rg-sre-agent`
   - **Agent name:** `sre-agent-partner-poc`
   - **Region:** `East US 2`
4. Click **Choose resource groups**
5. Select the resource group created by azd (e.g., `rg-sre-poc-partner`)
6. Click **Save** → **Create**

### Step 5.2: Grant Agent Permissions

The agent's managed identity needs `Reader` access to the resource group:

```bash
# Get agent's managed identity
AGENT_PRINCIPAL_ID=$(az resource show \
  --resource-group rg-sre-agent \
  --name sre-agent-partner-poc \
  --resource-type "Microsoft.SreAgent/agents" \
  --query "identity.principalId" \
  -o tsv 2>/dev/null)

# If the above doesn't work, get it from portal:
# SRE Agent → Settings → Identity → Copy Object (principal) ID
read -p "Enter SRE Agent Principal ID: " AGENT_PRINCIPAL_ID

# Grant Reader access to monitored resource group
az role assignment create \
  --assignee $AGENT_PRINCIPAL_ID \
  --role "Reader" \
  --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RG"
```

---

## 📝 Phase 6: Create Sub-Agent with MCP Tools

### Step 6.1: Prepare Knowledge File

The knowledge file helps the agent understand your app logs.

**Upload `loki-queries.md` to SRE Agent:**

1. In SRE Agent portal, go to **Knowledge** tab
2. Click **Upload file**
3. Upload from: `grocery-sre-demo/knowledge/loki-queries.md`

### Step 6.2: Create Sub-Agent "DiagnosticExpert"

1. In SRE Agent, go to **Sub-agents** tab
2. Click **Create sub-agent**
3. Fill in:
   - **Name:** `DiagnosticExpert`
   - **Description:** "Diagnoses application issues using Grafana logs and creates Jira tickets"

### Step 6.3: Add MCP Tools to Sub-Agent

**Add Grafana MCP:**
1. In sub-agent, go to **Tools** tab
2. Click **Add MCP Server**
3. Select **Remotely hosted**
4. Enter:
   - **Name:** `grafana-mcp`
   - **URL:** `https://$MCP_GRAFANA_URL/mcp`
   - **Transport:** `SSE` or `Streamable HTTP`
5. Click **Test** → **Save**

**Add Jira MCP:**
1. Click **Add MCP Server**
2. Select **Remotely hosted**
3. Enter:
   - **Name:** `jira-mcp`
   - **URL:** `https://$MCP_JIRA_URL/mcp`
   - **Transport:** `SSE` or `Streamable HTTP`
4. Click **Test** → **Save**

### Step 6.4: Configure Sub-Agent Instructions

In the **Instructions** tab, add:

```markdown
You are an expert in diagnosing applications running on Azure Container Apps.

Your workflow:
1. Use the Grafana tools to query Loki logs for error patterns
2. Reference the knowledge file `loki-queries.md` to construct accurate queries
3. Look for:
   - Rate limit errors (429 status codes)
   - External API failures
   - Error trends over time
4. Summarize your findings clearly
5. Create a Jira ticket in the appropriate project with:
   - Title: Brief description of the issue
   - Description: Root cause, affected service, timeline, remediation steps
   - Priority: Based on severity
   - Labels: `incident`, `automated`

Always query logs for the last 1 hour unless specified otherwise.
```

---

## 📝 Phase 7: Test the End-to-End Scenario

### Step 7.1: Trigger a Rate Limit Issue

**Option A: Via Web UI**
```bash
# Get web app URL
WEB_URL=$(az containerapp show \
  --name $(az containerapp list -g $RG --query "[?contains(name,'web')].name" -o tsv | head -1) \
  --resource-group $RG \
  --query "properties.configuration.ingress.fqdn" \
  -o tsv)

echo "Open: https://$WEB_URL"
# Click "Trigger Rate Limit (Demo)" button
```

**Option B: Via API**
```bash
API_URL=$(az containerapp show \
  --name $API_NAME \
  --resource-group $RG \
  --query "properties.configuration.ingress.fqdn" \
  -o tsv)

curl -X POST "https://$API_URL/api/demo/trigger-rate-limit"
```

### Step 7.2: Invoke the SRE Agent

1. Open SRE Agent in Azure Portal
2. In the chat, type:

```
@DiagnosticExpert: My container app ca-api in resource group rg-sre-poc-partner is experiencing rate limit errors from a supplier API when checking product inventory. Can you investigate?
```

**Expected Agent Actions:**
1. ✅ Reads `loki-queries.md` for query patterns
2. ✅ Queries Loki via Grafana MCP: `{app="grocery-api", level="error"} |= "429"`
3. ✅ Identifies spike in `SUPPLIER_RATE_LIMIT_429` errors
4. ✅ Extracts details: affected endpoint, timestamp, frequency
5. ✅ Creates Jira ticket with:
   - Summary: "Rate limit errors on grocery-api from FreshFoods Supplier API"
   - Description: RCA, affected service, remediation (implement exponential backoff, contact supplier)
   - Priority: High
   - Labels: `incident`, `automated`, `rate-limit`

### Step 7.3: Verify the Jira Ticket

1. Go to your Jira project
2. Find the newly created ticket
3. Verify it contains:
   - Root cause analysis
   - Loki query results
   - Timestamp of issue
   - Remediation recommendations

---

## 📝 Phase 8: Handoff and Partner Enablement

### Partner Training Checklist

- [ ] Walk through architecture diagram
- [ ] Show MCP server endpoints and how they work
- [ ] Demonstrate querying Loki in Grafana UI
- [ ] Show how to modify `loki-queries.md` knowledge file
- [ ] Test sub-agent prompts together
- [ ] Review Jira tickets created by agent
- [ ] Explore other sub-agent capabilities (Azure resource management)

### Customization for Partner's Real Scenario

To adapt this for the partner's actual application:

1. **Replace demo app with partner's Container App**
   - Ensure their app logs to Loki (add Loki SDK)
   - Use their app's `app` label in queries

2. **Update knowledge file**
   - Document partner's app labels and log fields
   - Add partner-specific query patterns

3. **Configure Jira project**
   - Update sub-agent instructions with correct Jira project key
   - Set appropriate issue types, priorities, labels

4. **Extend sub-agent**
   - Add Azure Monitor integration for metrics
   - Connect to PagerDuty if partner uses it

---

## 🔧 Troubleshooting

### MCP Server Not Responding
```bash
# Check container app logs
az containerapp logs show --name ca-mcp-grafana --resource-group $RG --follow

# Restart container
az containerapp revision restart \
  --name ca-mcp-grafana \
  --resource-group $RG \
  --revision $(az containerapp revision list -n ca-mcp-grafana -g $RG --query "[0].name" -o tsv)
```

### Agent Can't Access Resources
```bash
# Verify role assignment
az role assignment list \
  --assignee $AGENT_PRINCIPAL_ID \
  --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RG"
```

### Logs Not Appearing in Loki
```bash
# Check API logs for Loki push errors
az containerapp logs show --name $API_NAME --resource-group $RG --follow | grep -i loki

# Test Loki directly
curl -v "https://$LOKI_URL/loki/api/v1/query_range" \
  --get \
  --data-urlencode 'query={app="grocery-api"}'
```

---

## 📚 Additional Resources

- **Azure SRE Agent Docs:** https://learn.microsoft.com/en-us/azure/sre-agent/overview
- **MCP Specification:** https://modelcontextprotocol.io/
- **Grafana MCP Server:** https://github.com/grafana/mcp-grafana
- **Deepthi's Blog Post:** [Blog8.docx](docs_from_Deepthi%20Chelupati/Blog8.docx)
- **Original Demo Repo:** https://github.com/dm-chelupati/grocery-sre-demo

---

## 💡 Next Steps After PoC

1. **Scale to production:**
   - Use Azure Container Apps with autoscaling
   - Enable Application Insights for additional telemetry
   - Set up Azure Monitor alerts

2. **Enhance agent capabilities:**
   - Add custom runbooks for common remediation tasks
   - Integrate with ServiceNow if partner uses it
   - Connect to partner's CI/CD for automated rollbacks

3. **Expand coverage:**
   - Monitor additional Azure services (AKS, VMs, databases)
   - Add scheduled tasks for proactive security scanning
   - Set up multiple sub-agents for different teams

4. **Measure impact:**
   - Track MTTR (Mean Time To Recovery) before/after
   - Measure reduction in manual toil
   - Quantify time saved on incident response

---

**Document Version:** 1.0  
**Last Updated:** January 26, 2026  
**Contact:** Arturo Quiroga
