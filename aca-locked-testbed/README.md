# ACA Locked-Down Test Bed — Azure SRE Agent

> **Audience:** Partner Solution Architects, SRE teams
> **Status:** Ready to deploy
> **Built by:** Arturo Quiroga (PSA, Microsoft)

This test bed provisions a fully locked-down Azure Container Apps environment and proves that Azure SRE Agent can manage internal-only ACA apps through ARM without VNet connectivity.

## Why ACA is different from AKS

| Dimension | AKS (locked-down) | ACA (locked-down) |
|---|---|---|
| Authorization model | Dual-layer: ARM + Kubernetes RBAC | Single-layer: ARM only |
| Data-plane access | `az aks command invoke` (tunnels kubectl through ARM) | Direct ARM APIs (`az containerapp show/logs/update`) |
| Custom roles needed | Yes — AKS ReadOnly Command Invoke | No — built-in roles suffice |
| VNet injection | API server is private, command invoke bypasses | Environment is internal, ARM management bypasses |
| Log access | KQL via Log Analytics (same) | KQL via Log Analytics (same) |
| Console access | `kubectl exec` via command invoke | `az containerapp exec` (ARM-routed) |

ACA management is simpler because there is no Kubernetes data-plane RBAC layer. All operations go through ARM.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Azure SRE Agent (AI Foundry)                           │
│  Managed Identity (UAMI)                                │
└────────────────────┬────────────────────────────────────┘
                     │ ARM API calls
                     ▼
┌─────────────────────────────────────────────────────────┐
│  Azure Resource Manager                                 │
│  (always publicly reachable)                            │
└────────────────────┬────────────────────────────────────┘
                     │
        ┌────────────┼────────────┐
        ▼            ▼            ▼
┌──────────┐  ┌──────────┐  ┌──────────────┐
│ ACA Env  │  │ ACA Apps │  │ Log Analytics│
│ show/    │  │ show/    │  │ KQL queries  │
│ list     │  │ update/  │  │              │
│          │  │ logs/    │  │              │
│          │  │ restart  │  │              │
└──────────┘  └──────────┘  └──────────────┘
        ▲            ▲
        │  VNet 10.44.0.0/16  │
        │  ┌─────────────┐    │
        └──│ snet-aca     │───┘
           │ 10.44.0.0/21│
           │ internal=true│
           │ No public IP │
           └─────────────┘
```

The SRE Agent never touches the VNet. All management operations route through ARM.

## Locked-down security features

| Feature | Setting | Effect |
|---|---|---|
| VNet-injected environment | `internal: true` | No public IP, no public ingress |
| Subnet delegation | `Microsoft.App/environments` | ACA controls the subnet |
| NSG | Deny all inbound except VNet + LB | No external traffic |
| ACR auth | UAMI + AcrPull role | No admin credentials |
| App ingress | `external: false` | Apps only reachable inside VNet |
| Log Analytics | Workspace-based | All logs queryable via KQL |

## SRE Agent roles (3 roles — simpler than AKS)

| # | Role | Scope | Purpose |
|---|---|---|---|
| 1 | **Reader** | Resource group | List apps, show environment, discover resources |
| 2 | **Contributor** | ACA environment | Restart revisions, scale, update config, view replicas |
| 3 | **Log Analytics Reader** | Log Analytics workspace | KQL queries on container and system logs |

## Deployment

```bash
# 1. Set your SRE Agent's managed identity principal ID
export SRE_AGENT_PRINCIPAL_ID="f54ae888-64d7-451d-a03d-66060918c1a8"

# 2. Provision infrastructure
cd aca-locked-testbed
./scripts/01-provision.sh

# 3. Build and deploy the grocery API
./scripts/02-deploy-app.sh

# 4. Validate SRE Agent access
./scripts/04-validate-sre-access.sh

# 5. Trigger a test incident
./scripts/03-trigger-incident.sh

# 6. Fix the incident
./scripts/03-trigger-incident.sh --fix
```

## SRE Agent test scenarios

After deploying, point the SRE Agent at the resource group and test:

| Scenario | Agent prompt | Expected behavior |
|---|---|---|
| Health check | "What container apps are running and what is their status?" | Lists apps with revision health via `az containerapp list` |
| Failed deployment | "The API app seems broken. What happened?" | Finds failed revision, checks system logs for provisioning errors |
| Log analysis | "Show me recent error logs for the API app" | Queries `ContainerAppConsoleLogs_CL` via KQL |
| Restart | "Restart the API app" | Calls `az containerapp revision restart` through ARM |
| Scale | "Scale the API app to 3 replicas" | Calls `az containerapp update --min-replicas 3` |

## Teardown

```bash
cd aca-locked-testbed
azd down --force --purge
```

## Comparison with AKS locked testbed

| Test | AKS locked testbed | ACA locked testbed |
|---|---|---|
| ARM management | `az aks show`, `az aks update` | `az containerapp show`, `az containerapp update` |
| Workload commands | `az aks command invoke --command "kubectl ..."` | `az containerapp exec`, `az containerapp logs show` |
| Log queries | `KubePodInventory`, `ContainerLog` | `ContainerAppConsoleLogs_CL`, `ContainerAppSystemLogs_CL` |
| Incident trigger | CrashLoopBackOff pod | Bad image tag → ProvisioningFailed revision |
| Roles needed | 4 (including custom) | 3 (all built-in) |
| Data-plane RBAC | Required (AKS RBAC Reader) | Not applicable |
