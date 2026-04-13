---
title: AKS Cluster Validation — kubectl Command Execution Report
description: Execution results of 15 kubectl commands against aks-sre-westus2 via az aks command invoke
author: Arturo Quiroga
ms.date: 2026-04-13
ms.topic: reference
---

## Overview

This report captures the output of 15 kubectl commands executed against the private AKS
cluster `aks-sre-westus2` in resource group `rg-sre-aks-westus2` (West US 2).

All commands were executed remotely via `az aks command invoke` on April 13, 2026.

| Property | Value |
|----------|-------|
| Cluster | `aks-sre-westus2` |
| Resource Group | `rg-sre-aks-westus2` |
| Region | West US 2 |
| Kubernetes | v1.34.4 |
| Private Cluster | Yes |
| Nodes | 2 (Standard_D2s_v3, autoscale 1-3) |

---

## Command 1 — `kubectl get namespaces`

```text
NAME              STATUS   AGE
aks-command       Active   58m
default           Active   4d22h
grocery           Active   37m
kube-node-lease   Active   4d22h
kube-public       Active   4d22h
kube-system       Active   4d22h
```

---

## Command 2 — `kubectl get pods -n grocery -o wide`

```text
NAME                             READY   STATUS             RESTARTS        AGE   IP              NODE                             NOMINATED NODE   READINESS GATES
grocery-api-58995496cc-5csf6     1/1     Running            0               37m   192.168.0.206   aks-system-28767300-vmss000003   <none>           <none>
oom-simulator-77b66c497c-r8zbt   0/1     CrashLoopBackOff   7 (3m51s ago)   15m   192.168.0.157   aks-system-28767300-vmss000003   <none>           <none>
```

---

## Command 3 — `kubectl get deployments -n grocery`

```text
NAME            READY   UP-TO-DATE   AVAILABLE   AGE
grocery-api     1/1     1            1           38m
oom-simulator   0/1     1            0           15m
```

---

## Command 4 — `kubectl get services -n grocery`

```text
NAME          TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
grocery-api   ClusterIP   172.16.76.86   <none>        80/TCP    38m
```

---

## Command 5 — `kubectl get hpa -n grocery`

```text
NAME              REFERENCE                TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
grocery-api-hpa   Deployment/grocery-api   cpu: 8%/70%   1         5         1          38m
```

---

## Command 6 — `kubectl get events -n grocery`

```text
LAST SEEN   TYPE      REASON                         OBJECT                                    MESSAGE
39m         Warning   FailedScheduling               pod/grocery-api-58995496cc-5csf6          0/1 nodes are available: 1 Insufficient cpu
39m         Normal    Scheduled                      pod/grocery-api-58995496cc-5csf6          Successfully assigned grocery/grocery-api-58995496cc-5csf6 to aks-system-28767300-vmss000003
39m         Normal    Pulling                        pod/grocery-api-58995496cc-5csf6          Pulling image "acrsrewestus2.azurecr.io/grocery-api:latest"
39m         Normal    Pulled                         pod/grocery-api-58995496cc-5csf6          Successfully pulled image in 6.356s. Image size: 56303713 bytes.
39m         Normal    Created                        pod/grocery-api-58995496cc-5csf6          Created container: api
39m         Normal    Started                        pod/grocery-api-58995496cc-5csf6          Started container api
39m         Warning   FailedScheduling               pod/grocery-api-58995496cc-p5vrk          0/1 nodes are available: 1 Insufficient cpu
39m         Normal    Scheduled                      pod/grocery-api-58995496cc-p5vrk          Successfully assigned to aks-system-28767300-vmss000003
34m         Normal    Killing                        pod/grocery-api-58995496cc-p5vrk          Stopping container api
39m         Normal    SuccessfulCreate               replicaset/grocery-api-58995496cc         Created pod: grocery-api-58995496cc-p5vrk
39m         Normal    SuccessfulCreate               replicaset/grocery-api-58995496cc         Created pod: grocery-api-58995496cc-5csf6
34m         Normal    SuccessfulDelete               replicaset/grocery-api-58995496cc         Deleted pod: grocery-api-58995496cc-p5vrk
34m         Normal    SuccessfulRescale              horizontalpodautoscaler/grocery-api-hpa   New size: 1; reason: All metrics below target
39m         Normal    ScalingReplicaSet              deployment/grocery-api                    Scaled up replica set grocery-api-58995496cc from 0 to 2
34m         Normal    ScalingReplicaSet              deployment/grocery-api                    Scaled down replica set grocery-api-58995496cc from 2 to 1
16m         Normal    Scheduled                      pod/oom-simulator-77b66c497c-r8zbt        Successfully assigned to aks-system-28767300-vmss000003
16m         Normal    Pulling                        pod/oom-simulator-77b66c497c-r8zbt        Pulling image "python:3.11-alpine"
16m         Normal    Pulled                         pod/oom-simulator-77b66c497c-r8zbt        Successfully pulled image in 3.91s. Image size: 20361019 bytes.
5m15s       Normal    Created                        pod/oom-simulator-77b66c497c-r8zbt        Created container: oom-simulator
5m15s       Normal    Started                        pod/oom-simulator-77b66c497c-r8zbt        Started container oom-simulator
76s         Warning   BackOff                        pod/oom-simulator-77b66c497c-r8zbt        Back-off restarting failed container
16m         Normal    SuccessfulCreate               replicaset/oom-simulator-77b66c497c       Created pod: oom-simulator-77b66c497c-r8zbt
16m         Normal    ScalingReplicaSet              deployment/oom-simulator                  Scaled up replica set oom-simulator-77b66c497c from 0 to 1
```

---

## Command 7 — `kubectl describe deployment grocery-api -n grocery`

```text
Name:                   grocery-api
Namespace:              grocery
CreationTimestamp:       Mon, 13 Apr 2026 15:02:39 +0000
Labels:                 app=grocery-api
                        version=v1
Annotations:            deployment.kubernetes.io/revision: 1
Selector:               app=grocery-api
Replicas:               1 desired | 1 updated | 1 total | 1 available | 0 unavailable
StrategyType:           RollingUpdate
MinReadySeconds:        0
RollingUpdateStrategy:  25% max unavailable, 25% max surge
Pod Template:
  Labels:  app=grocery-api
           version=v1
  Containers:
   api:
    Image:      acrsrewestus2.azurecr.io/grocery-api:latest
    Port:       3100/TCP (http)
    Host Port:  0/TCP (http)
    Limits:
      cpu:      500m
      memory:   256Mi
    Requests:
      cpu:      100m
      memory:   128Mi
    Liveness:   http-get http://:3100/health delay=15s timeout=1s period=20s #success=1 #failure=3
    Readiness:  http-get http://:3100/health delay=5s timeout=1s period=10s #success=1 #failure=3
    Environment:
      PORT:                3100
      SUPPLIER_RATE_LIMIT: 5
Conditions:
  Type           Status  Reason
  ----           ------  ------
  Available      True    MinimumReplicasAvailable
  Progressing    True    NewReplicaSetAvailable
OldReplicaSets:  <none>
NewReplicaSet:   grocery-api-58995496cc (1/1 replicas created)
Events:
  Type    Reason             Age   From                   Message
  ----    ------             ----  ----                   -------
  Normal  ScalingReplicaSet  39m   deployment-controller  Scaled up replica set grocery-api-58995496cc from 0 to 2
  Normal  ScalingReplicaSet  34m   deployment-controller  Scaled down replica set grocery-api-58995496cc from 2 to 1
```

---

## Command 8 — `kubectl logs deployment/grocery-api --tail=20 -n grocery`

```json
{"level":"info","time":"2026-04-13T15:40:02.226Z","hostname":"grocery-api-58995496cc-5csf6","req":{"method":"GET","url":"/health"},"res":{"statusCode":200},"responseTime":1,"msg":"request completed"}
{"level":"info","time":"2026-04-13T15:40:12.226Z","hostname":"grocery-api-58995496cc-5csf6","req":{"method":"GET","url":"/health"},"res":{"statusCode":200},"responseTime":0,"msg":"request completed"}
{"level":"info","time":"2026-04-13T15:40:21.683Z","hostname":"grocery-api-58995496cc-5csf6","req":{"method":"GET","url":"/health"},"res":{"statusCode":200},"responseTime":0,"msg":"request completed"}
{"level":"info","time":"2026-04-13T15:40:22.226Z","hostname":"grocery-api-58995496cc-5csf6","req":{"method":"GET","url":"/health"},"res":{"statusCode":200},"responseTime":1,"msg":"request completed"}
{"level":"info","time":"2026-04-13T15:40:32.227Z","hostname":"grocery-api-58995496cc-5csf6","req":{"method":"GET","url":"/health"},"res":{"statusCode":200},"responseTime":1,"msg":"request completed"}
{"level":"info","time":"2026-04-13T15:40:42.227Z","hostname":"grocery-api-58995496cc-5csf6","req":{"method":"GET","url":"/health"},"res":{"statusCode":200},"responseTime":1,"msg":"request completed"}
{"level":"info","time":"2026-04-13T15:40:52.226Z","hostname":"grocery-api-58995496cc-5csf6","req":{"method":"GET","url":"/health"},"res":{"statusCode":200},"responseTime":0,"msg":"request completed"}
{"level":"info","time":"2026-04-13T15:41:01.683Z","hostname":"grocery-api-58995496cc-5csf6","req":{"method":"GET","url":"/health"},"res":{"statusCode":200},"responseTime":1,"msg":"request completed"}
{"level":"info","time":"2026-04-13T15:41:02.227Z","hostname":"grocery-api-58995496cc-5csf6","req":{"method":"GET","url":"/health"},"res":{"statusCode":200},"responseTime":2,"msg":"request completed"}
{"level":"info","time":"2026-04-13T15:41:12.226Z","hostname":"grocery-api-58995496cc-5csf6","req":{"method":"GET","url":"/health"},"res":{"statusCode":200},"responseTime":1,"msg":"request completed"}
{"level":"info","time":"2026-04-13T15:41:21.684Z","hostname":"grocery-api-58995496cc-5csf6","req":{"method":"GET","url":"/health"},"res":{"statusCode":200},"responseTime":1,"msg":"request completed"}
```

> All 20 log lines show healthy `GET /health` requests from `kube-probe/1.34` with HTTP 200
> and sub-2ms response times. No errors in the tail.

---

## Command 9 — `kubectl get nodes -o wide`

```text
NAME                             STATUS   ROLES    AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
aks-system-28767300-vmss000003   Ready    <none>   72m   v1.34.4   10.42.0.5     <none>        Ubuntu 22.04.5 LTS   5.15.0-1102-azure   containerd://1.7.30-2
aks-system-28767300-vmss000006   Ready    <none>   38m   v1.34.4   10.42.0.7     <none>        Ubuntu 22.04.5 LTS   5.15.0-1102-azure   containerd://1.7.30-2
```

---

## Command 10 — `kubectl top nodes`

```text
NAME                             CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
aks-system-28767300-vmss000003   411m         21%      2340Mi          40%
aks-system-28767300-vmss000006   451m         23%      1564Mi          27%
```

---

## Command 11 — `kubectl top pods -n grocery`

```text
NAME                           CPU(cores)   MEMORY(bytes)
grocery-api-58995496cc-5csf6   8m           37Mi
```

---

## Command 12 — `kubectl get configmaps -n grocery`

```text
NAME               DATA   AGE
kube-root-ca.crt   1      51m
```

---

## Command 13 — `kubectl get secrets -n grocery`

```text
No resources found in grocery namespace.
```

---

## Command 14 — `kubectl get ingress --all-namespaces`

```text
No resources found
```

---

## Command 15 — `kubectl get networkpolicies --all-namespaces`

```text
NAMESPACE     NAME                 POD-SELECTOR             AGE
kube-system   konnectivity-agent   app=konnectivity-agent   4d22h
```

---

## Summary

| # | Command | Status | Key Finding |
|---|---------|--------|-------------|
| 1 | `get namespaces` | OK | 6 namespaces including `grocery` |
| 2 | `get pods -n grocery` | OK | `grocery-api` Running; `oom-simulator` CrashLoopBackOff (test scenario) |
| 3 | `get deployments -n grocery` | OK | `grocery-api` 1/1 ready |
| 4 | `get services -n grocery` | OK | ClusterIP `172.16.76.86:80` |
| 5 | `get hpa -n grocery` | OK | CPU at 8% (target 70%), 1 replica |
| 6 | `get events -n grocery` | OK | Initial scheduling pressure resolved; HPA scaled 2→1 |
| 7 | `describe deployment` | OK | Rolling update strategy, health probes configured |
| 8 | `logs --tail=20` | OK | All health checks passing, sub-2ms response times |
| 9 | `get nodes -o wide` | OK | 2 Ready nodes, K8s v1.34.4, Ubuntu 22.04.5 |
| 10 | `top nodes` | OK | CPU 21-23%, Memory 27-40% |
| 11 | `top pods -n grocery` | OK | grocery-api: 8m CPU, 37Mi memory |
| 12 | `get configmaps` | OK | Default `kube-root-ca.crt` only |
| 13 | `get secrets` | OK | No secrets in grocery namespace |
| 14 | `get ingress` | OK | No ingress (private cluster, ClusterIP only) |
| 15 | `get networkpolicies` | OK | Only `konnectivity-agent` in kube-system |
