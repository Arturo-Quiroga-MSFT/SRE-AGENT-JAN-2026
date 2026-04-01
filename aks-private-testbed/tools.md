FYI, see this response from the SRE agent: Here's what I can execute on your AKS cluster:

### Read Commands (run immediately, no approval needed)
| Command | Purpose |
|---|---|
| `kubectl get` | List resources (pods, deployments, services, nodes, etc.) |
| `kubectl describe` | Detailed resource info, events, conditions |
| `kubectl logs` | Container logs (current and previous) |
| `kubectl top` | Resource usage (CPU/memory) for pods and nodes |
| `kubectl api-resources` | List available resource types |
| `kubectl api-versions` | List available API versions |

### Write Commands (require your approval)
| Command | Purpose |
|---|---|
| `kubectl create` | Create new resources |
| `kubectl apply` | Apply configuration from manifests |
| `kubectl patch` | Modify specific fields on a resource |
| `kubectl replace` | Replace a resource definition |
| `kubectl scale` | Change replica count |
| `kubectl rollout` | Manage rollouts (status, undo, restart) |
| `kubectl label` | Add/update labels |
| `kubectl annotate` | Add/update annotations |

### Not Allowed
| Command | Reason |
|---|---|
| `kubectl delete` | Blocked for safety — no destructive operations |
| `az aks command invoke` | Restricted command |

I can also query **Prometheus metrics** (CPU, memory, availability) and **visualize microservice topology** for the cluster. Let me know what you need.



