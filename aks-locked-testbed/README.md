---
title: AKS Locked-Down Testbed
description: Zafin-style AKS cluster with public endpoint, authorized IP ranges, Azure RBAC, and 4-role SRE Agent access model
author: Arturo Quiroga
ms.date: 2026-04-14
ms.topic: reference
---

## Overview

This testbed replicates the Zafin partner AKS pattern for SRE Agent testing.
Unlike the `aks-private-testbed` (fully private cluster), this variant uses a
**public API server locked down with authorized IP ranges + Azure RBAC**.

Source: `partner-context/Zafin-AKSDetails/` (Zoya's Terraform + role JSON).

## Architecture comparison

| Property | aks-private-testbed | aks-locked-testbed (this) |
|----------|--------------------|-----------------------|
| API server | Private (no public endpoint) | Public + authorized IP ranges |
| Network lockdown | Private Link | Authorized IP ranges only (no NSG) |
| Azure RBAC | Not enabled | Enabled (`enableAzureRBAC: true`) |
| Local accounts | Enabled | Disabled |
| SKU tier | Free | Standard |
| SRE Agent roles | Built-in roles (full access) | 4 roles (1 custom + 3 built-in) |
| kubectl method | `az aks command invoke` | `az aks command invoke` (ARM backbone) |

## Quick start

```bash
cd aks-locked-testbed
azd auth login
azd init -e sre-locked
azd env set AZURE_LOCATION westus2
./scripts/01-provision.sh
```

## Post-provisioning steps

### Add your IP to authorized ranges

```bash
MY_IP=$(curl -s ifconfig.me)
RG=$(azd env get-values | grep ^AZURE_RESOURCE_GROUP | cut -d= -f2 | tr -d '"')
AKS=$(azd env get-values | grep ^AKS_CLUSTER_NAME | cut -d= -f2 | tr -d '"')
az aks update -g "$RG" -n "$AKS" --api-server-authorized-ip-ranges "${MY_IP}/32"
```

### Assign SRE Agent roles

```bash
# Use the SRE Agent managed identity principal ID
./scripts/02-assign-sre-agent.sh f54ae888-64d7-451d-a03d-66060918c1a8
```

### Deploy grocery-api workload

```bash
./scripts/03-deploy-workload.sh
```

## SRE Agent role assignments (from Zoya's SRE_MI_Roles.json)

The template assigns **4 roles** to the SRE Agent managed identity:

### 1. Reader (built-in)

- Role ID: `acdd72a7-3385-48ef-bd42-f606fba81ae7`
- Scope: Resource group
- Permissions: `*/read`

### 2. AKS ReadOnly Command Invoke (custom)

- Scope: AKS cluster
- Permissions (4 actions only):
  - `Microsoft.ContainerService/managedClusters/read`
  - `Microsoft.ContainerService/managedClusters/listClusterUserCredential/action`
  - `Microsoft.ContainerService/managedClusters/runcommand/action`
  - `Microsoft.ContainerService/managedClusters/commandResults/read`

### 3. Log Analytics Reader (built-in)

- Role ID: `73c42c96-874c-492b-b04d-ab87d138a893`
- Scope: Log Analytics workspace

### 4. Azure Kubernetes Service RBAC Reader (built-in)

- Role ID: `7f6c6a51-bcf8-42ba-9220-52d62157d7db`
- Scope: AKS cluster
- Provides 30+ `dataActions` for read-only K8s access (pods, deployments,
  events, services, configmaps, namespaces, etc.)
- Does NOT allow: reading Secrets, writing, deleting, or exec'ing into pods

## File structure

```text
aks-locked-testbed/
  azure.yaml                     # azd project definition
  README.md                      # this file
  infra/
    abbreviations.json           # resource name prefixes
    main.bicep                   # subscription-scoped entry point
    main.parameters.json         # azd parameter bindings
    resources.bicep              # all Azure resources
  scripts/
    01-provision.sh              # azd provision wrapper
    02-assign-sre-agent.sh       # assign roles to SRE Agent MI
    03-deploy-workload.sh        # build + deploy grocery-api to AKS
```
