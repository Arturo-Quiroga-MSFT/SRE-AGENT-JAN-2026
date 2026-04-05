# Scenario: ServiceNow Integration

## Overview

Connect a **ServiceNow Personal Developer Instance (PDI)** to the SRE Agent so it
automatically receives, investigates, and updates incidents — without any custom Bicep or
MCP servers. This is a **built-in first-class integration** in the SRE Agent portal.

This scenario is the key demo differentiator for Zafin: they are a fintech almost certainly
running ServiceNow in production. Showing the full lifecycle — incident fires in ServiceNow →
agent investigates → posts findings as work notes → resolves — is far more compelling for
their stakeholders than the Jira PoC.

**Reference docs:**
- [ServiceNow incident indexing in Azure SRE Agent](https://learn.microsoft.com/en-us/azure/sre-agent/servicenow)
- [Tutorial: Connect to ServiceNow](https://learn.microsoft.com/en-us/azure/sre-agent/tutorial-connect-servicenow)

---

## Step 0 — Get a Free ServiceNow Developer Instance

> **Do this first.** No cost, no credit card.

1. Go to **https://developer.servicenow.com**
2. Sign in or register a free account
3. Select **Start Building** → request a Personal Developer Instance (PDI)
4. Wait ~5 min for provisioning
5. Your instance URL will be: `https://dev<number>.service-now.com`
6. Note your admin username and password

> **Keep the PDI awake:** It hibernates after 10 days of inactivity. Log in or hit the "Wake"
> button at developer.servicenow.com → My Instance before any demo.

---

## Step 1 — Choose Authentication Method

| Method | Best for | Setup time |
|--------|----------|-----------|
| **Basic auth** (username + password) | PDI / dev / testing | ~5 min |
| **OAuth 2.0** | Production / security-conscious | ~10 min |

For demo/PDI use, **Basic auth is fine** and much faster. Use OAuth for any Zafin
production conversation.

---

## Step 2 — (Basic Auth) Create a Dedicated Integration User in ServiceNow

Avoid using the admin account directly.

1. In your PDI, navigate to **User Administration → Users**
2. Select **New** and fill in:
   - **User ID:** `sre-agent-integration`
   - **Password:** a strong password
   - **Roles:** add `itil` (gives incident read/write without full admin)
3. **Submit**

---

## Step 3 — Connect ServiceNow from the SRE Agent Portal

1. Go to your SRE Agent instance in the Azure portal
2. Left nav → **Settings → Incident platform**
3. Select **ServiceNow** from the dropdown
4. Keep **Authentication Type** as **Basic Authentication** (default)
5. Fill in:
   - **ServiceNow endpoint:** `https://dev<your-number>.service-now.com`
   - **Username:** `sre-agent-integration`
   - **Password:** the password you set above
6. Select **Save**

The portal validates connectivity immediately by fetching a real incident from your
instance. You get an error right away if credentials are wrong — no "setup and hope."

**Expected result:** Green status indicator — *"ServiceNow is connected"*

---

## Step 4 — Enable the Quickstart Response Plan

When prompted, enable the **Quickstart response plan**. This auto-creates a default plan:

| What it handles | Autonomy level |
|-----------------|---------------|
| Priority 2 (High) incidents | Autonomous — agent investigates without waiting for human |

You can edit this later. For demo purposes the default is fine.

### ServiceNow priority reference:

| Priority value | Label |
|---------------|-------|
| 1 | Critical |
| 2 | High |
| 3 | Moderate |
| 4 | Low |
| 5 | Planning |

---

## Step 5 — Seed Test Incidents in ServiceNow

The agent scans every minute for new incidents. Create some that mirror your existing
grocery-sre-demo scenarios.

### Option A — ServiceNow UI

Navigate to **Incidents → Create New** in your PDI and create:

**Incident 1 — Rate Limiting (mirrors rate-limit-incident.md)**
- Short description: `Grocery API returning 429 errors from FreshFoods supplier`
- Priority: `2 - High`
- Category: `Software`
- Description:
  ```
  Container app ca-api is receiving SUPPLIER_RATE_LIMIT_429 errors.
  55+ occurrences in the last hour. Affected endpoint: /api/products.
  Supplier: FreshFoods Wholesale. RetryAfter: 60s.
  ```

**Incident 2 — OOMKill (mirrors AKS testbed scenario B)**
- Short description: `Kubernetes pod OOMKilled in production namespace`
- Priority: `2 - High`
- Category: `Infrastructure`
- Description:
  ```
  Pod grocery-api-* in namespace production repeatedly OOMKilled.
  Memory limit 256Mi exceeded. Pod restart count: 8 in last 30 minutes.
  ```

**Incident 3 — Service Degradation**
- Short description: `Grocery API P95 latency exceeded 2 seconds`
- Priority: `3 - Moderate`
- Category: `Performance`
- Description:
  ```
  P95 response time on /api/products climbed from 200ms to 2.4s over last hour.
  No deployment in last 24h. CPU and memory appear nominal.
  ```

### Option B — ServiceNow REST API

```bash
SNOW_INSTANCE="https://dev<your-number>.service-now.com"
SNOW_USER="sre-agent-integration"
SNOW_PASS="<your-password>"

# Create a High priority incident
curl -s -X POST "$SNOW_INSTANCE/api/now/table/incident" \
  -u "$SNOW_USER:$SNOW_PASS" \
  -H "Content-Type: application/json" \
  -d '{
    "short_description": "Grocery API returning 429 errors from FreshFoods supplier",
    "priority": "2",
    "urgency": "2",
    "category": "software",
    "description": "Container app ca-api receiving SUPPLIER_RATE_LIMIT_429. 55+ errors in last hour."
  }' | python3 -m json.tool | grep '"number"'
```

---

## Step 6 — Watch the Agent Investigate

After creating a Priority 2 incident, the agent picks it up within **1 minute** (scan interval).

In the SRE Agent portal, a new **investigation thread** appears automatically for each
incident, linked from the Incidents view.

The agent will:
1. **Acknowledge** the incident in ServiceNow (status update)
2. **Query connected data sources** — Loki via Grafana MCP, Azure Monitor, etc.
3. **Form and validate hypotheses** based on `architecture.md` and `debugging.md` from team onboarding
4. **Post findings as work notes** (discussion entries) back to the ServiceNow incident
5. **Resolve or escalate** depending on the response plan configuration

### Agent capabilities with ServiceNow incidents:

| Capability | Description |
|-----------|-------------|
| Read incidents | Fetch details, related records, discussion history |
| Post work notes | Add investigation findings back to the incident |
| Acknowledge | Mark as acknowledged when investigation begins |
| Change priority | Adjust based on investigation findings |
| Resolve | Close with resolution notes after mitigation |

---

## Step 7 — Verify the Integration

After the agent processes an incident, check ServiceNow:

1. Open the incident in your PDI
2. Scroll to **Work Notes / Discussion Entries** — the agent's findings should appear here
3. Check **Incident state** — should have transitioned from `New` → `In Progress`

Ask the agent directly:

```
"Show me the ServiceNow incidents you've investigated."
"What did you find on the OOMKill incident?"
"Summarize open Priority 2 incidents and their current state."
```

---

## Step 8 — (Optional) OAuth 2.0 for Production Conversations

For any demo to Zafin where you want to show production-grade setup:

### Register OAuth app in ServiceNow:

1. In your PDI: **System OAuth → Application Registry → New**
2. Select **Create an OAuth API endpoint for external clients**
3. Fill in:
   - **Name:** `Azure SRE Agent`
   - **Redirect URL:** `https://logic-apis-eastus2.consent.azure-apim.net/redirect`
     *(replace `eastus2` with your SRE Agent's Azure region)*
   - **Active:** checked
4. **Submit** — note the **Client ID** and reveal + copy the **Client Secret immediately**
   (it may only show once)

### Configure OAuth in the SRE Agent portal:

1. Settings → Incident platform → ServiceNow
2. Set **Authentication Type** to **OAuth 2.0**
3. Copy the Redirect URL shown in the yellow info box → add to ServiceNow OAuth app
4. Enter Client ID + Client Secret
5. Select **Authorize** → sign in to ServiceNow in the popup
6. Select **Save** once the Authorize button changes to Save

---

## Comparison: ServiceNow vs. Jira in This Demo

| Aspect | Jira (current) | ServiceNow (this scenario) |
|--------|---------------|---------------------------|
| Setup | Custom MCP server + Bicep | Built-in portal integration |
| Ticket creation | Agent creates ticket via MCP tool call | Agent auto-picks up existing incidents |
| Investigation trigger | Human asks agent to investigate | **Automatic** on new incident (1 min scan) |
| Findings | Posted via Jira MCP comment tool | Posted as ServiceNow work notes natively |
| Relevance to Zafin | Dev-team familiarity | **Production ITSM match** |
| Cost for demo | Existing `ca-mcp-jira` Container App | Free PDI instance |

---

## Demo Script (5-minute version for Zafin)

```
1. "Here's a ServiceNow incident that just fired — Priority 2, grocery API rate limiting."
   [Show incident in ServiceNow PDI]

2. "The SRE Agent picks this up automatically — no one had to open the agent."
   [Switch to SRE Agent portal — show the investigation thread that appeared]

3. "It queried our Loki logs, cross-referenced the runbook it learned during onboarding,
    and posted its findings directly back into ServiceNow as work notes."
   [Show work notes in ServiceNow incident]

4. "The on-call engineer doesn't context-switch between tools. Everything is in ServiceNow."
   [Show resolved/in-progress state]

5. "For your environment, we'd connect your existing ServiceNow instance. 
    The agent scopes to your team's assignment group — it won't touch other teams' incidents."
```

---

## Troubleshooting

| Issue | Likely Cause | Fix |
|-------|-------------|-----|
| "ServiceNow is not connected" after Save | Wrong credentials or URL | Verify `https://dev<number>.service-now.com` (no trailing slash) and recreate integration user |
| No investigation threads appearing | PDI is hibernating | Wake the PDI at developer.servicenow.com → My Instance |
| OAuth authorization popup closes immediately | Redirect URL mismatch | Verify exact URL in ServiceNow OAuth app matches portal-provided URL |
| Agent posts work notes but incident stays "New" | Integration user missing `itil` role | Add `itil` role to `sre-agent-integration` user in ServiceNow |
| Only one incident platform active at a time | Portal limitation | If you want to keep Jira for Sprint tracking and ServiceNow for incidents, ServiceNow must be the active incident platform; Jira can still be used via MCP for ticket creation |

---

## Related Scenarios

- [rate-limit-incident.md](rate-limit-incident.md) — Same incident, triggered manually via Loki
- [team-onboarding-codebase.md](team-onboarding-codebase.md) — Build `debugging.md` so agent knows the runbooks before it investigates
- [service-degradation.md](service-degradation.md) — Good candidate for a Moderate priority (P3) ServiceNow incident

---

*Last updated: April 5, 2026*  
*Reference: [Azure SRE Agent docs — ServiceNow](https://learn.microsoft.com/en-us/azure/sre-agent/servicenow)*
