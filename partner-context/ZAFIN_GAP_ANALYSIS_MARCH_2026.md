---
title: "Zafin SRE Agent Gap Analysis: January PoC vs March 2026 Roadmap"
description: "Maps the January 2026 PoC deliverables against Zafin's full 2026 Automation Roadmap, identifies gaps, and proposes work division between Arturo and Ankit."
author: Arturo Quiroga
ms.date: 2026-03-16
ms.topic: concept
---

## Summary

Zafin's 2026 roadmap spans **two documents** and **two distinct workstreams**.
Only the SRE/Cloud Services workstream is in scope for the current engagement.
The Customer Enablement workstream is included here for awareness but is
not an action item for our team.

| Workstream | Document | In scope? |
|---|---|---|
| SRE & Cloud Services Automation | `SRE-Cloud Services Automation Roadmap 2026` | Yes |
| Customer Enablement Automation | `Customer Enablement Automation Roadmap Zafin` | No (awareness only) |

## What was delivered in January 2026

| Component | Status | Detail |
|---|---|---|
| Demo app (Grocery Store) | Deployed | Container Apps: API + Web frontend |
| Loki log aggregation | Deployed | Container App with pre-seeded log patterns |
| Grafana MCP server | Deployed | SSE endpoint on Container Apps |
| Jira MCP server | Deployed | SSE endpoint on Container Apps (FastMCP) |
| Azure Managed Grafana | Deployed | Service account + Loki data source configured |
| SRE Agent + DiagnosticExpert sub-agent | Deployed | Portal-based setup with knowledge file |
| Scenario: Rate Limit Incident | Working | Manual trigger, Loki query, Jira ticket creation |
| Scenario: Service Degradation | Working | Manual trigger, multi-query analysis, Jira ticket creation |

**Key limitation:** The January PoC is reactive-only, manually triggered, uses
Loki (not KQL), and creates new Jira tickets rather than enriching existing ones.

## Zafin's SRE Roadmap: full scope vs our PoC coverage

### Experience 1 — Reactive Support (Incident to Recommendation)

The roadmap defines a **five-step reactive flow**. The January PoC covers parts
of Steps 4 and 5 only.

| Roadmap Step | What Zafin wants | Jan PoC covers? | Gap |
|---|---|---|---|
| **Step 1** — Ticket auto-enrichment | Zendesk creates Jira Incident; a "Troubleshooting Cockpit" URL scoped to customer/cluster/namespace/time window auto-appears in the ticket | No | Need Grafana dashboard template + ticketing integration that injects cockpit links |
| **Step 2a** — Infra Debug Bundle Agent | Collects K8s events, node status, pod restarts/OOMKills, resource pressure, network/DNS, Azure infra signals, Log Analytics queries for T0-15m..T0+30m; stores bundle in blob and registers metadata in Jira | No | Entirely new sub-agent. Must use KQL (Log Analytics) not Loki. Needs blob storage pipeline |
| **Step 2b** — Application Context Agent | Pulls release version, feature flags, dependency health, trace exemplars; searches similar incidents in Jira/Confluence; outputs suspected failure modes and top-5 checks | No | New sub-agent. Needs Confluence connector, release/config data source, incident similarity search |
| **Step 3** — Orchestrator/Classifier Agent | Consumes both streams, classifies fault domain (infra vs app vs mixed), posts classification + confidence + first-3-actions + routing into Jira | No | New orchestration logic. Correlates infra + app evidence into a single classification |
| **Step 4** — SRE Analysis Agent | Analyzes debug bundle + live telemetry; proposes mitigation (restart, scale, rollback, circuit breaker, config change); risk assessment; "what to monitor next 30 min"; generates ready-to-run commands | Partial | DiagnosticExpert queries logs and creates a ticket but does not produce structured mitigations, risk assessments, or runnable commands |
| **Step 5** — RCA Agent | Opens "Living RCA Draft" in Confluence, appends timeline/evidence/impact, generates customer-facing updates every N minutes | No | New sub-agent. Needs Confluence MCP and customer-aware communication templates |

### Experience 2 — Troubleshooting Cockpit

| Roadmap item | Jan PoC covers? | Gap |
|---|---|---|
| Grafana cockpit with golden signals per service, customer-scoped error rate, deploy/config change markers | No | Requires opinionated Grafana dashboard pack |
| Auto-zoom to incident time window, correlated event overlays | No | Requires parameterized dashboard URLs |
| SRE Agent "Analyze current view" button | No | Requires Grafana plugin or deep link integration |

### Experience 3 — Proactive Support

| Roadmap item | Jan PoC covers? | Gap |
|---|---|---|
| Health sweep every 5-15 min per cluster/customer/dependency | No | New scheduled sub-agent. Needs Azure Monitor alerts and metric ingestion |
| Predictive findings (memory creep, CPU saturation, error budget burn, latency regression) | No | Anomaly detection logic, trend analysis |
| DB risk detection (bloat, lock contention, vacuum lag, wraparound risk) | No | Requires DB-specific queries (PostgreSQL focus given Zafin stack) |
| Container memory creep detection + GC pressure analysis | No | Needs Container Insights integration |
| Action Tickets (auto-created Jira tasks with evidence and routing) | No | Extends Jira MCP to create proactive tasks, not just incident tickets |
| Weekly "Top 10 prevented incidents" summary | No | Reporting/aggregation sub-agent |

### Experience 4 — IAM/PIM Agent

| Roadmap item | Jan PoC covers? | Gap |
|---|---|---|
| Azure PIM request ingestion + automated validation | No | Entirely new domain. Needs Entra ID / PIM API integration |
| Ticket validation (exists, open, recent, requester match) | No | Cross-references PIM request against Jira |
| Policy engine (role allowlists, scope rules, SoD checks) | No | Deterministic rules engine |
| Risk scoring + anomaly detection | No | Behavioral analysis over PIM request history |
| Approver cockpit (Grafana security dashboard) | No | New dashboard pack |

## Customer Enablement Roadmap (awareness only, not in scope)

The second PDF defines a separate workstream for functional consultants:

1. **Enablement Designer Agent (EDA)** — requirements intake, fit-gap
   assessment, configuration playbooks
2. **Integration & Build Guidance Agent** — IO/Canvas build specs, contract
   tests
3. **QA & Regression Agent** — customer qualification packs, release
   regression

These are product/enablement concerns, not SRE. Noting here so we don't
accidentally scope them in during the demo.

## Recommended work division: Arturo + Ankit

The March 13 meeting agreed that Arturo and Ankit divide scenarios from the
roadmap PDF, implement them, and prepare a demo for the customer.

### Priority and assignment proposal

| Priority | Scenario | Owner | Rationale |
|---|---|---|---|
| **P1** | Reactive: Ticket enrichment + Troubleshooting Cockpit link | Arturo | Closest to existing January work. Extend DiagnosticExpert to enrich existing tickets instead of just creating new ones. Build a parameterized Grafana dashboard |
| **P1** | Reactive: Infra Debug Bundle Agent | Ankit | New sub-agent. Good standalone work item. Collect K8s events + Log Analytics queries for a time window, package as debug bundle |
| **P2** | Reactive: Application Context Agent | Ankit | New sub-agent. Pull release/config context, search similar incidents in Jira history |
| **P2** | Reactive: Orchestrator/Classifier logic | Arturo | Orchestration layer that consumes infra + app streams and classifies fault domain. Builds on top of P1 work from both sides |
| **P3** | RCA Agent + Confluence integration | Arturo | Living RCA draft, customer-facing comms. Needs Confluence MCP connector |
| **P3** | Proactive: Health sweep + predictive findings | Ankit | Scheduled agent, Azure Monitor integration, anomaly detection |
| **P4** | IAM/PIM Agent | TBD | Different domain entirely. Propose deferring unless customer insists |

### Environment alignment tasks (shared)

| Task | Note |
|---|---|
| Replace Loki queries with KQL (Log Analytics) | Zafin's AKS is behind private VNET; Loki is demo-only |
| Build Grafana Troubleshooting Cockpit dashboard pack | Parameterized by customer, namespace, time window |
| Add Confluence MCP connector | Required for RCA Agent and incident similarity |
| Contribute samples to public `microsoft/sre-agent` repo | Per March 13 meeting agreement |

## Next steps

1. **Get alignment with Ankit** on the proposed division above.
2. **Start P1 items** — Arturo on ticket enrichment, Ankit on Infra Debug
   Bundle Agent.
3. **Validate with Deepthi** that focusing on the SRE roadmap (not Enablement)
   is the right scoping for our demo.
4. **Schedule demo** with George once P1 + P2 scenarios are working.
