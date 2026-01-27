# Zafin SRE Agent - Context and Requirements

## Team Structure
- **George Mathew** - VP CloudOps (Project Sponsor)
- **Jijo Lawrence** - Director, SRE Team Lead  
- **Soya** - Reports to Jijo
- **Zafin Team** - Using the solution built in this PoC

## Original POC Scope - Phase 1

### 1. Incident Automation & RCA
- Agent automatically detects incidents from Azure Monitor
- Performs RCA using telemetry/logs and suggests probable causes
- **Goal:** Cut incident triage time from hours → minutes

### 2. Smarter Incident Triage
- Automated incident "context packet" (logs, deployments, infra changes, history)
- Impact analysis (affected services/clients/SLAs)
- Dependency mapping (upstream/downstream blast radius)

### 3. Intelligent Remediation
- Integration with playbooks and guided runbooks
- Self-healing for repeatable fixes
- Predictive healing (mitigating issues before alerts fire)

## Phase 2 - Enhancements

1. **Proactive Monitoring**
   - Daily health summaries
   - Compliance checks
   - Scaling/configuration recommendations

2. **Security Enhancements**
   - Misconfiguration/vulnerability alerts
   - Certificate expiry and auto-rotation
   - Privileged access monitoring

3. **Ops Engineer Experience**
   - One-click incident summaries
   - Guided escalation with pre-filled tickets
   - Knowledge recall from past incidents

4. **Continuous Learning**
   - Agent improves via feedback loops
   - Incident pattern recognition
   - Historical resolutions database

## Technical Constraints

### AKS Behind Private VNET
**Issue:** SRE Agent currently does not support AKS Cluster behind private VNET

**Pivot Solution:** Use observability via Azure Monitor and Log Analytics instead of direct cluster access

**Impact on Architecture:**
- Cannot directly query AKS API from agent
- Must rely on:
  - Azure Monitor Metrics
  - Log Analytics Workspace queries
  - Container Insights
  - Application Insights

**Updated Query Patterns:**
```kusto
// Instead of kubectl logs, use Log Analytics
ContainerLog
| where TimeGenerated > ago(1h)
| where PodName contains "grocery-api"
| where LogEntry contains "error"
| project TimeGenerated, PodName, LogEntry
```

## Demo Environment vs Zafin Production

| Aspect | Demo (Our PoC) | Zafin Production |
|--------|----------------|------------------|
| **Compute** | Container Apps | AKS (Private VNET) |
| **Logs** | Loki | Azure Log Analytics |
| **Metrics** | Prometheus | Azure Monitor |
| **Dashboards** | Azure Managed Grafana | Azure Monitor Workbooks / Grafana |
| **Ticketing** | Jira Cloud | Jira Cloud (same) |
| **Alert Source** | Manual trigger | Azure Monitor Alerts |

## Integration Points for Zafin

### Required Adaptations

1. **Replace Loki queries with Kusto (KQL)**
   - Update knowledge file with KQL query patterns
   - Use Log Analytics instead of Loki MCP server
   - May need custom MCP server for Log Analytics (if not available)

2. **Azure Monitor Integration**
   - Connect agent to Azure Monitor alerts (built-in support)
   - Query Container Insights for AKS metrics
   - Use Application Insights for application telemetry

3. **Private VNET Considerations**
   - MCP servers must be accessible from agent
   - May need Private Endpoints for Jira MCP
   - Ensure agent can reach Log Analytics workspace

4. **Knowledge File Updates**
   - Document Zafin's AKS namespace structure
   - Zafin-specific label conventions
   - Common error patterns in their applications
   - Dependency maps for their services

## References
- **Blog:** [Blog8.docx](docs_from_Deepthi%20Chelupati/Blog8.docx)
- **Demo Repo:** https://github.com/dm-chelupati/grocery-sre-demo
- **SRE Agent Docs:** https://learn.microsoft.com/en-us/azure/sre-agent/overview
- **Teams Chat:** Zafin SRE Agent use cases implementation - Internal Sync call with PSA

---

**Last Updated:** January 26, 2026  
**Project:** Zafin SRE Agent PoC Implementation  
**Architect:** Arturo Quiroga
