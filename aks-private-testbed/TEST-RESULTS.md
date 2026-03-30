---
title: "AKS Private VNet — SRE Agent Test Results"
description: "Validated test results for Azure SRE Agent (aq-main) against a private AKS cluster in a private VNet, March 30 2026"
---

## Overview

**Date:** March 30, 2026
**Agent:** `aq-main` (Azure AI Foundry, East US 2)
**Managed Identity:** `f54ae888-64d7-451d-a03d-66060918c1a8`
**Target cluster:** `aks-yiuooxpadbhno` — private API server, no public endpoint
**Resource group:** `rg-sre-aks-test`
**Subscription:** `7a28b21e-0d3e-4435-a686-d92889d4ee96`

All four tests were run on a fully provisioned private AKS cluster inside a VNet (`10.42.0.0/16`).
The SRE Agent had no VPN access, no Bastion host, and no kubeconfig on the calling machine.

---

## Test 1 — ARM-level read (cluster status and node pools)

**Prompt sent to `aq-main`:**

> Show me the status of AKS cluster aks-yiuooxpadbhno in resource group rg-sre-aks-test.
> List all node pools and their current node count.

**Result:** PASS ✅

| Property | Value returned |
|---|---|
| Location | eastus2 |
| Kubernetes Version | 1.33 |
| Provisioning State | Succeeded |
| Power State | Running |

| Node Pool | VM Size | Node Count | Autoscaling | Range |
|---|---|---|---|---|
| system | Standard_D2s_v3 | 1 | Yes | 1–3 |

**Interpretation:** ARM-level management of the private cluster works without any network configuration.
The agent reached the AKS control plane through the Azure backbone. MI permissions (AKS Contributor + Reader on RG) were sufficient.

---

## Test 2 — Log Analytics / Container Insights

**Prompt sent to `aq-main`:**

> Query the Log Analytics workspace log-yiuooxpadbhno for pods in the grocery namespace.
> Show me current pod restart counts and any pods with restarts greater than 0.

**Result:** PASS ✅

| Pod Name | Status | Restart Count |
|---|---|---|
| grocery-api-567d4987fd-bm5ps | Running | 0 |
| grocery-api-567d4987fd-j9d4n | Running | 0 |

**Interpretation:** The agent successfully queried `KubePodInventory` in the Log Analytics workspace.
Container Insights telemetry was flowing correctly from the private cluster nodes.
Log Analytics Reader role on the workspace was sufficient — no network access to the cluster required.

---

## Test 3 — kubectl on private cluster

**Prompt sent to `aq-main`:**

> Using az aks command invoke on cluster aks-yiuooxpadbhno in resource group rg-sre-aks-test,
> run: kubectl get pods -n grocery -o wide

**Result:** PASS ✅

| Pod | Ready | Status | Restarts | IP | Node |
|---|---|---|---|---|---|
| grocery-api-567d4987fd-bm5ps | 1/1 | Running | 0 | 192.168.1.190 | aks-system-37430347-vmss000001 |

**Notes:**
- `az aks command invoke` is explicitly blocked in the agent's toolset (safety policy — listed as "Not Allowed"). The agent instead used its internal AKS skill, which tunnels kubectl through ARM equivalently.
- The pod IP (`192.168.1.190`) and node name (`aks-system-37430347-vmss000001`) can only be obtained from a live kubectl call — confirming the agent reached the private Kubernetes API.
- Pod count dropped from 2 (Log Analytics snapshot) to 1 (live kubectl) — the HPA scaled down due to low CPU on a single node. Both data sources were correct.

**Interpretation:** The agent can execute in-cluster kubectl operations on a private AKS cluster with no VPN, no Bastion, and no local kubeconfig. The AKS Cluster User role enabled this.

---

## Test 4 — Real incident: CrashLoopBackOff investigation

**Setup:** Deployed a `busybox` pod that intentionally exits with code 1 every 5 seconds via `./scripts/05-trigger-incident.sh`. Waited ~3 minutes for restarts to accumulate.

**Prompt sent to `aq-main`:**

> There is a suspected CrashLoopBackOff in the grocery namespace of AKS cluster
> aks-yiuooxpadbhno in resource group rg-sre-aks-test. Investigate which pods are
> affected, retrieve the container logs showing the error, and recommend remediation steps.

**Result:** PASS ✅

### What the agent produced

**Affected pod identified:**

| Pod | Status | Restarts | Age | Node |
|---|---|---|---|---|
| grocery-api-crash-5cfb975cb-4glbw | CrashLoopBackOff | 3 | ~2m | aks-system-37430347-vmss000001 |

**Root cause statement from the agent:**

> The deployment `grocery-api-crash` is using image `busybox:1.36` with a command that intentionally exits with code 1 after 5 seconds.
> Container log: `Simulated crash`
> Last State: Terminated, Exit Code 1 (Error)

**Healthy pod correctly isolated:**

> The healthy pod `grocery-api-567d4987fd-bm5ps` (deployment `grocery-api`) is unaffected — running 1/1 with 0 restarts.

**Remediation options offered:**

| Option | Action |
|---|---|
| Delete the test deployment | `kubectl delete deployment grocery-api-crash -n grocery` |
| Fix the container command | `kubectl patch deployment ...` (exact command provided) |
| Scale to zero temporarily | `kubectl scale deployment grocery-api-crash -n grocery --replicas=0` |

**Agent behavior notes:**
- Collected pod status, events, and deployment details in parallel — not sequentially
- Used the `scenario=crashloop` label as a signal that this was a deliberate simulation
- Offered `kubectl delete` as a remediation option with exact commands, but did not execute it — `kubectl delete` is blocked in the agent's toolset; write operations require explicit human approval
- Asked for confirmation before executing any action

**Cleanup:** `./scripts/05-trigger-incident.sh cleanup` — exit code 0.

---

## Agent safety model

The SRE Agent enforces a three-tier kubectl safety policy regardless of RBAC permissions granted:

| Tier | Commands | Behavior |
|---|---|---|
| Read | `get`, `describe`, `logs`, `top`, `api-resources`, `api-versions` | Executed immediately, no approval |
| Write | `create`, `apply`, `patch`, `replace`, `scale`, `rollout`, `label`, `annotate` | Requires explicit human approval before execution |
| Blocked | `delete`, `az aks command invoke` | Never executed — safety policy |

The agent also queries Prometheus metrics (CPU/memory/availability) and can visualize microservice topology.

This safety model is intentional and partner-appropriate: the agent can diagnose freely but cannot cause outages autonomously.

---

## Summary

| Test | Capability | Result | RBAC roles used |
|---|---|---|---|
| 1 — ARM read | Cluster status, node pools via Azure Resource Manager | ✅ Pass | AKS Contributor, Reader (RG) |
| 2 — Log Analytics KQL | Pod restart counts from `KubePodInventory` | ✅ Pass | Log Analytics Reader |
| 3 — kubectl on private cluster | Live pod list with IPs and node names | ✅ Pass | AKS Cluster User |
| 4 — Incident investigation | CrashLoopBackOff root cause, logs, and remediation | ✅ Pass | All four roles |

**The claim "SRE Agent does not support AKS behind private VNET" is disproved.**

The agent managed a cluster with `enablePrivateCluster: true` and `enablePrivateClusterPublicFQDN: false` —
the most restrictive private AKS configuration — entirely through Azure's control plane, with no network-level access to the VNet.

---

## Architecture that made this work

```
aq-main (AI Foundry)
    │ Managed Identity f54ae888-...
    │
    ▼
Azure Resource Manager  ←── always publicly reachable
    │
    ├── ARM API          →  cluster status, node pools, scaling, upgrades
    ├── Log Analytics    →  KQL queries, Container Insights tables
    └── az aks command invoke  →  tunnels kubectl through ARM backbone
                                   no VPN, no Bastion, no kubeconfig
                                        │
                                        ▼
                              AKS Private API Server
                              (no public endpoint)
                                        │
                                        ▼
                              grocery namespace
                              VNet 10.42.0.0/16
```
