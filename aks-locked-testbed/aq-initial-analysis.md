Good question. Here's my analysis of why Zoya's kubectl is failing and what we need to test:

**The problem is likely the intersection of 3 settings:**

1. **`disableLocalAccounts: true`** — No local kubeconfig (certificate-based auth is gone)
2. **`azure_rbac_enabled: true`** — All K8s API calls must go through Entra ID + Azure RBAC
3. **`az aks command invoke`** — When Azure RBAC is enabled, command invoke runs as the **calling identity**, not as cluster-admin

**What this means for the SRE Agent:**

When command invoke runs `kubectl get pods`, the flow is:
- **ARM layer**: needs `runcommand/action` — Zoya's custom role has this
- **K8s layer**: the kubectl command runs as the SRE Agent MI, which needs **dataActions** to read K8s objects

Zoya's `AKS RBAC Reader` role (`7f6c6a51`) provides the dataActions (pods/read, deployments/read, etc.), so **read-only commands should theoretically work**.

**Possible failure points to test:**

| Command | Expected | Potential Issue |
|---------|----------|----------------|
| `kubectl get pods` | Works | AKS RBAC Reader covers `pods/read` |
| `kubectl get nodes` | Works | Covered by `metrics.k8s.io/nodes/read` |
| `kubectl logs <pod>` | **May fail** | Needs `pods/log` — NOT in AKS RBAC Reader |
| `kubectl describe pod` | Works | Covered by `pods/read` + `events/read` |
| `kubectl exec` | Fails (by design) | Not in Reader |
| `kubectl top pods` | Works | `metrics.k8s.io/pods/read` is included |

**The most likely cause of Zoya's failures:**

1. **Timeout = the SRE Agent service itself may not be propagating identity correctly** through command invoke when Azure RBAC is enabled. The ARM call succeeds, but the K8s API server rejects the identity because it can't resolve the MI's token to Azure RBAC permissions.

2. **Missing `listClusterUserCredential`** — Command invoke internally calls `listClusterUserCredential`. With local accounts disabled, this returns an Entra-based kubeconfig. Zoya's role has this, but if the Entra token isn't propagated properly inside the command invoke pod, it's a dead end.

3. **The SRE Agent might use a different mechanism** than standard `az aks command invoke` — it may call the AKS API directly via ARM REST, and the identity chain might break.

**What to test in our locked testbed (in order):**

1. Run `az aks command invoke` as **yourself** (your Entra identity) — does it work?
2. Run it with the SRE Agent MI — does that work?
3. If #1 works but #2 fails, it's an Azure RBAC dataAction propagation issue with the MI
4. Try adding `Azure Kubernetes Service RBAC Cluster Admin` (`b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b`) temporarily to see if elevated K8s RBAC fixes it — then narrow down which specific dataActions are missing

This is exactly why we built this testbed — to isolate whether the problem is the role assignments, the Azure RBAC + command invoke interaction, or something in the SRE Agent's identity chain.