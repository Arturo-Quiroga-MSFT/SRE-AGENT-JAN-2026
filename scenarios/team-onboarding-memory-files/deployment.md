## Deployment

### Pipeline

**Method:** Azure Developer CLI (`azd up`) + manual scripts for MCP servers

| Phase | Command | Time |
|---|---|---|
| Base infra (API, Web, Grafana, ACR) | `cd grocery-sre-demo && azd up` | 20–30 min |
| Loki | `./scripts/deploy-loki.sh` | ~10 min |
| MCP servers (Grafana + Jira) | `./scripts/deploy-mcp-servers.sh` | ~15 min |
| SRE Agent setup | Azure Portal manual config | ~20 min |
| **Total from scratch** | | **~90 min (with this guide: ~60 min)** |

### Container Images

| App | Image | Registry |
|---|---|---|
| Grocery API | `grocery-sre-demo/api-aqsre:azd-deploy-<timestamp>` | `crps64h2ydsavgc.azurecr.io` |
| Grocery Web | `grocery-sre-demo/web-aqsre:azd-deploy-<timestamp>` | `crps64h2ydsavgc.azurecr.io` |
| Grafana MCP | `grafana-mcp-streamable:latest` | `crps64h2ydsavgc.azurecr.io` |
| Jira MCP | `ghcr.io/sooperset/mcp-atlassian:latest` | GitHub Container Registry |
| Loki | `grafana/loki:2.9.0` | Docker Hub |

### Find Current Version

```bash
# Container App image tag
az containerapp show -g rg-aqsre -n ca-api-ps64h2ydsavgc \
  --query "properties.template.containers[0].image" -o tsv

# All active revisions
az containerapp revision list -g rg-aqsre -n ca-api-ps64h2ydsavgc \
  --query "[?properties.active].{name:name, image:properties.template.containers[0].image}" -o table
```

### Rollback

```bash
# List revisions
az containerapp revision list -g rg-aqsre -n ca-api-ps64h2ydsavgc -o table

# Activate a previous revision
az containerapp revision activate -g rg-aqsre -n ca-api-ps64h2ydsavgc \
  --revision <previous-revision-name>

# Route traffic to previous revision
az containerapp ingress traffic set -g rg-aqsre -n ca-api-ps64h2ydsavgc \
  --revision-weight <previous-revision-name>=100
```

### Full Redeploy

```bash
# Tear down everything
azd down --purge --force

# Redeploy from scratch
azd up
```

See also: [SRE_AGENT_QUICK_RECREATE.md](https://github.com/Arturo-Quiroga-MSFT/SRE-AGENT-JAN-2026/blob/main/docs/SRE_AGENT_QUICK_RECREATE.md)

### Known Issue: npm ci + package-lock.json

The upstream `grocery-sre-demo` repo has `package-lock.json` in `.gitignore` but Dockerfiles use `npm ci`. Fix: commit lock files or change to `npm install --omit=dev`. See [BUG_REPORT_FOR_UPSTREAM.md](https://github.com/Arturo-Quiroga-MSFT/SRE-AGENT-JAN-2026/blob/main/docs/BUG_REPORT_FOR_UPSTREAM.md).
