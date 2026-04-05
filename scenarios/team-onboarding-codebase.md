# Scenario: Team Onboarding — Codebase Exploration

## Overview

This scenario walks through connecting the `grocery-sre-demo` repository to the SRE Agent
and completing the **Team Onboarding** interview. By the end, the agent has built persistent
memory files (`architecture.md`, `team.md`, `debugging.md`) that it references automatically
in every future investigation — no need to re-explain the system each session.

This maps directly to **Use Case #2** discussed with Zafin: *"going through the codebase and
helping engineers"* — specifically the team ramp-up and knowledge capture phase that
precedes autonomous SRE investigation.

**Reference docs:**
- [Team onboarding for Azure SRE Agent](https://learn.microsoft.com/en-us/azure/sre-agent/team-onboard)
- [Memory and knowledge](https://learn.microsoft.com/en-us/azure/sre-agent/memory)

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| SRE Agent created | At least one agent instance in your Azure portal |
| Repository connected | GitHub repo connected during agent setup (Step 1) |
| Azure subscription linked | `rg-aqsre` or equivalent resource group connected |
| Grafana + Loki MCP running | So the agent can cross-reference logs with code context |

> **Tip:** The agent works without a connected repo, but the onboarding interview and
> resulting `architecture.md` are far richer when codebase exploration runs automatically.

---

## The Grocery SRE Demo Codebase

This is the repository the agent will explore during onboarding:

```
grocery-sre-demo/
├── src/
│   ├── api/              # Node.js Express API — rate limiting, product catalog, health
│   │   ├── index.js      # Main entry point + /api/demo/* trigger endpoints
│   │   └── package.json  # Dependencies: express, axios, pino (structured logging)
│   └── web/              # Static web frontend served via Express
│       └── public/
│           └── index.html  # Demo UI with incident trigger buttons
├── knowledge/
│   └── loki-queries.md   # LogQL patterns — this is the agent's "runbook" today
├── infra/
│   ├── main.bicep        # azd entry point
│   ├── resources.bicep   # Container Apps, Loki, ACR, Managed Identity
│   └── mcp-*.bicep       # Grafana MCP + Jira MCP deployment
└── dashboards/
    └── sre-troubleshooting-cockpit.json  # Grafana dashboard definition
```

---

## Step 1 — Connect the Repository During Agent Setup

1. In the Azure portal, navigate to your SRE Agent instance.
2. In **Step 1: Create and set up**, select **Add data source → Code repository**.
3. Authenticate with GitHub and select `Arturo-Quiroga-MSFT/SRE-AGENT-JAN-2026`
   (or the fork/org copy for Zafin's environment).
4. Select **Done and go to agent**.

The agent immediately starts exploring the repository. A **progress indicator** appears in
the Team onboarding thread pinned to your Favorites sidebar.

---

## Step 2 — What the Agent Explores Automatically

The agent reads the repo without any prompting. Expect it to find:

| What it reads | What it learns |
|--------------|----------------|
| `grocery-sre-demo/README.md` | Service overview, deployment method (azd), environment names |
| `src/api/index.js` | Express routes, rate limiter logic (`/api/products`), demo trigger endpoints |
| `src/api/package.json` | Runtime: Node.js 18+, dependencies: `express`, `axios`, `pino-http` |
| `src/web/server.js` | Static file server, health endpoint at `/health` |
| `knowledge/loki-queries.md` | Existing LogQL runbooks for 429, OOMKill, circuit breaker scenarios |
| `infra/resources.bicep` | Container Apps env name, Loki URL, ACR name, Managed Identity |
| `infra/mcp-grafana/` | Grafana MCP image path, GRAFANA_URL env var pattern |
| `dashboards/*.json` | Grafana panel names + Loki datasource UID |

### Expected agent summary (after exploration):

```
I explored the grocery-sre-demo repository. Here's what I found:

Architecture:
- Two-tier app: Node.js API (ca-api-*) + static web frontend (ca-web-*)
- Deployed to Azure Container Apps in environment cae-*
- Loki (ca-loki-*) as log aggregator, exposed via HTTP
- Two MCP servers: ca-mcp-grafana (Grafana MCP) and ca-mcp-jira (Atlassian Jira)
- Infrastructure provisioned via azd + Bicep

Key operational endpoints:
- GET  /api/products          → product catalog (subject to rate limiting)
- POST /api/demo/trigger-rate-limit   → simulates 429 storm
- POST /api/demo/cpu-stress           → CPU load simulation
- GET  /health                → liveness probe

Logging:
- Structured JSON via pino-http
- Labels: app="grocery-api", level="error"|"info"|"warn"
- Key error codes: SUPPLIER_RATE_LIMIT_429, CIRCUIT_OPEN

Saved to memory as architecture.md.
```

---

## Step 3 — Team Context Interview

After codebase exploration the agent starts the interview. Respond naturally — it extracts
structured data automatically.

### Suggested answers (adapt for Zafin's team):

```
Agent: Tell me about your team. What services do you own and how does on-call work?

You: We're the Platform Reliability team — four engineers. We own the grocery API,
     the web frontend, and the Loki+Grafana observability stack. On-call is a weekly
     rotation. We use Jira for incident tracking. Escalation goes to the senior engineer
     on-call, then to the engineering manager.

Agent: Got it. I've saved this:
  - Team: Platform Reliability, 4 engineers
  - Services: grocery-api, grocery-web, loki, grafana-mcp, jira-mcp
  - On-call: weekly rotation
  - Incident tracking: Jira (SCRUM project)
  - Escalation: Senior on-call → Engineering Manager
  Saved to team.md.
```

---

## Step 4 — Upload Runbooks / Operational Procedures

Upload or describe your incident procedures so the agent builds `debugging.md`.

### Option A — Upload a file

Click **+** → **Attach file** in the Team onboarding thread. Attach:

- `grocery-sre-demo/knowledge/loki-queries.md` — existing LogQL patterns
- Any runbook markdown you have

### Option B — Describe procedures in chat

```
You: When we see 429 errors from the supplier API, we first query Loki for
     SUPPLIER_RATE_LIMIT_429 in the last hour. If the count is above 20 we open
     a Jira incident, implement exponential backoff, and notify the supplier.

You: When a pod is OOMKilled we check the namespace with kubectl top pods, look
     at memory trends in Grafana over the last 24h, then adjust the Container App
     memory allocation and redeploy.

You: Circuit breaker errors (CIRCUIT_OPEN) mean the API is protecting itself from
     a downstream failure. First confirm the downstream is actually down, then
     check if the circuit has auto-reset before making any changes.
```

Expected agent response:

```
I've extracted and saved 3 procedures:

1. Supplier rate limiting (429): Query Loki → threshold check → Jira incident →
   backoff + supplier notification
2. OOMKill response: kubectl top pods → Grafana memory trend → resize + redeploy
3. Circuit breaker: Confirm downstream health → wait for auto-reset → intervene only
   if needed

Saved to debugging.md.
```

---

## Step 5 — Verify Agent Memory

After onboarding, verify the three persistent memory files were created:

```
Ask the agent:
"What do you know about our codebase?"
"Who is on call and how do we escalate?"
"Walk me through how we handle a 429 incident."
```

The agent should answer from memory **without re-reading the repo or asking you again**.

### Memory files created:

| File | Contents |
|------|---------|
| `architecture.md` | Service map, routes, logging labels, infra topology |
| `team.md` | Team name, size, services owned, Jira project, escalation path |
| `debugging.md` | 429 runbook, OOMKill runbook, circuit breaker procedure |

---

## Step 6 — Test: Incident with Full Context

Trigger a rate-limit incident **after** onboarding and compare the agent's response to a
cold-start (no memory) session.

```bash
# Trigger
API_URL=$(az containerapp list -g rg-aqsre \
  --query "[?contains(name,'ca-api')].properties.configuration.ingress.fqdn" \
  -o tsv | head -1)

curl -X POST "https://$API_URL/api/demo/trigger-rate-limit"
```

Then ask the agent:

```
"We're seeing 429 errors on ca-api. Investigate and create a Jira ticket."
```

**Expected difference vs. cold-start:**
- Agent already knows the Loki label scheme (`app="grocery-api"`) — no setup queries
- Agent knows error code `SUPPLIER_RATE_LIMIT_429` from `debugging.md`
- Agent knows to open a Jira SCRUM ticket (from `team.md`)
- Agent references the exact runbook steps it stored in `debugging.md`
- Response time faster; fewer clarifying questions

---

## Relevance to Zafin Use Case #1 (Cloud Services Automation)

This scenario is the **foundation** that enables autonomous SRE actions. The progression is:

```
Team Onboarding (this scenario)
        │
        ▼
Agent has architecture.md + team.md + debugging.md
        │
        ▼
Human-in-the-loop investigation (rate-limit, OOMKill, degradation scenarios)
        │
        ▼
T1 Automation: agent executes low-risk runbook steps without human gate
(Phase 2 — after trust is established)
```

George Mathew's goal of getting *"a few hundred users"* before a public reference is
achievable at the "human-in-the-loop investigation" tier. The codebase onboarding scenario
is the entry point that makes that tier work well for Zafin's engineering team.

---

## Troubleshooting

| Issue | Likely Cause | Fix |
|-------|-------------|-----|
| Team onboarding thread not visible | Setup not fully completed | Go to Complete your setup first |
| Agent says "I couldn't find a repository" | Repo not connected or auth expired | Re-add GitHub connector in agent settings |
| `architecture.md` missing or sparse | Repo has no README or sparse structure | Tell the agent about missing directories in chat (see Step 2) |
| Knowledge base files no longer visible in UI | Known platform bug (as of April 2026) | Files still active; raise Azure support ticket per Zoya's issue (SCRUM open item) |
| Repository connector stays "Pending" | Known indexing issue (as of April 2026) | Use MCP server alternative; raise support ticket |

---

## Related Scenarios

- [rate-limit-incident.md](rate-limit-incident.md) — First investigation after memory is built
- [service-degradation.md](service-degradation.md) — CPU/memory incident using architecture context

---

*Last updated: April 5, 2026*  
*Reference: [Azure SRE Agent docs — Team onboarding](https://learn.microsoft.com/en-us/azure/sre-agent/team-onboard)*
