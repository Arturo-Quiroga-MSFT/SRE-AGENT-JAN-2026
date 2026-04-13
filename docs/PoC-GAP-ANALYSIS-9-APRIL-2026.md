
Here's the full gap analysis mapping your PoC work against the **Cloud Services Automation Roadmap: 2026**.

---

## Roadmap vs. PoC Coverage

### 1) Reactive Support Agent Experience

| Roadmap Component | Status | Evidence in Repo |
|---|---|---|
| **Ticket auto-enrichment** (Incident Console link in Jira) | **Partial** | Agent creates Jira tickets with Grafana dashboard links and Loki queries, but no auto-triggered link injection on ticket creation. Tickets are created *by* the agent, not enriched on inbound tickets from Zendesk. |
| **Infra Debug Bundle Agent** (auto-collect K8s events, node status, pod restarts, network, Azure infra signals) | **Partial** | AKS testbed validates KQL queries for `KubePodInventory`, `ContainerLog`, pod restarts, and Azure Monitor alerts. But there is no packaged "debug bundle" pipeline (collect → blob → metadata → Jira attachment). Evidence is ad-hoc per investigation, not a reusable artifact. |
| **Application Context Agent** (release version, feature flags, dependency health, trace exemplars, similar incidents) | **Partial** | Agent pulls current image tag via `az containerapp show`, and the `knowledge/grocery-architecture.md` documents endpoints, dependencies, and fault injection scenarios. But no automated *similar incident search* (Jira/Confluence history), no Tempo trace integration, no feature flag/config delta detection. |
| **Orchestrator / Classifier Agent** (fault-domain classification: INFRA vs APP vs MIXED) | **Done** | [DIAGNOSTIC_EXPERT_INSTRUCTIONS_V2.md](https://github.com/Arturo-Quiroga-MSFT/SRE-AGENT-JAN-2026/blob/main/docs/DIAGNOSTIC_EXPERT_INSTRUCTIONS_V2.md) explicitly implements the INFRA / APP / MIXED classification with confidence scores. Live-tested on 429 incidents. |
| **SRE Analysis Agent** (mitigation recommendations with runnable commands, risk assessment, rollback steps) | **Done** | DiagnosticExpert produces structured output with ready-to-run `az containerapp` commands, rollback plans, and "What to Monitor (Next 30 min)" — exactly matching the roadmap spec. See [RCA-GROCERY-API-429-2026-03-18.md](https://github.com/Arturo-Quiroga-MSFT/SRE-AGENT-JAN-2026/blob/main/docs/RCA-GROCERY-API-429-2026-03-18.md). |
| **RCA Agent** (Living RCA draft, continuous timeline, customer comms, evidence links) | **Done** | [RCA_AGENT_INSTRUCTIONS.md](https://github.com/Arturo-Quiroga-MSFT/SRE-AGENT-JAN-2026/blob/main/docs/RCA_AGENT_INSTRUCTIONS.md) defines the sub-agent with all 9 RCA sections. The March 18 RCA includes timeline, impact assessment, corrective actions, customer communication draft, and evidence links. |
| **Troubleshooting Cockpit** (Grafana dashboard, golden signals, deploy markers, deep links) | **Partial** | [sre-troubleshooting-cockpit.json](https://github.com/Arturo-Quiroga-MSFT/SRE-AGENT-JAN-2026/blob/main/dashboards/sre-troubleshooting-cockpit.json) deployed with error rate, warning rate, error-by-code, and 429 panels. Missing: deploy markers overlay, auto-zoom to incident window, and customer-scoped error rate panel. |
| **Zendesk integration** (customer ticket entry point) | **Not Done** | No Zendesk integration anywhere in the repo. |
| **Confluence integration** (RCA storage, runbook search, known-error matching) | **Not Done** | RCA documents are generated as markdown in the agent thread, not stored in Confluence. No Confluence MCP or API integration. |
| **KPI tracking** (MTTA, MTTT, MTTR measurement) | **Not Done** | [PROJECT_SUMMARY.md](https://github.com/Arturo-Quiroga-MSFT/SRE-AGENT-JAN-2026/blob/main/docs/PROJECT_SUMMARY.md) sets targets (MTTT <15 min, MTTR 30-50% reduction) and tracks agent response times (5-12 min), but no automated KPI dashboard or measurement pipeline. |

### 2) Proactive Support Agent Experience

| Roadmap Component | Status | Evidence in Repo |
|---|---|---|
| **Health Sweep Engine** (every 5-15 min per cluster/customer) | **Not Done** | No scheduled health sweep. The [PHASE5_ACTUAL_SETUP_GUIDE.md](https://github.com/Arturo-Quiroga-MSFT/SRE-AGENT-JAN-2026/blob/main/docs/PHASE5_ACTUAL_SETUP_GUIDE.md) mentions a "Daily Health Check" scheduled task concept, but it's listed as optional and not implemented. |
| **Fleet Health Cockpit** (green/yellow/red by cluster and customer) | **Not Done** | No fleet-level dashboard. Cockpit is scoped to one service (`grocery-api`). |
| **Predictive Findings** (memory creep, CPU saturation trends, error budget burn) | **Not Done** | No trend-based anomaly detection or predictive analytics. |
| **Database risk detection** (bloat, lock contention, vacuum, wraparound) | **Not Done** | No database monitoring — the Grocery API demo has no real database. |
| **Action Tickets** (auto-create Jira tasks from proactive findings) | **Not Done** | Jira tickets are only created reactively during investigations. |
| **Prevention reporting** (weekly "Top 10 prevented incidents") | **Not Done** | No prevention/proactive reporting. |
| **Azure Monitor alerts → incident auto-creation** | **Partial** | AKS testbed has 3 alert rules (pod restarts, node CPU >80%, no ready pods). Grafana has 1 alert rule (429 errors). But alert → agent auto-investigation pipeline is documented but not wired end-to-end. |

### 3) IAM/PIM Agent Experience

| Roadmap Component | Status | Evidence in Repo |
|---|---|---|
| **PIM request ingestion + validation** | **Not Done** | Zero PIM/IAM automation in the repo. |
| **Ticket legitimacy validation** (Jira reference check) | **Not Done** | — |
| **Scope/duration/SoD policy engine** | **Not Done** | — |
| **Risk scoring + anomaly detection** | **Not Done** | — |
| **IAM/PIM Cockpit dashboard** | **Not Done** | — |
| **Audit trail storage** | **Not Done** | — |

### 4) Agent Roles and Responsibilities

| Roadmap Agent | Status | PoC Equivalent |
|---|---|---|
| **1. Support Intake Agent** (normalize tickets) | **Not Done** | No Zendesk/intake normalization layer. |
| **2. Infra Debug Bundle Agent** | **Partial** | Agent queries infra signals ad-hoc, not as a packaged bundle. AKS testbed covers K8s events + Log Analytics. |
| **3. Application Context Agent** | **Partial** | Agent has architecture knowledge and can query logs, but no prior-incident similarity or trace correlation. |
| **4. Orchestrator / Classifier Agent** | **Done** | DiagnosticExpert with INFRA/APP/MIXED classification. |
| **5. SRE Analysis Agent** | **Done** | DiagnosticExpert + structured mitigation output with commands. |
| **6. RCA & Comms Agent** | **Done** | RCA Agent sub-agent instructions + live RCA output (March 18 incident). |
| **7. IAM/PIM Agent** | **Not Done** | — |

### 5) Tooling Integration Map

| System | Status | Evidence |
|---|---|---|
| **Zendesk** | **Not Done** | No integration. |
| **Jira** | **Done** | Jira MCP connector via `ca-mcp-jira`, creates/updates tickets. |
| **Confluence** | **Not Done** | No integration. |
| **Log Analytics / Loki** | **Done** | Loki for Container Apps (via Grafana MCP), Log Analytics for AKS testbed (via KQL). |
| **Grafana** | **Done** | Azure Managed Grafana with Loki datasource, Troubleshooting Cockpit dashboard, alert rules. |
| **Mimir / Prometheus** | **Partial** | Grocery API exposes `/metrics` endpoint with Prometheus metrics, but no Prometheus/Mimir datasource is scraped or connected to Grafana. |
| **Tempo** | **Not Done** | No distributed tracing. |
| **ServiceNow** | **Done** | [servicenow-integration.md](https://github.com/Arturo-Quiroga-MSFT/SRE-AGENT-JAN-2026/blob/main/scenarios/servicenow-integration.md) documents the built-in ServiceNow connector with full lifecycle (auto-pick up incident → investigate → post work notes → resolve). |

### 6) Deliverables

| Deliverable | Status | Notes |
|---|---|---|
| **D1: Reactive "Incident-to-Recommendation"** | **~70% Done** | Jira integration ✅, debug bundle (ad-hoc) ✅, app context (partial), orchestrator routing ✅, SRE recommendation ✅. Missing: Zendesk, Confluence similarity, packaged debug bundle. |
| **D2: Proactive "Fleet Health & Prediction"** | **~5% Done** | Only the alert rules exist. No health sweep, no risk register, no Jira auto-tasking. |
| **D3: RCA + Customer Communication** | **~75% Done** | Living RCA draft ✅, customer update draft ✅, evidence links ✅. Missing: Confluence storage, periodic auto-generated updates, final RCA template as a workflow. |
| **D4: IAM/PIM Governance Automation** | **Not Done** | — |

### 7) Guardrails

| Guardrail | Status | Evidence |
|---|---|---|
| **Tenant scoping** | **Partial** | Queries scoped by `app` label, Container App name, resource group. No multi-tenant isolation. |
| **RBAC** | **Done** | AKS testbed assigns 4 scoped RBAC roles. Agent uses managed identity. |
| **PII/secret redaction** | **Not Done** | Jira API tokens appeared in plain text in [PHASE4_STATUS.md](https://github.com/Arturo-Quiroga-MSFT/SRE-AGENT-JAN-2026/blob/main/docs/PHASE4_STATUS.md). |
| **Immutable audit log** | **Not Done** | No audit log beyond Jira ticket history and agent thread transcripts. |
| **Graceful degradation** | **Partial** | DiagnosticExpert instructions include handoff rules on failure, but no formal degradation pattern. |
| **Human-in-the-loop** | **Done** | Agent recommends; humans execute. Review mode by default. |

### 8) MVP Phasing

| Phase | Status | Coverage |
|---|---|---|
| **Phase 1** (Reactive foundation) | **~65%** | Incident Console + Cockpit ✅, Infra Debug Bundle (partial), RCA/Comms drafting ✅, PIM ❌ |
| **Phase 2** (Classification + similarity) | **~40%** | Orchestrator classification ✅, App Context Agent (partial), PIM risk scoring ❌ |
| **Phase 3** (Proactive health sweep) | **~5%** | Fleet cockpit ❌, Jira action tickets ❌, PIM dashboards ❌ |
| **Phase 4** (Predictive + optimization) | **Not Started** | Trend forecasting ❌, Runbook coverage analytics ❌ |

---

## Summary Scorecard

| Roadmap Section | Addressed | Partial | Not Done |
|---|---|---|---|
| 1. Reactive Support Agent | 3 | 4 | 3 |
| 2. Proactive Support Agent | 0 | 1 | 5 |
| 3. IAM/PIM Agent | 0 | 0 | 6 |
| 4. Agent Roles (7 agents) | 3 | 2 | 2 |
| 5. Tooling Integrations (7 tools) | 4 | 1 | 2 |
| 6. Deliverables (4) | 0 | 2 | 2 |
| 7. Guardrails (6) | 2 | 2 | 2 |

**Bottom line:** Your PoC strongly validates the **reactive investigation workflow** (Roadmap Section 1, Phase 1-2) — the fault classification, SRE analysis, RCA generation, Jira/ServiceNow integration, and Grafana/Loki observability are all working end-to-end. The biggest gaps are:

1. **Proactive monitoring** (Section 2) — essentially untouched
2. **IAM/PIM** (Section 3) — entirely untouched
3. **Zendesk + Confluence** — the two integration points assumed in the reactive flow
4. **Distributed tracing (Tempo)** and **Prometheus/Mimir scraping** — observability gaps
5. **Packaged debug bundle pipeline** — evidence collection is ad-hoc today vs. the roadmap's automated bundle concept



