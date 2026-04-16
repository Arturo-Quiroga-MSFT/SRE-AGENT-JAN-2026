---
title: ACA Locked-Down Testbed Validation Report
description: Full validation results of Azure SRE Agent managing locked-down ACA apps through ARM
author: Arturo Quiroga
ms.date: 2026-04-16
ms.topic: reference
---

## Executive Summary

We built and deployed a fully locked-down Azure Container Apps environment
to test whether the Azure SRE Agent can manage internal-only ACA apps
through ARM — with no VNet access, no public endpoints, and no workarounds.

**Result: Full pass.** The SRE Agent diagnosed a healthy environment,
detected an injected incident (ingress port mismatch + crash loop),
identified the root cause, and proposed a working fix — all through ARM APIs.

This validates Deepthi's feedback that the blog should expand beyond AKS.
ACA is not just supported — it is *simpler* than AKS for SRE Agent
management because there is no dual-layer auth to configure.

## Environment Deployed

| Property | Value |
|---|---|
| Resource group | `rg-aqacasre` |
| Region | East US 2 |
| ACA environment | `cae-wpcgf5675olvq` |
| VNet | `vnet-wpcgf5675olvq` (10.44.0.0/16) |
| ACA subnet | `snet-aca` (10.44.0.0/21), delegated to `Microsoft.App/environments` |
| PE subnet | `snet-pe` (10.44.8.0/27) |
| Static IP | 10.44.0.44 (internal) |
| Public network access | **Disabled** |
| ACR | `acrsrewpcgf5675olvq` (RBAC-only, admin disabled) |
| Log Analytics | `log-wpcgf5675olvq` (workspace `c04f4b3d-21ec-4cd4-af1e-5d5aa96a96ea`) |
| NSG | Allow VNet (100), Allow LB (110), Deny All Inbound (4096) |

### Container Apps Deployed

| App | Image | Port | Ingress |
|---|---|---|---|
| `ca-api-wpcgf5675olvq` | `grocery-api:latest` | 3100 | Internal only |
| `ca-web-wpcgf5675olvq` | `grocery-web:latest` | 3000 | Internal only |

### SRE Agent Roles (3 built-in, no custom roles)

| Role | Scope |
|---|---|
| Reader | `rg-aqacasre` (resource group) |
| Contributor | `cae-wpcgf5675olvq` (ACA environment) |
| Log Analytics Reader | `log-wpcgf5675olvq` (workspace) |

Compare this to AKS which needs 4 roles including the custom
`AKS ReadOnly Command Invoke` role.

## Test 1 — Baseline Health Check (Pass)

**Prompt:** "Check the ACA apps in rg-aqacasre and their health status."

**Agent findings:**

* Both apps healthy with 1 replica each, running on internal-only FQDNs
* VNet-injected environment with `publicNetworkAccess: Disabled`
* NSG correctly enforcing deny-all-inbound except VNet and LB
* UAMI-based ACR pull working (no admin credentials)
* Web→API connectivity configured via internal FQDN env var
* Workload profile: Consumption, zone redundancy: No

**ARM operations the agent used:**

1. `az containerapp list` — enumerate apps
2. `az containerapp show` — app details, env vars, ingress config
3. `az containerapp revision list` — revision health, replica count
4. `az containerapp env show` — environment config, VNet, mTLS
5. KQL queries against `ContainerAppConsoleLogs_CL` and `ContainerAppSystemLogs_CL`

**Verdict:** The agent built a complete picture of the locked-down environment
purely through ARM. No VNet connectivity was needed.

## Test 2 — ARM Access Validation Script (Pass)

We ran `04-validate-sre-access.sh` which executes the same 10 ARM operations
the SRE Agent uses.

| # | Operation | Result |
|---|---|---|
| 1 | List container apps | Pass — both apps returned with status `Succeeded` |
| 2 | Show app details | Pass — env, replicas, ingress config returned |
| 3 | List revisions | Pass — revision health, active state returned |
| 4 | Show replica status | Pass — individual replica names returned |
| 5 | Stream logs via ARM | Pass — system events returned (startup, probe events) |
| 6 | Show environment details | Pass — VNet config, provisioning state returned |
| 7 | KQL — ContainerAppConsoleLogs | Pass — app stdout/stderr returned (Node.js startup logs) |
| 8 | KQL — ContainerAppSystemLogs | Pass — probe failures, container lifecycle events returned |
| 9 | Restart revision | Skipped (destructive) — command documented |
| 10 | Scale app | Skipped (destructive) — command documented |

**Verdict:** All 8 active operations passed. The SRE Agent identity has
full read access plus write access for restart and scale operations.

## Test 3 — Injected Incident: Port Mismatch + Crash Loop (Pass)

### Incident Setup

We injected two simultaneous failures:

1. **Ingress port mismatch** — changed `targetPort` from 3100 to 9999
   (app listens on 3100, ingress forwards to 9999)
2. **CRASH_ON_START env var** — added `CRASH_ON_START=true` to create
   a new revision

This created revision `--0000002` which entered an
**Unhealthy/Degraded** state with continuous startup probe failures.

### What the SRE Agent Found

**Prompt:** "The grocery API in rg-aqacasre seems to be having issues.
Can you diagnose what's wrong and suggest a fix?"

The agent identified **3 issues** with correct severity ratings:

| # | Severity | Issue | Agent's Finding |
|---|---|---|---|
| 1 | Critical | `CRASH_ON_START=true` env var | Found the env var, correlated with 5 container terminations (`ProbeFailure`), `npm error signal SIGTERM`, and "Deployment Progress Deadline Exceeded" |
| 2 | Critical | Ingress port mismatch (9999 vs 3100) | Found `targetPort: 9999` while app `PORT=3100`, correctly explained all HTTP requests fail because the startup probe can't reach the app |
| 3 | Moderate | Loki push 404 errors | Found the API posting to `localhost:3100/loki/api/v1/push` (itself), getting 404 — correctly identified as a misconfiguration, not a crash cause |

### Agent's Proposed Fix

```bash
az containerapp update \
  -n ca-api-wpcgf5675olvq \
  -g rg-aqacasre \
  --set-env-vars "PORT=3100" "SUPPLIER_RATE_LIMIT=5" \
  --remove-env-vars "CRASH_ON_START" \
  --target-port 3100
```

The fix addressed both critical issues in a single command.
We applied it (in two steps due to CLI flag separation) and
the app recovered to **Healthy/Running** on revision `--fix-1776359054`.

### Incident Timeline

| Time (UTC) | Event |
|---|---|
| 16:22 | Baseline: revision `--0000001` healthy, port 3100 |
| 16:41 | Injected: revision `--0000002` with `CRASH_ON_START=true` |
| 16:45 | Injected: ingress `targetPort` changed to 9999 |
| 16:55 | Revision `--0000002` entered Unhealthy/Degraded |
| 16:55+ | SRE Agent analyzed, found all 3 issues |
| 17:04 | Fix applied: port restored to 3100, env var removed |
| 17:05 | Revision `--fix-1776359054` healthy and running |

**Verdict:** The SRE Agent diagnosed a multi-factor incident on a locked-down
ACA app using only ARM APIs. It correlated system logs, console logs,
ingress config, and environment variables to produce an actionable fix.

## ACA vs AKS — SRE Agent Comparison

| Dimension | AKS (locked-down) | ACA (locked-down) |
|---|---|---|
| Roles needed | 4 (including custom `AKS ReadOnly Command Invoke`) | 3 (all built-in) |
| Auth layers | 2 (ARM + Kubernetes RBAC) | 1 (ARM only) |
| Data-plane access | `az aks command invoke` tunnels kubectl | Direct ARM APIs |
| Log access | KQL via Log Analytics | KQL via Log Analytics |
| App health | `kubectl get pods` via command invoke | `az containerapp revision list` |
| App logs | `kubectl logs` via command invoke | `az containerapp logs show` |
| Environment vars | `kubectl describe pod` via command invoke | `az containerapp show` |
| Network config | `kubectl get networkpolicies` via command invoke | NSG rules via ARM |
| Restart | `kubectl rollout restart` via command invoke | `az containerapp revision restart` |
| Scale | `kubectl scale` via command invoke | `az containerapp update --min/max-replicas` |

**Key insight:** ACA eliminates the Kubernetes data-plane RBAC layer entirely.
The SRE Agent needs fewer permissions, simpler setup, and gets richer data
from ARM APIs than from `kubectl` output parsed through command invoke.

## Test 4 — Container Exec Capability (Expected Limitation Confirmed)

**Prompt:** "Can you execute this type of command `az containerapp exec`?"

The agent correctly reported that `az containerapp exec` is **not available**
because it requires an interactive TTY session that the agent's tooling
does not support. This is a tooling constraint, not a permissions or
network issue.

The agent categorized its available operations as:

* **Read commands** (`list`, `show`, `get`) — execute immediately
* **Write commands** (`create`, `update`, `set`, `scale`, `start`, `stop`, `restart`) — require approval
* **Interactive commands** (`exec`) — blocked (no TTY support)

The agent proactively offered four alternatives to get the same
information without exec:

1. Console logs via KQL (`ContainerAppConsoleLogs_CL`)
2. System logs via KQL (`ContainerAppSystemLogs_CL`)
3. `az containerapp logs show` for recent log streaming
4. `az containerapp revision show` for revision health and replica status

**Verdict:** This limitation is the same on both AKS and ACA — the agent
cannot open interactive sessions into containers. On AKS, `kubectl exec`
via command invoke would face the same TTY constraint. The agent
compensates with log queries and ARM metadata, which proved sufficient
to diagnose the port mismatch incident in Test 3.

## Known Limitations

* **No container exec:** `az containerapp exec` is blocked at the agent
  tooling level (no interactive TTY support). This is not a network or
  RBAC issue — the agent's tool runtime does not support interactive
  sessions. The same limitation applies to `kubectl exec` on AKS.
* **Log ingestion delay:** Container App logs take 2-5 minutes to appear
  in Log Analytics. Real-time log streaming (`az containerapp logs show`)
  works through ARM but only returns recent events.
* **No App Insights:** This testbed uses Log Analytics only. Adding
  Application Insights would give the agent APM traces, dependency maps,
  and failure analysis.

## Recommendations for the Blog

1. **Add an ACA section** to the blog post showing that locked-down ACA
   is simpler than AKS (fewer roles, no custom role, no dual-layer auth)
2. **Reference this test** as evidence that the SRE Agent handles
   real incident scenarios on private ACA environments
3. **Position ACA as the easy path** for partners who want to try the
   SRE Agent without the complexity of AKS RBAC configuration
4. **Consider a blog series:** Part 1 = AKS (current draft),
   Part 2 = ACA (this validation), Part 3 = App Service

## Files and Artifacts

| Artifact | Path |
|---|---|
| Bicep infrastructure | `aca-locked-testbed/infra/resources.bicep` |
| Provision script | `aca-locked-testbed/scripts/01-provision.sh` |
| Deploy apps script | `aca-locked-testbed/scripts/02-deploy-app.sh` |
| Trigger incident | `aca-locked-testbed/scripts/03-trigger-incident.sh` |
| Validate SRE access | `aca-locked-testbed/scripts/04-validate-sre-access.sh` |
| SRE Agent diagnosis | `TS.md` (raw agent output from incident test) |
| This report | `docs/ACA_TESTBED_VALIDATION_REPORT.md` |
