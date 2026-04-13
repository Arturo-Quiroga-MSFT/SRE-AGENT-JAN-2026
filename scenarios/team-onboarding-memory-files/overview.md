## Azure SRE Agent PoC — Grocery API

End-to-end PoC demonstrating Azure SRE Agent with Grafana/Loki + Jira via MCP connectors. Also validated on fully private AKS clusters (no public endpoint).

**Repo:** `Arturo-Quiroga-MSFT/SRE-AGENT-JAN-2026` (main branch)
**Partner:** Zafin — weekly working sessions to prove out scenarios

### Glue

| Connection | How |
|---|---|
| Code → Infra | `grocery-sre-demo/src/api` → Container App `ca-api-ps64h2ydsavgc` in `rg-aqsre` |
| Infra → Logs | Container App pushes JSON logs via HTTP → Loki (`ca-loki`) → Grafana |
| Logs → Code | Loki label `app="grocery-api"`, errorCode field maps to `src/api/index.js` |
| Deploy → Version | `kubectl` or `az containerapp show` → image tag `azd-deploy-<timestamp>` |
| Correlation | Structured JSON logs with `event`, `productId`, `errorCode` fields |

### Key Resources

| Resource | Name | Purpose |
|---|---|---|
| Container App (API) | `ca-api-ps64h2ydsavgc` | Grocery API (Node.js) |
| Container App (Web) | `ca-web-ps64h2ydsavgc` | Web frontend |
| Loki | `ca-loki` | Log aggregation |
| Grafana MCP | `ca-mcp-grafana` | MCP server (Streamable-HTTP) |
| Jira MCP | `ca-mcp-jira` | MCP server (HTTP/FastMCP) |
| Managed Grafana | `amg-ps64h2ydsavgc` | Dashboards + Loki datasource |
| ACR | `crps64h2ydsavgc` | Container images |
| SRE Agent | `aq-main` | Main agent (DiagnosticExpert subagent, 127 tools) |

### Quick Links

- [Architecture](architecture.md) — components, data flow, environments
- [Team](team.md) — who knows what, engagement model
- [Logs](logs.md) — Loki labels, first queries, correlation
- [Deployment](deployment.md) — azd pipeline, version lookup, rollback
- [Auth](auth.md) — managed identity, Grafana SA token, Jira API token
- [Debugging](debugging.md) — 429 runbook, common issues, TSGs
- [Dashboards](dashboards.md) — Grafana links, dashboard panels
