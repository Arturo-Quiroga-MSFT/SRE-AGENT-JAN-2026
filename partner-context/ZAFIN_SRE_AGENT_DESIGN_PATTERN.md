---
title: "Azure SRE Agent — Zafin Design Pattern"
description: "Validated design pattern and implementation guide for deploying Azure SRE Agent against Zafin's private AKS production topology"
---

## Purpose and status

This document defines the validated design pattern for deploying Azure SRE Agent
against Zafin's production topology: AKS clusters behind a private VNet with no
public API server endpoint.

The pattern was proven on March 30, 2026 using a purpose-built test bed
(`aks-private-testbed/`) that mirrors Zafin's infrastructure. All four
validation tests passed. See [TEST-RESULTS.md](../aks-private-testbed/TEST-RESULTS.md)
for the full evidence record.

**The previously documented limitation — "SRE Agent does not support AKS behind
private VNET" — is incorrect and can be removed from architectural decision records.**

---

## Architecture overview

```
                    Zafin SRE Team
                         |
                   (browser / chat)
                         |
                         v
              ┌─────────────────────┐
              │  Azure SRE Agent    │
              │  (AI Foundry)       │
              │  Managed Identity   │
              └────────┬────────────┘
                       |
          authenticates via Managed Identity
                       |
                       v
          ┌────────────────────────┐
          │  Azure Resource Manager│  <-- always publicly reachable
          │  (control plane)       │
          └──────┬──────┬──────────┘
                 |      |
        ARM API  |      | Log Analytics API
                 |      |
    ┌────────────v──┐  ┌v─────────────────────────┐
    │ AKS API Server│  │ Log Analytics Workspace   │
    │ Private, no   │  │ KubePodInventory          │
    │ public endpoint│  │ ContainerLog              │
    └───────┬───────┘  │ KubeEvents                │
            |          │ Perf                      │
   ARM tunnel|          │ AppInsights tables        │
   (kubectl) |          └───────────────────────────┘
            |
    ┌───────v───────────────────────┐
    │  Private VNet                 │
    │  ┌─────────────────────────┐  │
    │  │  AKS Node Pool          │  │
    │  │  Zafin workloads        │  │
    │  │  (namespaced by client) │  │
    │  └─────────────────────────┘  │
    └───────────────────────────────┘

The SRE Agent never enters the VNet.
```

---

## How the agent reaches a private AKS cluster

The key insight is that the SRE Agent operates entirely through Azure's
**control plane**, which is always publicly reachable. No VPN, no Bastion
host, no kubeconfig on the calling machine is required.

### Path 1 — ARM-level operations

All cluster management operations (scale, upgrade, describe, node pools,
`az aks show`) go through Azure Resource Manager, which has a built-in
Private Link path to the private AKS control plane over the Azure backbone.

### Path 2 — Log Analytics

Container Insights writes all cluster telemetry (pod inventory, container logs,
node metrics, Kubernetes events) to the Log Analytics workspace. The agent
queries these tables via the Log Analytics REST API — no cluster connectivity
needed.

### Path 3 — In-cluster kubectl operations

The agent can tunnel `kubectl` commands through ARM using `az aks command invoke`.
This establishes an ARM-brokered connection to the private API server, allowing
full read and write kubectl access without network reachability to the VNet.

---

## Required Azure RBAC roles

Assign these four roles to the SRE Agent's Managed Identity.
All assignments are at resource-specific scope — no subscription-wide permissions needed.

| Role | Scope | Enables |
|---|---|---|
| Azure Kubernetes Service Contributor Role | AKS cluster | Scale, upgrade, node pool management, `az aks show` |
| Azure Kubernetes Service Cluster User Role | AKS cluster | `az aks command invoke` (kubectl without VPN) |
| Log Analytics Reader | Log Analytics workspace | KQL queries — Container Insights, App Insights, custom tables |
| Reader | Resource group | `az aks show`, `az monitor`, `az resource list`, alert enumeration |

```bash
# Template — replace variables for each Zafin cluster
MI_OBJECT_ID="<sre-agent-managed-identity-object-id>"
SUBSCRIPTION="<subscription-id>"
RG="<resource-group>"
AKS_ID="/subscriptions/${SUBSCRIPTION}/resourceGroups/${RG}/providers/Microsoft.ContainerService/managedClusters/<cluster-name>"
LA_ID="/subscriptions/${SUBSCRIPTION}/resourceGroups/${RG}/providers/Microsoft.OperationalInsights/workspaces/<workspace-name>"

# AKS Contributor
az role assignment create --assignee-object-id "${MI_OBJECT_ID}" \
  --role "Azure Kubernetes Service Contributor Role" \
  --scope "${AKS_ID}" --assignee-principal-type ServicePrincipal

# AKS Cluster User
az role assignment create --assignee-object-id "${MI_OBJECT_ID}" \
  --role "Azure Kubernetes Service Cluster User Role" \
  --scope "${AKS_ID}" --assignee-principal-type ServicePrincipal

# Log Analytics Reader
az role assignment create --assignee-object-id "${MI_OBJECT_ID}" \
  --role "Log Analytics Reader" \
  --scope "${LA_ID}" --assignee-principal-type ServicePrincipal

# Reader on RG
az role assignment create --assignee-object-id "${MI_OBJECT_ID}" \
  --role "Reader" \
  --scope "/subscriptions/${SUBSCRIPTION}/resourceGroups/${RG}" \
  --assignee-principal-type ServicePrincipal
```

---

## Diagnostic telemetry: what flows into Log Analytics

Zafin must ensure Container Insights is enabled on each AKS cluster.
No custom exporters or agents are required — the omsagent addon handles
all collection automatically.

| Log Analytics table | Content | Key columns |
|---|---|---|
| `KubePodInventory` | Pod status, restarts, phase, namespace, node assignment | `Name`, `Namespace`, `PodRestartCount`, `PodStatus`, `ControllerName` |
| `KubeNodeInventory` | Node status, conditions (MemoryPressure, DiskPressure) | `Computer`, `Status`, `KubeletVersion` |
| `KubeEvents` | Kubernetes Warning and Normal events | `Reason`, `Message`, `KubeEventType`, `ObjectKind` |
| `ContainerLog` | All stdout/stderr from every container | `PodName`, `LogEntry`, `ContainerName` |
| `Perf` | CPU and memory usage by container and node | `ObjectName`, `CounterName`, `CounterValue` |
| `requests` (App Insights) | HTTP request rates, latency, result codes | `name`, `resultCode`, `duration`, `success` |
| `exceptions` (App Insights) | Unhandled exceptions with stack traces | `type`, `outerMessage`, `assembly` |

### Enable Container Insights (if not already on)

```bash
az aks enable-addons \
  --resource-group <rg> \
  --name <cluster-name> \
  --addons monitoring \
  --workspace-resource-id <log-analytics-workspace-resource-id>
```

---

## SRE Agent knowledge file — KQL query library

The agent uses a knowledge file to guide its investigations. The following
KQL patterns should be included for Zafin's environment. Replace
`<namespace>` with Zafin's actual namespace conventions.

### Pod health

```kusto
// Pod restart counts — identify crashing pods
KubePodInventory
| where TimeGenerated > ago(1h)
| where Namespace == "<namespace>"
| where isnotempty(PodRestartCount)
| summarize MaxRestarts = max(toint(PodRestartCount)) by Name, Namespace
| where MaxRestarts > 0
| order by MaxRestarts desc
```

```kusto
// OOMKilled pods
KubePodInventory
| where TimeGenerated > ago(2h)
| where Namespace == "<namespace>"
| where PodStatus == "OOMKilled" or ContainerLastStatus == "OOMKilled"
| project TimeGenerated, Name, Namespace, Node, PodRestartCount
```

```kusto
// Pending or failed pods
KubePodInventory
| where TimeGenerated > ago(30m)
| where Namespace == "<namespace>"
| where PodStatus in ("Pending", "Failed", "Unknown")
| project TimeGenerated, Name, PodStatus, Namespace, Node
```

### Container logs

```kusto
// Recent error logs from a namespace
ContainerLog
| where TimeGenerated > ago(1h)
| where PodName contains "<namespace>"
| where LogEntry contains "error" or LogEntry contains "ERROR" or LogEntry contains "FATAL"
| project TimeGenerated, PodName, ContainerName, LogEntry
| order by TimeGenerated desc
| take 50
```

```kusto
// HTTP 5xx errors from application logs
ContainerLog
| where TimeGenerated > ago(1h)
| where PodName contains "<service-name>"
| where LogEntry matches regex "5[0-9]{2}"
| project TimeGenerated, PodName, LogEntry
| order by TimeGenerated desc
```

### Node health

```kusto
// Node conditions
KubeNodeInventory
| where TimeGenerated > ago(30m)
| summarize arg_max(TimeGenerated, *) by Computer
| project Computer, Status, KubeletVersion, Labels
```

```kusto
// Node CPU usage (Container Insights Perf table)
Perf
| where TimeGenerated > ago(30m)
| where ObjectName == "K8SNode"
| where CounterName == "cpuUsageNanoCores"
| summarize AvgCPU = avg(CounterValue) by Computer, bin(TimeGenerated, 5m)
| order by TimeGenerated desc
```

### Kubernetes events

```kusto
// Warning events (OOMKill, BackoffLimitExceeded, Failed scheduling)
KubeEvents
| where TimeGenerated > ago(2h)
| where KubeEventType == "Warning"
| where Namespace == "<namespace>"
| project TimeGenerated, Reason, Message, ObjectKind, Name
| order by TimeGenerated desc
```

### Application Insights (if instrumented)

```kusto
// Request failure rate by endpoint
requests
| where timestamp > ago(1h)
| where cloud_RoleName == "<service-name>"
| summarize
    Total = count(),
    Failed = countif(success == false)
  by name, bin(timestamp, 5m)
| extend FailureRate = round(100.0 * Failed / Total, 1)
| where FailureRate > 5
| order by timestamp desc
```

```kusto
// Top exceptions in the last hour
exceptions
| where timestamp > ago(1h)
| where cloud_RoleName == "<service-name>"
| summarize Count = count() by type, outerMessage
| order by Count desc
| take 10
```

---

## Agent safety model

The SRE Agent enforces a three-tier kubectl execution policy regardless of
RBAC permissions on the cluster. Zafin's SRE team should understand this
before onboarding:

| Tier | kubectl commands | Behavior |
|---|---|---|
| **Read** | `get`, `describe`, `logs`, `top`, `api-resources` | Executed immediately, no approval |
| **Write** | `apply`, `patch`, `scale`, `rollout`, `label`, `annotate` | Requires explicit human approval before execution |
| **Blocked** | `delete`, `exec`, `port-forward` | Never executed — safety policy |

The agent also queries Prometheus metrics and can visualize microservice topology.

**Implications for Zafin:**
- The agent can diagnose any incident autonomously without risk of causing further damage
- Remediation actions (scale, rollout restart) require an SRE to confirm in the chat before they execute
- Destructive operations are fully blocked — the agent cannot delete a workload or a namespace

---

## Incident investigation workflow

The recommended prompt pattern for Zafin SREs to use with the agent:

### Reactive — alert fired

```
An alert fired on AKS cluster <cluster-name> in resource group <rg>,
subscription <subscription-id>. The alert indicates <alert description>.
Investigate what is happening in namespace <namespace>, identify the root cause
from logs and events, and recommend immediate remediation steps.
```

### Reactive — manual report

```
There is a reported incident in the <namespace> namespace on cluster <cluster-name>
(resource group <rg>). Users are seeing <symptom>. Investigate pod health,
recent Kubernetes events, and container logs for the last 30 minutes, then
summarize root cause and recommended actions.
```

### Proactive — health check

```
Run a health check on AKS cluster <cluster-name> in resource group <rg>.
Check all node conditions, identify any pods with restarts in the last 2 hours,
show memory and CPU usage trends, and flag any early warning signals.
```

---

## Recommended alert rules

Deploy these Log Analytics scheduled query rules to automate incident detection.
The alert webhook can be configured to notify the SRE team, who then invoke
the SRE Agent to investigate.

| Alert | Query basis | Threshold | Frequency |
|---|---|---|---|
| Pod restart spike | `KubePodInventory`, `PodRestartCount` | > 3 restarts in 15 min | PT5M |
| Zero ready pods | `KubePodInventory`, `PodStatus == Running` count | 0 pods for any deployment | PT5M |
| Node CPU sustained high | Azure Monitor metric, `node_cpu_usage_percentage` | > 80% for 5 min | PT5M |
| OOMKill detected | `KubeEvents`, `Reason == OOMKilling` | Any event | PT5M |
| Failed jobs accumulating | `KubeEvents`, `Reason == BackoffLimitExceeded` | > 2 in 30 min | PT5M |

---

## Multi-cluster considerations

Zafin likely operates multiple AKS clusters (per region, per environment, or
per customer tier). Apply the RBAC role assignments to the SRE Agent's Managed
Identity on **each cluster** and **each Log Analytics workspace** separately.

There is no additional cluster networking needed — ARM reaches all clusters
through the same public control plane endpoint pattern regardless of how many
clusters are in scope.

---

## What this pattern does not cover

| Capability | Current status | Path forward |
|---|---|---|
| Alert → agent auto-trigger | Not in scope | Azure Monitor alert action group → webhook → agent invocation |
| Jira ticket auto-enrichment | Partially covered in Jan PoC | Extend DiagnosticExpert to enrich existing tickets (roadmap P1) |
| Infra Debug Bundle Agent | Not in scope | New sub-agent collecting K8s events + KQL for a time window |
| Application Context Agent | Not in scope | Pull release/feature flag context, Jira incident similarity search |
| Confluence / RCA integration | Not in scope | Confluence MCP connector required |
| Proactive health sweeps | Not in scope | Scheduled sub-agent, Azure Monitor metric ingestion |
| IAM / PIM Agent | Not in scope | Different domain — Entra ID / PIM API |

See [ZAFIN_GAP_ANALYSIS_MARCH_2026.md](./ZAFIN_GAP_ANALYSIS_MARCH_2026.md) for
the full roadmap coverage map.

---

## Validation evidence

The complete test results are in
[aks-private-testbed/TEST-RESULTS.md](../aks-private-testbed/TEST-RESULTS.md).
Summary:

| Test | Capability | Result |
|---|---|---|
| ARM-level cluster read | Node pools, cluster status via Resource Manager | Pass |
| Log Analytics KQL | Pod restart counts from `KubePodInventory` | Pass |
| kubectl on private cluster | Live pod list with IPs via ARM tunnel | Pass |
| CrashLoopBackOff investigation | Root cause from logs + remediation options | Pass |

Infrastructure used: `aks-yiuooxpadbhno` with `enablePrivateCluster: true`
and `enablePrivateClusterPublicFQDN: false` — the most restrictive private
AKS configuration available in Azure.
