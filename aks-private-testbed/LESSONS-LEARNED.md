# Lessons Learned — AKS Private VNet Test Bed

> **Date:** March 30, 2026
> **Author:** Arturo Quiroga (PSA, Microsoft)
> **Context:** First-time deployment of the AKS Private VNet SRE Agent test bed

This document captures every issue hit during the initial deployment, the root cause, and the fix applied. It exists so that fellow PSAs and engineers do not repeat the same debugging cycle.

---

## L1 — The "private VNet" limitation was wrong

### What we believed

Earlier project documentation stated:

> *"SRE Agent currently does not support AKS Cluster behind private VNET"*

This was documented as a hard platform limitation and was driving architectural decisions — specifically, avoiding direct AKS integration in favor of an Azure Monitor / Log Analytics only approach.

### What is actually true

The [Azure SRE Agent documentation](https://learn.microsoft.com/en-us/azure/sre-agent/overview) (last updated March 27, 2026) lists AKS as a fully supported compute service. There is no documented limitation for private VNet clusters.

### Why the confusion arose

The limitation was real for a specific access pattern: **running `kubectl` commands** requires the caller to be network-reachable to the private AKS API server. However, this is different from the broader question of whether SRE Agent can manage a private AKS cluster.

### The correct mental model

There are three distinct operations, with different network requirements:

| Operation | Network requirement | SRE Agent support |
|---|---|---|
| ARM-level management (scale, upgrade, node pools, `az aks show`) | None — ARM is always reachable | Fully supported out of the box |
| Log Analytics / Container Insights queries (KQL) | None — Log Analytics has public endpoint | Fully supported with Log Analytics Reader role |
| `kubectl` commands (in-cluster operations) | `az aks command invoke` tunnels through ARM — no VPN needed | Supported with AKS Cluster User role |

### Impact on our docs

Updated project documentation to remove the blanket limitation statement and replace with the correct nuanced picture.

---

## L2 — Bicep alert rule: wrong property name `timeAggregationMethod`

### Symptom

```
BadRequest: 'summarize' operator: Failed to resolve scalar expression named 'PodName'.
```

```
InvalidRequestContent: 'Frequency of 2 minutes is not supported.'
```

Two of three scheduled query rule alert resources failed to deploy on the first `azd provision` run.

### Root causes (two separate issues in the same resource type)

**Issue 2a — Wrong property name:**
The Bicep for `Microsoft.Insights/scheduledQueryRules` used `timeAggregationMethod` as a property on the `Condition` object. The correct property is `timeAggregation`. Bicep type validation did not catch this at compile time (it warns but does not error on unknown properties that match a similar schema path).

**Issue 2b — Unsupported evaluation frequency:**
The "no ready pods" alert was configured with `evaluationFrequency: 'PT2M'` (2 minutes). The Log Analytics scheduled query rule API only supports specific frequencies. The minimum supported is `PT5M` (5 minutes).

### Fix

```bicep
// Before (wrong)
timeAggregationMethod: 'Minimum'

// After (correct)
timeAggregation: 'Minimum'
```

```bicep
// Before (unsupported)
evaluationFrequency: 'PT2M'

// After (supported)
evaluationFrequency: 'PT5M'
```

### Lesson

When using `Microsoft.Insights/scheduledQueryRules`, always use `az bicep build` before deploying — it will warn on unknown properties. The supported evaluation frequencies are: 1, 5, 10, 15, 30, 45, 60, 120, 180, 240, 300, 360, 1440 minutes.

---

## L3 — KQL column name: `PodRestartCount` not `RestartCount`

### Symptom

```
BadRequest: 'where' operator: Failed to resolve scalar expression named 'RestartCount'.
```

Second `azd provision` run (after fixing L2) failed on the pod-restart alert.

### Root cause

The KQL query in the alert referenced `RestartCount` as the column name in `KubePodInventory`. The actual column name in the Container Insights schema is `PodRestartCount`.

### Fix

```kusto
// Before (wrong column name)
| where isnotempty(RestartCount)
| summarize MaxRestarts = max(toint(RestartCount)) by PodName, Namespace

// After (correct)
| where isnotempty(PodRestartCount)
| summarize MaxRestarts = max(toint(PodRestartCount)) by Name, Namespace
```

Note: the pod name column is `Name` in `KubePodInventory`, not `PodName`.

### Container Insights KubePodInventory schema reference

Key columns used in SRE Agent queries:

| Column | Type | Description |
|---|---|---|
| `Name` | string | Pod name |
| `Namespace` | string | Kubernetes namespace |
| `PodStatus` | string | Running, Pending, Failed, etc. |
| `PodRestartCount` | string | Cumulative restart count (cast to int for math) |
| `ContainerID` | string | Container runtime ID |
| `TimeGenerated` | datetime | Log ingestion timestamp |

---

## L4 — Multi-period evaluation requires `bin(TimeGenerated)` in KQL

### Symptom

```
BadRequest: Number of evaluation periods must be 1 for queries that do not project
the 'TimeGenerated' column of type 'datetime'
```

### Root cause

The "no ready pods" alert was configured with `numberOfEvaluationPeriods: 2` and `minFailingPeriodsToAlert: 2`. The Log Analytics rule engine requires the KQL query to explicitly project a `TimeGenerated` column (via `bin()`) when using multi-period evaluation. A bare `summarize count()` without a time dimension does not satisfy this requirement.

### Fix

```kusto
// Before (fails with multi-period evaluation)
KubePodInventory
| where Namespace == "grocery"
| where PodStatus == "Running"
| summarize ReadyPods = count()

// After (passes validation)
KubePodInventory
| where Namespace == "grocery"
| where PodStatus == "Running"
| summarize ReadyPods = count() by bin(TimeGenerated, 5m)
```

### When this matters

Any Log Analytics scheduled query alert with `numberOfEvaluationPeriods > 1` must include `bin(TimeGenerated, <window>)` in the aggregation.

---

## L5 — ACR naming: Bicep static analysis min-length warning

### Symptom

```
Warning BCP334: The provided value can have a length as small as 2 and may be too
short to assign to a target with a configured minimum length of 5.
```

### Root cause

The `abbreviations.json` entry for container registries was `"cr"` (2 characters). Azure Container Registry names must be at least 5 characters. Bicep's static analysis cannot prove at compile time that `uniqueString()` will always produce a long-enough result, so it warns when the static prefix is too short.

### Fix

Changed the ACR resource name from `'${abbrs.containerRegistries}${resourceToken}'` to a hardcoded prefix:

```bicep
name: 'acrsre${resourceToken}'
```

`acrsre` is 6 characters. Combined with `uniqueString()` output (always 13 characters), the total name is always 19 characters — well within both the minimum (5) and the maximum (50) for ACR names. As a bonus, the `acr` prefix makes the resource instantly identifiable in the portal.

---

## L6 — `az aks command invoke` file mount path

### Symptom

```
error: the path "/mnt/grocery-api.yaml" does not exist
```

### Root cause

`az aks command invoke --file <path>` mounts the specified file inside the ephemeral command pod at `/mnt/<basename>`. The `--command` string must reference the file using only its basename — not the full `/mnt/...` path.

This is not clearly documented. The Azure CLI help text says "upload files" but does not specify how they are referenced inside the container.

### Fix

```bash
# Wrong — /mnt/ prefix in --command
az aks command invoke \
  --command "kubectl apply -f /mnt/grocery-api.yaml" \
  --file ./k8s/grocery-api.yaml

# Correct — basename only in --command
az aks command invoke \
  --command "kubectl apply -f grocery-api.yaml" \
  --file ./k8s/grocery-api.yaml
```

### Side effect: temp file naming

When substituting `ACR_LOGIN_SERVER` into the manifest at runtime (to avoid committing the real registry URL), the temp file must have a **fixed basename** — not a randomized one (e.g., `mktemp /tmp/grocery-api-XXXXX.yaml` would produce `grocery-api-a4f2b.yaml`, which then has to be referenced as `grocery-api-a4f2b.yaml` in `--command`). We write to `/tmp/grocery-api.yaml` to keep the basename predictable.

---

## L7 — `az aks command invoke` default output format bug

### Symptom

```
Operation returned an invalid status 'OK'
Command exited with code 1
```

This appeared for `kubectl get pods` commands even when the command succeeded inside the cluster (exit code 0 in logs).

### Root cause

The default table output format of `az aks command invoke` has a rendering bug in Azure CLI version 2.x when the operation status is `OK`. It incorrectly treats the HTTP status as an error condition and exits non-zero.

### Fix

Always use `--output json` and parse the response with Python:

```bash
az aks command invoke \
  --resource-group "${RG}" \
  --name "${AKS_NAME}" \
  --command "kubectl get pods -n grocery -o wide" \
  --output json | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['logs']); sys.exit(r['exitCode'])"
```

The JSON response always contains:
- `logs` — full stdout from the command
- `exitCode` — the actual exit code from inside the pod
- `provisioningState` — `Succeeded` when the invoke itself worked

---

## L8 — `kubectl rollout status` not supported via command invoke

### Symptom

```
Operation returned an invalid status 'OK'
Command exited with code 1
```

Specifically for: `kubectl rollout status deployment/grocery-api -n grocery --timeout=120s`

### Root cause

`kubectl rollout status` is a long-polling watch command that keeps the connection open until the rollout completes or times out. `az aks command invoke` is a one-shot API call — it does not support streaming or long-running interactive commands.

### Fix

Replace with a static check after a fixed sleep:

```bash
# Instead of rollout status (streaming — not supported)
# kubectl rollout status deployment/grocery-api -n grocery --timeout=120s

# Use this (static — works with command invoke)
sleep 20
kubectl get pods -n grocery -o wide
```

For production runbooks, loop on `kubectl get deployment` JSON output and check `readyReplicas`.

---

## Summary: `az aks command invoke` constraints

| Capability | Supported | Notes |
|---|---|---|
| Apply manifests (`kubectl apply`) | Yes | Use basename in `--command` |
| Delete resources (`kubectl delete`) | Yes | Use basename in `--command` |
| Get resources (`kubectl get`) | Yes | Use `--output json` to avoid CLI bug |
| Describe resources (`kubectl describe`) | Yes | Returns full text in `logs` field |
| Watch commands (`kubectl rollout status`, `kubectl get -w`) | **No** | Streaming not supported |
| Interactive commands | **No** | One-shot only |
| Multiple files | Yes | Pass multiple `--file` flags |
| Commands referencing mounted files | Yes | Use basename only, not `/mnt/` prefix |
