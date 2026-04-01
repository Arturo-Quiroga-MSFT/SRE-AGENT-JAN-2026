---
title: "SRE Agent Quick Recreate Guide"
description: "Step-by-step procedure for recreating the Azure SRE Agent resource after deletion, assuming all other infrastructure is still deployed."
author: Arturo Quiroga
ms.date: 2026-03-16
ms.topic: how-to
---

## Prerequisites (already deployed, do not recreate)

| Resource | Name | Status |
|---|---|---|
| Resource Group | `rg-aqsre` | Exists |
| Container Apps Env | `cae-ps64h2ydsavgc` | Exists |
| Container Registry | `crps64h2ydsavgc` | Exists |
| Managed Grafana | `amg-ps64h2ydsavgc` | Exists |
| Grafana MCP | `ca-mcp-grafana` | Exists |
| Jira MCP | `ca-mcp-jira` | Exists |
| Loki | `ca-loki` | Exists |
| Grocery API | `ca-api-ps64h2ydsavgc` | Exists |
| Web Frontend | `ca-web-ps64h2ydsavgc` | Exists |

## Step 0 — Verify MCP servers are alive

```bash
curl -s -o /dev/null -w "%{http_code}" \
  https://ca-mcp-grafana.icymeadow-96da5d2b.eastus2.azurecontainerapps.io/mcp
# Expected: 200

curl -s -o /dev/null -w "%{http_code}" \
  https://ca-mcp-jira.icymeadow-96da5d2b.eastus2.azurecontainerapps.io/mcp
# Expected: 406 (normal — FastMCP rejects bare GET)
```

If either times out, the containers may have scaled to zero. Hit the endpoint
a few times to wake them.

## Step 1 — Create SRE Agent resource (~5 min)

1. Azure Portal → Create Resource → search **Azure SRE Agent**
2. Configure:

| Field | Value |
|---|---|
| Name | `aq-main` |
| Region | `eastus2` |
| Resource Group | `rg-aqsre` |
| Subscription | `ARTURO-MngEnvMCAP094150` |

3. Review + Create → wait for deployment to complete

## Step 2 — Add MCP Connectors (~3 min)

Navigate to the new SRE Agent resource → **Settings → Connectors → + Add connector**.

### Grafana MCP

| Field | Value |
|---|---|
| Name | `grafana-mcp` |
| Connection type | **Streamable-HTTP** |
| URL | `https://ca-mcp-grafana.icymeadow-96da5d2b.eastus2.azurecontainerapps.io/mcp` |
| Authentication method | **Bearer token** |
| Token | `not-required` (any non-empty string; MCP server ignores it). If validation fails, use the Grafana SA token: `glsa_SkH1KcoKzOHFfMc8hJRGqZ8Ay36bE7ao_f5fadede` |

Click **Validate connection** → green checkmark → **Save**.

### Jira MCP

| Field | Value |
|---|---|
| Name | `jira-mcp` |
| Connection type | **Streamable-HTTP** |
| URL | `https://ca-mcp-jira.icymeadow-96da5d2b.eastus2.azurecontainerapps.io/mcp` |
| Authentication method | **Bearer token** |
| Token | The actual Jira API token (see below). The `mcp-atlassian` image passes bearer tokens through to Jira. |

**CRITICAL:** Use the real Jira API token, not a placeholder. The newer
`mcp-atlassian` image forwards the bearer token from the incoming request
to Jira as the auth credential. Using `not-required` will cause silent
auth failures when the agent tries to create tickets.

```text
<your-jira-api-token>   # generate at https://id.atlassian.com/manage/api-tokens
```

Click **Validate connection** → green checkmark → **Save**.

## Step 3 — Create DiagnosticExpert sub-agent (~5 min)

Navigate to **Builder → Agent Canvas → + Create subagent**.

> **Note (March 2026):** The UI renamed "Subagent Builder" to
> **Agent Canvas**. The "+ Create subagent" button is at the bottom of
> the canvas view.

### Basic info

| Field | Value |
|---|---|
| Name | `DiagnosticExpert` |

### Handoff Instructions

```text
Hand off to DiagnosticExpert when the user needs to investigate an incident,
query Grafana/Loki logs, create a Jira ticket, or diagnose application errors.
```

### Instructions

```text
You are a diagnostic expert that investigates incidents using Grafana logs
and creates Jira tickets for tracking.

WORKFLOW:
1. When given an incident or alert, use grafana-mcp to query Loki logs for
   relevant error patterns
2. Analyze the logs to identify root cause indicators
3. Summarize findings with timestamps, error counts, and affected services
4. Use jira-mcp to create a ticket with the diagnosis details

LOG QUERY PATTERNS:
- For errors: {job="your-app"} |= "error" | json
- For specific service: {service_name="<service>"} | json
- Time-based: Use the last 1 hour unless specified otherwise

JIRA TICKET FORMAT:
- Project: Use the project key provided by the user
- Summary: "[Incident] <brief description>"
- Description: Include timeline, error samples, affected components,
  and recommended actions
- Priority: Based on error severity and impact

Always explain your reasoning and provide actionable recommendations.
```

### Tools

Select **all tools** from both `grafana-mcp` and `jira-mcp` connectors.
As of March 2026, Grafana MCP exposes 56 tools. Total with Jira + built-in
Azure tools is ~127. Select All when prompted and also add useful built-in
tools (CheckIfResourceExists, CheckTcpConnectivity, etc.).

## Step 4 — Upload knowledge file (~1 min)

1. In the sub-agent, go to **Knowledge** section
2. Upload: `grocery-sre-demo/knowledge/loki-queries.md`
3. Tags: `loki`, `queries`, `logging`

## Step 4.5 — Generate Loki log data (before testing)

Loki may be empty after a long idle period. Generate test data first:

```bash
# Mixed logs (info + warn + errors) — recommended
python scripts/generate_loki_logs.py --count 100

# Errors only (429 rate-limit scenarios)
python scripts/generate_loki_logs.py --count 50 --errors-only
```

Alternatively, trigger errors through the web UI:

```bash
curl -X POST "https://ca-api-ps64h2ydsavgc.icymeadow-96da5d2b.eastus2.azurecontainerapps.io/api/demo/trigger-rate-limit"
```

## Step 5 — Test in Playground (~3 min)

Switch to the **Test playground** tab (top bar in Agent Canvas).

Paste this prompt:

```text
My container app ca-api-ps64h2ydsavgc in resource group rg-aqsre is
experiencing rate limit errors from a supplier API when checking product
inventory. Can you investigate the logs from the last hour?
```

When the agent asks for a Jira project key, reply:

```text
Yes, please create a Jira ticket in project SCRUM
```

Verify the agent:

1. Queries Grafana MCP (Loki logs)
2. Analyzes error patterns
3. Creates a Jira ticket in project **SCRUM**
4. Returns a summary with the ticket link

## Cleanup (when done testing)

```bash
az resource delete \
  --resource-group rg-aqsre \
  --name aq-main \
  --resource-type Microsoft.SreAgent/agents
```

Or delete from the Azure Portal: SRE Agent resource → Delete.

Everything else in `rg-aqsre` stays deployed for next time.

## Troubleshooting — Known Blockers (March 2026)

### Container App ImagePullBackOff

**Symptom:** Container Apps (especially `ca-web`) show `Pending:ImagePullBackOff`
after the SRE Agent has been deleted and recreated, or after a long idle
period.

**Cause:** ACR admin password was rotated or the stored secret is stale.

**Fix:**

```bash
# Get current ACR password
ACR_PASS=$(az acr credential show --name crps64h2ydsavgc \
  --query "passwords[0].value" -o tsv)

# Re-set credentials on the affected container app
az containerapp registry set \
  --name ca-web-ps64h2ydsavgc \
  --resource-group rg-aqsre \
  --server crps64h2ydsavgc.azurecr.io \
  --username crps64h2ydsavgc \
  --password "$ACR_PASS"

# Restart the revision
REVISION=$(az containerapp revision list \
  --name ca-web-ps64h2ydsavgc \
  --resource-group rg-aqsre \
  --query "[0].name" -o tsv)

az containerapp revision restart \
  --name ca-web-ps64h2ydsavgc \
  --resource-group rg-aqsre \
  --revision "$REVISION"
```

Repeat for `ca-api-ps64h2ydsavgc` if it also shows ImagePullBackOff.

### Jira MCP: "Invalid user Jira token or configuration"

**Symptom:** Agent successfully queries Grafana logs but fails to create
Jira tickets. Error in `ca-mcp-jira` logs:
`Invalid user Jira token or configuration: Unable to get current user account ID`

**Cause:** The newer `mcp-atlassian` image passes the SRE Agent's bearer
token through to Jira as the auth credential. If you used a placeholder
like `not-required`, the Jira API rejects it.

**Fix:** Edit the `jira-mcp` connector in SRE Agent and set the bearer
token to the **actual Jira API token** (see Step 2 above). Re-validate.

**How to verify:** Check container logs:

```bash
az containerapp logs show --name ca-mcp-jira \
  --resource-group rg-aqsre --tail 30
```

### Loki returns empty results

**Symptom:** Agent reports no logs found or Loki appears empty.

**Cause:** Logs expire or the app hasn't generated recent entries.

**Fix:** Run `python scripts/generate_loki_logs.py --count 100` to
populate Loki with fresh test data before testing.

### Connector auth is now mandatory

**Symptom:** Cannot add MCP connector without an authentication method.

**Cause:** The March 2026 SRE Agent portal UI requires **Bearer token**
or **Custom headers** — there is no "None" option.

**Fix:** For Grafana MCP, use any non-empty string or the Grafana SA
token. For Jira MCP, use the **real Jira API token** (see above).

### Available Jira project keys

To find valid project keys:

```bash
curl -s -u "arturoqu@microsoft.com:<JIRA_API_TOKEN>" \
  "https://aq-r2d2.atlassian.net/rest/api/3/project" \
  | python3 -c "import sys,json; \
    [print(f'{p[\"key\"]:15s} {p[\"name\"]}') \
    for p in json.load(sys.stdin)]"
```

As of March 2026, the only project is **SCRUM**.
