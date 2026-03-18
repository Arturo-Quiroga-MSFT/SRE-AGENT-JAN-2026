---
title: "Arturo + Ankit Sync — March 18, 2026"
description: "Discussion framework for the working session covering progress since March 13, work division, blockers, and demo planning for Zafin."
author: Arturo Quiroga
ms.date: 2026-03-18
ms.topic: reference
---

## Meeting goal

Align on what is done, divide remaining work, and agree on a timeline
to demo for George.

---

## Agenda (suggested 60 min)

| Min | Topic | Goal |
|-----|-------|------|
| 0-5 | Quick recap of March 13 action items | Shared context |
| 5-15 | Walk through progress since Jan PoC | Show running artifacts |
| 15-30 | Review gap analysis table and agree on ownership | Firm assignments |
| 30-45 | Technical decisions and blockers | Unblock each other |
| 45-55 | Demo plan and timeline for George | Ship date |
| 55-60 | Immediate next actions | Clear to-dos |

---

## Section 1 — Progress since January PoC

### What was delivered in January

- Demo app (Grocery Store) on Container Apps (web + API)
- Loki log aggregation + Azure Managed Grafana
- Grafana MCP server (Streamable-HTTP)
- Jira MCP server (FastMCP)
- SRE Agent (`aq-main`) with DiagnosticExpert sub-agent
- Two working scenarios: Rate Limit Incident, Service Degradation

### What was done March 16-18 (Arturo)

| Item | Status | Artifact |
|------|--------|----------|
| Gap analysis vs Zafin 2026 roadmap | Done | `partner-context/ZAFIN_GAP_ANALYSIS_MARCH_2026.md` |
| SRE Agent recreated after cost-savings deletion | Done | Agent `aq-main`, both MCP connectors reconnected |
| DiagnosticExpert v2 instructions | Done — deployed in Agent Canvas | `docs/DIAGNOSTIC_EXPERT_INSTRUCTIONS_V2.md` |
| RCA Agent (net new sub-agent) | Done — created, tested, generating 213-line RCA docs | `docs/RCA_AGENT_INSTRUCTIONS.md` |
| Troubleshooting Cockpit dashboard (8 panels) | Done — imported into Grafana, all panels rendering | `dashboards/sre-troubleshooting-cockpit.json` |
| Loki log generator script | Done | `scripts/generate_loki_logs.py` |
| Architecture diagrams (Mermaid + Draw.io) | Done | `docs/sre-agent-architecture.*` |
| Quick-recreate runbook | Done | `docs/SRE_AGENT_QUICK_RECREATE.md` |

### Verified working (March 18)

- Troubleshooting Cockpit imported into Grafana — all 8 panels rendering
  with live Loki data (error rate, warning rate, error code bars,
  pie chart, error logs, warning logs, heatmap, rate limit timeline)
- RCAAgent created in Agent Canvas and tested — generates 213-line RCA
  documents including executive summary, timeline, root cause, corrective
  actions (10 items), and customer communication draft
- RCAAgent self-identified operational gaps: zero alert rules, no
  Prometheus datasource, Loki patterns API 404, no Jira integration —
  this is exactly the kind of proactive insight the roadmap calls for
- RCAAgent then **executed its own corrective action** — created a
  Grafana alert rule for 429 detection (>5 errors in 5 min, folder
  "SRE Alerts", severity=high) via grafana-mcp tools autonomously
- Full reactive flow working: incident prompt → DiagnosticExpert
  investigation → RCAAgent document generation → corrective action
  execution

---

## Section 2 — Gap analysis: roadmap vs PoC

Full details in `partner-context/ZAFIN_GAP_ANALYSIS_MARCH_2026.md`.
Summary below for discussion.

### Reactive support (Experience 1)

| Step | What Zafin wants | Jan PoC | March progress | Remaining gap |
|------|------------------|---------|----------------|---------------|
| 1 | Troubleshooting Cockpit URL in Jira ticket | None | **Dashboard deployed in Grafana** | Parameterized URL injection into Jira tickets |
| 2a | Infra Debug Bundle Agent | None | None | **Ankit candidate** — new sub-agent |
| 2b | Application Context Agent | None | None | **Ankit candidate** — new sub-agent |
| 3 | Orchestrator/Classifier Agent | None | None | Depends on 2a + 2b outputs |
| 4 | SRE Analysis Agent (structured mitigations) | Partial | **DiagnosticExpert v2 deployed + tested** | Done for demo scope |
| 5 | RCA Agent (Living RCA, customer comms) | None | **RCAAgent deployed + tested (213-line RCA)** | Confluence storage (defer to P3) |

### Troubleshooting Cockpit (Experience 2)

| Item | March progress | Remaining |
|------|----------------|-----------|
| Golden signals dashboard | **Deployed and verified** — 8 panels rendering | Add deploy/config change markers |
| Auto-zoom to incident window | Not started | Parameterized URL with time range |
| "Analyze current view" button | Not started | Grafana plugin or deep link |

### Proactive support (Experience 3) — not started

- Health sweep every 5-15 min
- Predictive findings (memory creep, CPU, error budget burn)
- DB risk detection
- Action Tickets (auto-created Jira with evidence)

### IAM/PIM Agent (Experience 4) — not started, propose deferring

---

## Section 3 — Proposed work division

Carried forward from the gap analysis, open for discussion.

### Arturo

| Priority | Item | Status |
|----------|------|--------|
| P1 | Ticket enrichment + Cockpit link injection | In progress |
| P1 | DiagnosticExpert v2 (structured output, commands) | **Done — deployed + tested** |
| P2 | Orchestrator/Classifier logic | Not started |
| P3 | RCA Agent + customer-facing comms | **Done — deployed + tested** |

### Ankit

| Priority | Item | Status |
|----------|------|--------|
| P1 | Infra Debug Bundle Agent | Not started |
| P2 | Application Context Agent | Not started |
| P3 | Proactive Health Sweep | Not started |

### Shared

| Item | Notes |
|------|-------|
| Replace Loki with KQL (Log Analytics) | Required for Zafin prod. Demo can stay on Loki for now |
| Grafana Troubleshooting Cockpit dashboard | Arturo has v1, may need Ankit's input on K8s panels |
| Confluence MCP connector | Needed for RCA Agent (Living RCA storage) |
| PR to `microsoft/sre-agent` public repo | Per March 13 agreement — both contribute samples |

---

## Section 4 — Technical decisions to make together

### Decision 1 — Loki vs KQL for the demo

- **Option A:** Keep Loki for demo simplicity, note KQL as production
  adaptation.
- **Option B:** Switch to KQL now so the demo is closer to Zafin's stack.
- **Recommendation:** Option A for speed. Zafin knows their prod uses Log
  Analytics; the patterns transfer.

### Decision 2 — Jira MCP auth issue

- `mcp-atlassian` v0.21.0 broke bearer-token passthrough. Agent's own token
  overrides env var credentials.
- **Options:**
  - Pin an older image (`v0.16.x`-`v0.18.x`) where env vars worked
  - Build a header-stripping proxy sidecar
  - Wait for upstream fix
  - Skip Jira integration in demo, show ticket creation as mock
- **Need Ankit's input:** Does Ankit's work need Jira MCP? If so, we need
  to resolve this.

### Decision 3 — Where to create sub-agents

- Agent Canvas in Azure portal is the current UI for sub-agents.
- Each sub-agent needs: name, instructions, connectors, handoff config.
- **Question for Ankit:** Has he used Agent Canvas before? Need a walkthrough?

### Decision 4 — Demo scope for George

- What do we show?
  - Must-have: Reactive flow (incident → diagnosis → mitigation → RCA)
  - Nice-to-have: Proactive sweep, Cockpit dashboard, Jira integration
- **Proposal:** Focus on the reactive flow end-to-end. That is the highest
  value for George.

---

## Section 5 — Known blockers

| Blocker | Impact | Proposed resolution |
|---------|--------|---------------------|
| Jira MCP auth (v0.21.0 bearer passthrough) | Cannot create/enrich tickets from SRE Agent | Pin older image or proxy. See Decision 2 |
| ca-api container was "Activating" | API backend may not be reachable | Check and fix ACR credentials if needed |
| Confluence MCP not set up | RCA Agent cannot store Living RCA docs | Defer to P3 or mock output as markdown |
| No KQL data source | Demo uses Loki; Zafin prod uses Log Analytics | Keep Loki for demo, document KQL migration path |

---

## Section 6 — Timeline proposal

| Milestone | Target date | Owner |
|-----------|-------------|-------|
| P1 items working in demo env | March 25 | Both |
| P2 items working | April 1 | Both |
| Internal dry run | April 2-3 | Arturo + Ankit |
| Demo with George | Week of April 7 | Arturo + Ankit (Deepthi/Poornika join) |
| PR to public `microsoft/sre-agent` repo | April 14 | Both |

*Dates are proposals — adjust based on Ankit's availability.*

---

## Section 7 — Immediate next actions (leave meeting with these)

| Action | Owner | By when |
|--------|-------|---------|
| ~~Import Cockpit dashboard into Grafana + test~~ | ~~Arturo~~ | ~~Done~~ |
| ~~Apply DiagnosticExpert v2 + RCA Agent in portal~~ | ~~Arturo~~ | ~~Done~~ |
| ~~Test full reactive flow end-to-end~~ | ~~Arturo~~ | ~~Done~~ |
| ~~Explore Grafana alerting rules for 429 detection~~ | ~~Arturo~~ | ~~Done — RCAAgent created it autonomously~~ |
| Start Infra Debug Bundle Agent design | Ankit | March 21 |
| Decide on Jira MCP fix approach | Both | March 19 |
| Share repo access with Ankit | Arturo | Today |
| Review gap analysis doc | Ankit | March 19 |
| Add parameterized Cockpit URL to Jira ticket enrichment | Arturo | March 21 |
| Configure Grafana notification contact point (Slack/email) | Arturo | March 21 |

---

## Reference links

- Repo: `https://github.com/Arturo-Quiroga-MSFT/SRE-AGENT-JAN-2026`
- SRE Agent portal: Azure Portal → SRE Agent → `aq-main`
- Azure Managed Grafana: `amg-ps64h2ydsavgc`
- Gap analysis: `partner-context/ZAFIN_GAP_ANALYSIS_MARCH_2026.md`
- March 13 meeting notes: `meetings-recaps/march-13-2026.md`
