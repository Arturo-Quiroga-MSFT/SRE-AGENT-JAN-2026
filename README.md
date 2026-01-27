# Azure SRE Agent - Partner PoC Quick Start

This repository contains everything you need to build an Azure SRE Agent environment that integrates Jira and Grafana/Loki for automated incident response.

## 📁 What's Included

```
SRE-AGENT-JAN-2026/
├── README.md                          # This file - Quick start guide
├── PARTNER_POC_GUIDE.md               # Complete step-by-step implementation guide
├── DEPLOYMENT_CHECKLIST.md            # Interactive checklist for deployment
├── DEPLOYMENT_TIME_TRACKER.md         # Track actual time & agent performance
├── ZAFIN_CONTEXT.md                   # Zafin-specific requirements & constraints
├── deploy-loki.sh                     # Automated Loki deployment script
├── deploy-mcp-servers.sh              # Automated MCP servers deployment script
├── docs_from_Deepthi Chelupati/
│   └── Blog8.docx                     # Reference blog post
├── grocery-sre-demo/                  # Demo application (cloned from GitHub)
│   ├── README.md                      # Demo app documentation
│   ├── knowledge/
│   │   └── loki-queries.md           # Knowledge file for SRE Agent
│   ├── src/                          # Demo application source
│   └── infra/                        # Bicep infrastructure code
└── scenarios/                         # Partner-specific scenario templates
    ├── rate-limit-incident.md         # Rate limiting scenario with timing
    └── service-degradation.md         # Performance degradation scenario
```

## ⏱️ Time Estimate

| Phase | Duration | Complexity |
|-------|----------|------------|
| Prerequisites | 5 min | Easy |
| Base Infrastructure | 20-30 min | Easy |
| Loki + MCP Servers | 25 min | Medium |
| SRE Agent Setup | 20 min | Medium |
| Testing | 15 min | Easy |
| **Total** | **~90 min** | **Medium** |

💡 **Tip:** Use [DEPLOYMENT_TIME_TRACKER.md](DEPLOYMENT_TIME_TRACKER.md) to track actual time and agent performance metrics.

## 🚀 Quick Start (3 Steps)

### Step 1: Deploy Base Infrastructure (20-30 min)

```bash
cd grocery-sre-demo

# Login to Azure
az login
azd auth login

# Deploy Container Apps, Grafana, and demo app
azd up
# Choose environment name: sre-poc-partner
# Choose location: eastus2
```
 (25 min)

**Deploy Loki (10 min)oup: `rg-sre-poc-partner`
- Container Apps Environment with demo API
- Azure Managed Grafana
- Container Registry

**Save these values:**
```bash
export RG=$(azd env get-values | grep AZURE_RESOURCE_GROUP | cut -d'=' -f2 | tr -d '"')
export CAE_NAME=$(azd env get-values | grep AZURE_CONTAINER_APPS_ENVIRONMENT_NAME | cut -d'=' -f2 | tr -d '"')
```

### Step 2: Deploy Loki & MCP Servers

**Deploy Loki:** (15 min)
```bash
cd ..
./deploy-loki.sh
# Follow prompts to enter Resource Group and Container Apps Environment
```

**Get Grafana Service Account Token:**
1. Open Azure Managed Grafana (URL from deployment)
2. Go to **Administration** → **Service Accounts** → **Add service account**
3. Name: `mcp-server`, Role: **Admin**
4. Generate token and copy it

**Deploy MCP Servers:**
```bash
./deploy-mcp-servers.sh (20 min)

1. **Create SRE Agent (10 min)
# - Container Apps Environment
# - Grafana URL
# - Grafana service account token
# - Jira URL (https://yourorg.atlassian.net)
# - Jira email
# - Jira API token (from https://id.atlassian.com/manage/api-tokens)
```

**Saves endpoints to:** `mcp-endpoints.txt`

### Step 3: Configure SRE Agent

1. **Create SRE Agent:**
   - Go to https://aka.ms/sreagent/portal
   - Create agent in `eastus2`
   - Name: `sre-agent-partner-poc`
   - Monitor the resource group from Step 1

2. **Add Loki Data Source in Grafana:**
   - Configuration → Data Sources → Add Loki
   - URL from `loki-config.txt`

3. **Create Sub-Agent (10 min):**
   - Name: `DiagnosticExpert`
   - Add MCP tools (URLs from `mcp-endpoints.txt`):
     - Grafana MCP (remotely hosted)
     - Jira MCP (remotely hosted)
   - Upload knowledge file: `grocery-sre-demo/knowledge/loki-queries.md`
   - Add instructions from [PARTNER_POC_GUIDE.md](PARTNER_POC_GUIDE.md#step-64-configure-sub-agent-instructions)

## 🧪 Test the Demo (15 min)

**Trigger rate limit scenario:**
```bash
# Get API URL
API_URL=$(az containerapp list -g $RG --query "[?contains(name,'api')].properties.configuration.ingress.fqdn" -o tsv | head -1)

# Trigger rate limit
curl -X POST "https://$API_URL/api/demo/trigger-rate-limit"
```

**Ask the SRE Agent:**
```
@DiagnosticExpert: My container app is experiencing rate limit errors from a supplier API when checking product inventory. Can you investigate?
```

**Expected outcome (5-8 min response time):**
- ✅ Agent reads knowledge file (~5 sec)
- ✅ Agent queries Loki logs via Grafana MCP (~10-15 sec)
- ✅ Agent identifies rate limit errors (429 status codes) (~10 sec)
- ✅ Agent creates Jira ticket with root cause and remediation (~30-45 sec)

**Track performance:** Use [DEPLOYMENT_TIME_TRACKER.md](DEPLOYMENT_TIME_TRACKER.md) to record actual response times and token usage.
| Document | Purpose | Time to Review |
|----------|---------|----------------|
| **[README.md](README.md)** | Quick start (this file) | 5 min |
| **[PARTNER_POC_GUIDE.md](PARTNER_POC_GUIDE.md)** | Complete implementation guide | 20 min |
| **[DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md)** | Interactive deployment checklist | Use during deployment |
| **[DEPLOYMENT_TIME_TRACKER.md](DEPLOYMENT_TIME_TRACKER.md)** | Track time & agent performance | Fill out during testing |
| **[ZAFIN_CONTEXT.md](ZAFIN_CONTEXT.md)** | Zafin-specific requirements | 10 min |
| **[scenarios/](scenarios/)** | Incident scenario examples | 15 min |

**External References:**
## 📚 Documentation

- **[PARTNER_POC_GUIDE.md](PARTNER_POC_GUIDE.md)** - Complete implementation guide with all phases
- **[Azure SRE Agent Docs](https://learn.microsoft.com/en-us/azure/sre-agent/overview)** - Official documentation
- **[MCP Specification](https://modelcontextprotocol.io/)** - Model Context Protocol docs
- **[Original Demo Repo](https://github.com/dm-chelupati/grocery-sre-demo)** - Source repository

## 🔧 Deployment Scripts

| S🎯 Zafin-Specific Considerations

**Key Constraint:** AKS behind private VNET - SRE Agent cannot directly access cluster.

**Solution:** Use Azure Monitor + Log Analytics instead of direct cluster access.

See [ZAFIN_CONTEXT.md](ZAFIN_CONTEXT.md) for:
- Original POC scope (Phase 1 & 2)
- Team structure and sponsors
- Technical constraints and pivots
- KQL query patterns instead of Loki

## cript | Purpose |
|--------|---------|
| `deploy-loki.sh` | Deploy Loki for log aggregation, configure apps to send logs |
| `deploy-mcp-servers.sh` | Deploy Grafana and Jira MCP servers to Container Apps |

Both scripts:
- ✅ Check prerequisites
- ✅ Validate inputs
- ✅ Deploy resources
- ✅ Test endpoints
- ✅ Save configuration for next steps

## 💡 Partner Customization

To adapt this for your actual application:

1. **Replace demo app with your Container App**
   ```bash
   # Configure your app to send logs to Loki
   az containerapp update \
     --name YOUR_APP_NAME \
     --resource-group $RG \
     --set-env-vars "LOKI_HOST=https://ca-loki.xxxxx.azurecontainerapps.io"
   ```

2. **Update knowledge file**
   - Copy `grocery-sre-demo/knowledge/loki-queries.md`
   - Update app labels and log fields for your app
   - Upload to SRE Agent

3. **Customize Jira integration**
   - Update sub-agent instructions with your Jira project key
   - Set appropriate issue types and priorities

## 🎯 Key Capabilities Demonstrated

- ✅ **MCP Integration:** Connect non-Azure tools to SRE Agent
- ✅ **Log Analysis:** Query Loki logs via Grafana MCP
- ✅ **Ticket Automation:** Create Jira tickets with RCA
- ✅ **Knowledge Context:** Speed up investigation with domain knowledge
- ✅ **Container Apps:** Modern microservices on Azure

## 🔍 Troubleshooting

**MCP endpoints not responding?**
```bash
# Check container logs
az containerapp logs show --name ca-mcp-grafana --resource-group $RG --follow

# Restart if needed
az containerapp revision restart \
  --name ca-mcp-grafana \
  --resource-group $RG \
  --revision $(az containerapp revision list -n ca-mcp-grafana -g $RG --query "[0].name" -o tsv)
```

**Logs not appearing in Loki?**
```bash
# Check API configuration
az containerapp show --name YOUR_API --resource-group $RG \
  --query "properties.template.containers[0].env"

# Test Loki directly
LOKI_URL=$(az containerapp show --name ca-loki -g $RG --query "properties.configuration.ingress.fqdn" -o tsv)
curl "https://$LOKI_URL/loki/api/v1/query_range?query={app=\"grocery-api\"}"
```

## 📞 Support

- **Architecture Questions:** Review [PARTNER_POC_GUIDE.md](PARTNER_POC_GUIDE.md)
- **Azure SRE Agent:** [Documentation](https://learn.microsoft.com/en-us/azure/sre-agent/overview)
- **MCP Servers:** Check container logs for detailed errors

## 🎓 Next Steps After PoC

1. **Scale to Production:**
   - Enable autoscaling on Container Apps
   - Add Application Insights for additional telemetry
   - Set up Azure Monitor alerts for proactive monitoring

2. **Enhance Capabilities:**
   - Add custom runbooks for common remediation tasks
   - Integrate ServiceNow if needed
   - Create multiple sub-agents for different teams

3. **Measure Impact:**
   - Track MTTR (Mean Time To Recovery)
   - Measure reduction in manual toil
   - Quantify time saved on incident response

---

**Version:** 1.0  
**Date:** January 26, 2026  
**Contact:** Arturo Quiroga
