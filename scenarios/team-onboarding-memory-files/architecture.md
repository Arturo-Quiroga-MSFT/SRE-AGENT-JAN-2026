## Architecture

### Components

| Component | Container App | Repo Source | Image | Purpose |
|---|---|---|---|---|
| Grocery API | `ca-api-ps64h2ydsavgc` | `grocery-sre-demo/src/api` | `crps64h2ydsavgc.azurecr.io/grocery-sre-demo/api-aqsre` | Node.js Express API — rate limiting, product catalog, demo triggers |
| Web Frontend | `ca-web-ps64h2ydsavgc` | `grocery-sre-demo/src/web` | `crps64h2ydsavgc.azurecr.io/grocery-sre-demo/web-aqsre` | Static frontend with demo trigger buttons |
| Loki | `ca-loki` | `grafana/loki:2.9.0` | Official image | Log aggregation — receives JSON logs via HTTP push |
| Grafana MCP Server | `ca-mcp-grafana` | Custom Dockerfile | `crps64h2ydsavgc.azurecr.io/grafana-mcp-streamable:latest` | MCP bridge to Grafana (Streamable-HTTP transport) |
| Jira MCP Server | `ca-mcp-jira` | `ghcr.io/sooperset/mcp-atlassian` | Community image | MCP bridge to Jira Cloud (FastMCP 2.14.5, HTTP transport) |

### Azure Resources (rg-aqsre, East US 2)

| Resource | Name | Type |
|---|---|---|
| Container Apps Environment | `cae-ps64h2ydsavgc` | Microsoft.App/managedEnvironments |
| Azure Container Registry | `crps64h2ydsavgc` | Microsoft.ContainerRegistry/registries |
| Azure Managed Grafana | `amg-ps64h2ydsavgc` | Microsoft.Dashboard/grafana |
| Azure SRE Agent | `aq-main` | Microsoft.App/agents |
| App Insights | `aq-app-insights-001` | Microsoft.Insights/components |
| Log Analytics Workspace | `aqmlwork0019254899053` | Microsoft.OperationalInsights/workspaces |

### SRE Agent Internals

```
aq-main (Main Agent)
  └── DiagnosticExpert (Subagent, 127 tools)
      ├── Knowledge file: loki-queries.md
      ├── Connector: grafana-mcp (Streamable-HTTP)
      │   └── ca-mcp-grafana → Azure Managed Grafana → Loki
      └── Connector: jira-mcp (Streamable-HTTP)
          └── ca-mcp-jira → Jira Cloud (aq-r2d2.atlassian.net, project: SCRUM/ACV2)
```

### Data Flow

```
User → Web Frontend → Grocery API → (simulated) FreshFoods Wholesale API
                          │
                          ├── Logs (JSON via HTTP) → Loki → Grafana
                          │
                          └── On incident:
                              SRE Agent → DiagnosticExpert
                                  ├── grafana-mcp → Loki (LogQL queries)
                                  └── jira-mcp → Jira Cloud (ticket creation)
```

### API Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/products` | Product catalog (subject to rate limiting) |
| POST | `/api/demo/trigger-rate-limit` | Simulates 429 storm from supplier API |
| POST | `/api/demo/cpu-stress` | CPU load simulation |
| POST | `/api/demo/memory-leak` | Memory leak simulation |
| GET | `/health` | Liveness probe (anonymous) |

### Container App Env Vars (ca-api)

| Var | Value | Notes |
|---|---|---|
| `PORT` | `3100` | API listen port |
| `SUPPLIER_RATE_LIMIT` | `5` | Current supplier rate limit (was 10, reduced) |
| `LOKI_HOST` | `https://ca-loki.icymeadow-96da5d2b.eastus2.azurecontainerapps.io` | Loki push endpoint |

### AKS Private VNet Testbed (rg-sre-aks-test)

Separate environment proving SRE Agent works with fully private AKS:

| Resource | Name | Notes |
|---|---|---|
| AKS Cluster | `aks-yiuooxpadbhno` | Private API server, no public endpoint |
| VNet | `10.42.0.0/16` | Azure CNI Overlay, subnet `snet-aks 10.42.0.0/22` |
| Log Analytics | `log-yiuooxpadbhno` | Container Insights tables |

**Access pattern (no VPN needed):**
- ARM operations → always reachable (public ARM endpoint)
- Log Analytics KQL → always reachable (public LA endpoint)
- kubectl → tunneled via `az aks command invoke` through ARM backbone

### Critical Design Decision

**Azure SRE Agent requires Streamable-HTTP transport, NOT SSE.** The official Grafana MCP image defaults to SSE, so a custom Docker image was built to force Streamable-HTTP via ENTRYPOINT override.
