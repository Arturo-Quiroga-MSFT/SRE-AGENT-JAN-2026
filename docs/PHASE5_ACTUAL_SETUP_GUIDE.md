# Phase 5: Azure SRE Agent Setup - Actual Portal Workflow

**Date:** January 28, 2026  
**Status:** Based on actual Azure Portal experience + official documentation

---

## Architecture Note

Azure SRE Agent uses a two-tier structure:
- **Connectors**: External integrations (MCP servers, Teams, Outlook, etc.)
- **Subagents**: Specialized AI agents that USE the connectors as tools

---

## Step 1: Add MCP Connectors (5 minutes)

### 1.1 Navigate to Connectors

1. Open Azure Portal: https://portal.azure.com
2. Go to your SRE Agent resource: `main` (or whatever you named it)
3. In the left menu, select **Settings → Connectors**
4. Click **+ Add connector**

### 1.2 Add Grafana MCP Connector

```
Connector Type: MCP server
Name: grafana-mcp
Connection Type: SSE
MCP server URL: https://ca-mcp-grafana.icymeadow-96da5d2b.eastus2.azurecontainerapps.io/sse
Authentication: None required (token embedded in container)
```

- Click **Validate connection** to test
- Status should show "Connected" with green checkmark
- Click **Save**

### 1.3 Add Jira MCP Connector

```
Connector Type: MCP server
Name: jira-mcp
Connection Type: SSE
MCP server URL: https://ca-mcp-jira.icymeadow-96da5d2b.eastus2.azurecontainerapps.io/sse
Authentication: None required (credentials embedded in container)
```

- Click **Validate connection** to test
- Status should show "Connected" with green checkmark
- Click **Save**

**Verification:** You should now see both connectors in the list with "Connected" status.

---

## Step 2: Create Subagent (10 minutes)

### 2.1 Navigate to Subagent Builder

1. In your SRE Agent resource, look for **Subagent Builder** or **Subagents** in the left menu
2. Click **Create subagent** or **+ New subagent**

### 2.2 Configure Basic Information

```
Name: DiagnosticExpert
Description: Diagnoses application issues using Grafana/Loki logs and creates Jira tickets for incidents
Purpose: Investigate Container Apps logs, identify root causes, automate ticket creation
```

### 2.3 Upload Knowledge File

1. Go to **Settings → Knowledge Base → Files** tab (or look for **Knowledge** in subagent)
2. Click **Upload files** or **+ Add file**
3. Upload: `/Users/arturoquiroga/GITHUB/SRE-AGENT-JAN-2026/grocery-sre-demo/knowledge/loki-queries.md`
4. Add tags: `loki`, `queries`, `logging`
5. Enable access for "DiagnosticExpert" subagent

### 2.4 Select Tools (Associate MCP Connectors)

1. In the subagent configuration, find **Tools** or **Extended tools** section
2. Click **Choose tools** or **Add connector**
3. Select the MCP connectors you created:
   - ✅ grafana-mcp
   - ✅ jira-mcp
4. Click **Save** or **Apply**

### 2.5 Configure Subagent Instructions

In the **Instructions** field, add:

```markdown
You are an expert in diagnosing applications running on Azure Container Apps.

When investigating issues:

1. **Query Logs via Grafana MCP:**
   - Use the grafana-mcp tool to query Loki logs
   - Reference the knowledge file `loki-queries.md` for LogQL query patterns
   - Focus on error patterns, rate limits (429 status codes), and external API failures
   - Default query range: last 1 hour (unless specified otherwise)

2. **Analyze Findings:**
   - Identify error trends over time
   - Determine affected services and endpoints
   - Extract relevant timestamps and frequencies
   - Establish root cause

3. **Create Jira Ticket via Jira MCP:**
   - Use the jira-mcp tool to create a ticket in the appropriate project
   - Title: Brief, clear description of the issue
   - Description: Include:
     * Root cause analysis
     * Affected service(s) and resource group
     * Timeline of the incident
     * Recommended remediation steps
   - Priority: Set based on severity (Critical/High/Medium/Low)
   - Labels: Always add `incident`, `automated`, and relevant service tags

4. **Response Format:**
   - Summarize findings clearly
   - Provide Jira ticket link
   - Suggest immediate mitigation if applicable

Always be thorough but concise in your analysis.
```

### 2.6 Set Handoff Rules (Optional)

Define when the subagent should escalate to humans or other subagents:
- If unable to query logs after 3 attempts
- If root cause is ambiguous
- If manual intervention is required

---

## Step 3: Configure Triggers (Optional - 5 minutes)

### Option A: Incident Response Plan

If you want the subagent to auto-respond to Azure Monitor alerts:

1. Go to **Settings → Incident Response Plans**
2. Click **Create plan**
3. Configure:
   ```
   Name: Container Apps Diagnostics
   Trigger: Azure Monitor alerts
   Filtering: Resource type = Container Apps, Severity >= Warning
   Assign to Subagent: DiagnosticExpert
   ```

### Option B: Scheduled Task

For proactive health checks:

1. Go to **Settings → Scheduled Tasks**
2. Click **Create task**
3. Configure:
   ```
   Name: Daily Health Check
   Schedule: Every day at 9:00 AM (Cron: 0 9 * * *)
   Subagent: DiagnosticExpert
   Task: "Query Loki for any errors in the last 24 hours from all Container Apps"
   ```

---

## Step 4: Test in Subagent Playground (5 minutes)

1. In the DiagnosticExpert subagent, look for **Playground** or **Test** tab
2. Enter a test query:

```
My container app ca-api in resource group rg-aqsre is experiencing rate limit errors from a supplier API when checking product inventory. Can you investigate the logs from the last hour?
```

3. **Expected Behavior:**
   - Agent reads `loki-queries.md` knowledge file
   - Agent calls grafana-mcp tool to query Loki with LogQL
   - Agent summarizes log findings
   - Agent calls jira-mcp tool to create a ticket
   - Agent provides Jira ticket link

4. **Review the Trace:**
   - Check which tools were called
   - Verify tool responses contain expected data
   - Confirm Jira ticket was created successfully

---

## Troubleshooting

### Connector Shows "Not Connected"
- Verify the MCP server URL is correct and accessible
- Test SSE endpoint manually: 
  ```bash
  curl -N -H "Accept: text/event-stream" https://ca-mcp-grafana.../sse
  ```
- Check container app logs:
  ```bash
  az containerapp logs show --name ca-mcp-grafana --resource-group rg-aqsre --follow
  ```

### Subagent Can't Access Tools
- Verify connectors are properly assigned to the subagent in the **Tools** section
- Refresh the connector status in Settings → Connectors
- Try disconnecting and reconnecting the MCP server

### Knowledge File Not Being Used
- Verify file is uploaded successfully
- Check that subagent has access enabled in knowledge base settings
- File must be in Markdown (.md) or text (.txt) format

---

## Next: End-to-End Testing

Once the subagent is configured and tested in playground:

1. **Trigger the Rate Limit Scenario:**
   ```bash
   curl -X POST "https://ca-api-ps64h2ydsavgc.icymeadow-96da5d2b.eastus2.azurecontainerapps.io/api/demo/trigger-rate-limit"
   ```

2. **Invoke the Agent** (via chat in Azure Portal):
   ```
   @DiagnosticExpert: My container app is experiencing rate limit errors. Can you investigate?
   ```

3. **Validate:**
   - ✅ Agent queries Loki logs via Grafana MCP
   - ✅ Agent creates Jira ticket with RCA
   - ✅ Jira ticket appears at https://aq-r2d2.atlassian.net

---

## Summary

✅ **Connectors Added**: Grafana MCP and Jira MCP configured in Settings → Connectors  
✅ **Subagent Created**: DiagnosticExpert with tools and instructions  
✅ **Knowledge Uploaded**: loki-queries.md available to subagent  
✅ **Ready for Testing**: Playground validated, ready for live scenarios

**Time Invested:** ~25 minutes for complete setup

