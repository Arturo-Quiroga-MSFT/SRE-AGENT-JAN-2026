# SRE Agent — kubectl Access on Semi-Private AKS Clusters

**Audience:** Anyone setting up Azure SRE Agent to run kubectl commands against a semi-private (VNet-injected, public API server) AKS cluster.

**Last tested:** 2026-04-14 on `aks-mqmxizpsox7vu` in `rg-sre-locked` (West US 2, K8s 1.34)

---

## How It Works

The SRE Agent runs `kubectl` commands via `az aks command invoke`, which tunnels through the ARM backbone — no direct network path to the API server is needed. This requires two layers of permissions:

| Layer | Role Needed | What It Grants |
|---|---|---|
| **Control plane** (ARM) | A role with `Microsoft.ContainerService/managedClusters/runCommand/action` | Allows `az aks command invoke` to execute |
| **Data plane** (Kubernetes) | `Azure Kubernetes Service RBAC Reader` | Read access to K8s objects (pods, services, logs, etc.) |

Both roles must be assigned to the agent's managed identity **Object ID** (not Client ID — see Gotcha #1 below).

---

## Setup Checklist

### Step 1: Find Your Agent's Identity

From the SRE Agent portal or ARM resource, note:

| Property | Where to Find | Example |
|---|---|---|
| **Client ID** (App ID) | Agent settings → Managed Identity | `5ef3d54d-b401-496d-ba2f-a6652872a084` |
| **Object ID** (Principal ID) | `az ad sp show --id <client-id> --query id -o tsv` | `f54ae888-64d7-451d-a03d-66060918c1a8` |

> **Tip:** If you don't know the Object ID yet, you can also find it in the error message when `az aks command invoke` fails with 403 — it prints the Object ID in the Forbidden response.

### Step 2: Create or Assign the Control Plane Role

**Option A — Custom least-privilege role (recommended):**

Create a custom role with only `runCommand/action`:

```json
{
  "Name": "AKS ReadOnly Command Invoke (<cluster-name>)",
  "Description": "Allows az aks command invoke (read-only kubectl) on a specific AKS cluster",
  "Actions": [
    "Microsoft.ContainerService/managedClusters/runCommand/action",
    "Microsoft.ContainerService/managedClusters/commandResults/read"
  ],
  "NotActions": [],
  "AssignableScopes": [
    "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.ContainerService/managedClusters/<cluster-name>"
  ]
}
```

```bash
az role definition create --role-definition @custom-role.json
az role assignment create \
  --assignee-object-id "<object-id>" \
  --assignee-principal-type ServicePrincipal \
  --role "AKS ReadOnly Command Invoke (<cluster-name>)" \
  --scope "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.ContainerService/managedClusters/<cluster-name>"
```

**Option B — Built-in role (broader permissions):**

```bash
az role assignment create \
  --assignee-object-id "<object-id>" \
  --assignee-principal-type ServicePrincipal \
  --role "Azure Kubernetes Service Cluster User Role" \
  --scope "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.ContainerService/managedClusters/<cluster-name>"
```

### Step 3: Assign the Data Plane Role

```bash
az role assignment create \
  --assignee-object-id "<object-id>" \
  --assignee-principal-type ServicePrincipal \
  --role "Azure Kubernetes Service RBAC Reader" \
  --scope "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.ContainerService/managedClusters/<cluster-name>"
```

### Step 4: Wait for Propagation

Role assignments typically take **1-2 minutes** to propagate. Don't panic if the first attempt after assignment still fails.

### Step 5: Verify Roles

```bash
az role assignment list \
  --assignee-object-id "<object-id>" \
  --scope "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.ContainerService/managedClusters/<cluster-name>" \
  --query "[].roleDefinitionName" -o tsv
```

You should see both roles listed:
```
AKS ReadOnly Command Invoke (<cluster-name>)    # or Azure Kubernetes Service Cluster User Role
Azure Kubernetes Service RBAC Reader
```

### Step 6: Test from the Agent

In a chat with the SRE Agent, ask it to run:

```
run this on my cluster: kubectl get pods -A
```

The agent will use the **Bash subagent** to execute `az aks command invoke` under the hood.

---

## What RBAC Reader Can and Cannot Do

### Allowed (namespace-scoped reads)

| Command | Notes |
|---|---|
| `kubectl get pods -A` | List pods across all namespaces |
| `kubectl get svc -A` | List services |
| `kubectl get deployments -A` | List deployments |
| `kubectl get configmaps -n <ns>` | List configmaps |
| `kubectl get events -A` | List events |
| `kubectl logs -n <ns> <pod> --tail=N` | View pod logs (non-streaming) |
| `kubectl top pods -n <ns>` | Pod CPU/memory metrics |
| `kubectl describe <resource> -n <ns>` | Describe namespace-scoped resources |

### Denied (cluster-scoped reads)

| Command | Why | Fix |
|---|---|---|
| `kubectl get nodes` | `nodes` is cluster-scoped | Need custom role with `nodes/list` |
| `kubectl top nodes` | Same | Same |

### Denied (all writes)

| Command | Verb Blocked |
|---|---|
| `kubectl create` / `kubectl apply` | `create` |
| `kubectl delete` | `delete` |
| `kubectl exec` | `create` on `pods/exec` |
| `kubectl run` | `create` on `pods` |
| `kubectl scale` / `kubectl patch` | `update` / `patch` |

### Not supported via command invoke (regardless of RBAC)

| Command | Why |
|---|---|
| `kubectl logs -f` (follow) | Streaming not supported |
| `kubectl port-forward` | Requires persistent connection |
| `kubectl exec -it` | No interactive TTY |
| `kubectl rollout status -w` | Watch/streaming not supported |

---

## Common Gotchas

### Gotcha #1: Client ID vs Object ID

**Symptom:** `az role assignment list --assignee <client-id>` returns empty even though roles are assigned.

**Cause:** Azure RBAC binds roles to the **Object ID** (service principal ID), not the **Client ID** (application ID). These are different identifiers.

**Fix:** Always use `--assignee-object-id`:
```bash
# WRONG — may return empty
az role assignment list --assignee "5ef3d54d-b401-496d-ba2f-a6652872a084"

# CORRECT — returns actual assignments
az role assignment list --assignee-object-id "f54ae888-64d7-451d-a03d-66060918c1a8"
```

### Gotcha #2: `az aks command invoke` Blocked by Agent CLI Tools

**Symptom:** The agent says `az aks command invoke` is "blocked" or "not allowed."

**Cause:** The SRE Agent's direct Azure CLI tool (`RunAzCliReadCommands`) has `aks command invoke` on its safety blocklist.

**Fix:** The agent must use the **Bash subagent** path instead. When asking the agent, say something like:
- "run this on my cluster: kubectl get pods -A"
- The agent should automatically route through the Bash subagent

If it doesn't, explicitly ask: "use the Bash subagent to run az aks command invoke"

### Gotcha #3: `az aks nodepool show` vs `az aks show` for Subnet Injection

**Symptom:** `az aks show` query returns `null` for `vnetSubnetID` even though nodes are VNet-injected.

**Cause:** The JMESPath projection on `az aks show` doesn't reliably surface `vnetSubnetID` from the agent pool profiles.

**Fix:** Use the authoritative check:
```bash
az aks nodepool show -g <rg> --cluster-name <cluster> -n <pool-name> --query vnetSubnetId
```

### Gotcha #4: Cluster Is Stopped

**Symptom:** `az aks command invoke` returns HTTP 400: `ManagedCluster is in a state preventing RunCommand feature: PowerState=Stopped`

**Fix:** Start the cluster first:
```bash
az aks start --resource-group <rg> --name <cluster> --subscription <sub-id>
```
This takes 3-5 minutes. Check status with:
```bash
az aks show -g <rg> -n <cluster> --query "{powerState:powerState.code, provisioningState:provisioningState}"
```

### Gotcha #5: 403 But "I Already Assigned the Role"

**Symptom:** You assigned a role but still get 403.

**Possible causes:**
1. You assigned it to the **Client ID** instead of **Object ID** — verify with `--assignee-object-id`
2. You only assigned **one** of the two required roles (need both control plane + data plane)
3. Role hasn't propagated yet — wait 1-2 minutes and retry
4. Role was assigned at the wrong scope (e.g., resource group instead of cluster, or wrong cluster)

---

## Quick Reference

```bash
# Variables — replace with your values
OBJECT_ID="<agent-object-id>"
CLUSTER_SCOPE="/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.ContainerService/managedClusters/<cluster-name>"

# Assign both roles
az role assignment create --assignee-object-id "$OBJECT_ID" --assignee-principal-type ServicePrincipal \
  --role "Azure Kubernetes Service Cluster User Role" --scope "$CLUSTER_SCOPE"

az role assignment create --assignee-object-id "$OBJECT_ID" --assignee-principal-type ServicePrincipal \
  --role "Azure Kubernetes Service RBAC Reader" --scope "$CLUSTER_SCOPE"

# Verify
az role assignment list --assignee-object-id "$OBJECT_ID" --scope "$CLUSTER_SCOPE" \
  --query "[].roleDefinitionName" -o tsv

# Test
az aks command invoke -g <rg> -n <cluster> --subscription <sub-id> --command "kubectl get pods -A"
```

---

## Related Files

- [Architecture](../memories/synthesizedKnowledge/architecture.md) — cluster details, network posture
- [Auth](../memories/synthesizedKnowledge/auth.md) — managed identity IDs, role assignments
- [Debugging](../memories/synthesizedKnowledge/debugging.md) — full RBAC permission matrix, AKS gotchas
