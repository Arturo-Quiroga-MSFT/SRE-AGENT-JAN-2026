# Grocery SRE Demo — Application Architecture

## Overview

The grocery-sre-demo is a food ordering application deployed on **Azure Container Apps**
in resource group `rg-aqsre`. It is the primary monitored application for the SRE Agent
PoC. The SRE Agent investigates and remediates issues with this app using Loki logs
(via Grafana MCP) and Jira for incident tracking.

---

## Infrastructure

| Component | Azure Service | Details |
|-----------|---------------|---------|
| **API** | Azure Container App | Node.js Express, port 3100, external ingress |
| **Web** | Azure Container App | Static frontend, port 3001, external ingress |
| **Loki** | Azure Container App | Log aggregator, HTTP ingest + query, port 3100 |
| **Container Environment** | Container Apps Environment | `cae-<suffix>`, linked to Log Analytics |
| **Container Registry** | ACR | `cr<suffix>.azurecr.io` — admin auth enabled |
| **Log Analytics** | LA Workspace | Container infrastructure logs |
| **Grafana** | Azure Managed Grafana | Dashboard + Loki datasource |
| **Identity** | User-Assigned Managed Identity | Agent uses this for RBAC access |

### Container App Names (resource group: `rg-aqsre`)

| Role | Container App Name Pattern |
|------|---------------------------|
| API | `ca-api-<suffix>` |
| Web frontend | `ca-web-<suffix>` |
| Loki | `ca-loki-<suffix>` |
| Grafana MCP | `ca-mcp-grafana-<suffix>` |
| Jira MCP | `ca-mcp-jira-<suffix>` |

> **Tip:** Get the exact names with:
> ```bash
> az containerapp list -g rg-aqsre --query "[].name" -o tsv
> ```

---

## Application Endpoints

### API (`ca-api-<suffix>`)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Liveness probe — returns `{ status: "ok" }` |
| `/api/products` | GET | Product catalog — calls FreshFoods Wholesale API |
| `/metrics` | GET | Prometheus metrics (CPU, request count, supplier calls) |
| `/api/demo/trigger-rate-limit` | POST | **Triggers** supplier rate limit scenario (55+ 429 errors) |
| `/api/demo/cpu-stress` | POST | **Triggers** CPU load scenario |
| `/api/demo/memory-leak` | POST | **Triggers** memory growth scenario |

### Web (`ca-web-<suffix>`)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Product catalog UI with incident trigger buttons |
| `/health` | GET | Liveness probe |

### Loki (`ca-loki-<suffix>`)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/loki/api/v1/push` | POST | Log ingest (used by API container) |
| `/loki/api/v1/query_range` | GET | LogQL range query |
| `/ready` | GET | Readiness check |

> **Note:** `GET /` on Loki returns 404 — this is expected. Only the `/loki/api/v1/...` paths respond.

---

## Observability Stack

### Logging: Loki

All application logs flow from `ca-api` → Loki via HTTP push. Labels used:

| Label | Values |
|-------|--------|
| `app` | `grocery-api` |
| `job` | `grocery-api` |
| `level` | `info`, `warn`, `error` |
| `environment` | `production` |

**Log format:** Structured JSON via `pino-http`. Key fields:

| Field | Description |
|-------|-------------|
| `event` | Event type (e.g., `supplier_rate_limited`) |
| `errorCode` | Structured error code |
| `message` | Human-readable description |
| `statusCode` | HTTP status code |
| `retryAfter` | Seconds until retry (429 scenarios) |
| `supplier` | Supplier name when relevant |

### Metrics: Prometheus

The API exposes a `/metrics` endpoint with:

| Metric | Description |
|--------|-------------|
| `grocery_http_request_duration_seconds` | HTTP request latency histogram |
| `grocery_supplier_requests_total` | Supplier API call counter (labels: `rate_limited`, `success`) |
| `grocery_supplier_rate_limit_hits_total` | Count of 429 hits |
| `grocery_supplier_request_count` | Active supplier requests gauge |

### MCP Connectors

| Connector | URL Pattern | Purpose |
|-----------|-------------|---------|
| Grafana MCP | `https://ca-mcp-grafana-<suffix>.icymeadow-96da5d2b.eastus2.azurecontainerapps.io/mcp` | Query Loki + Grafana dashboards |
| Jira MCP | `https://ca-mcp-jira-<suffix>.icymeadow-96da5d2b.eastus2.azurecontainerapps.io/mcp` | Create/update Jira SCRUM incidents |

---

## Fault Injection — Known Scenarios

### Scenario A: Supplier Rate Limiting (429 Storm)

**Trigger:**
```bash
API_URL=$(az containerapp list -g rg-aqsre \
  --query "[?contains(name,'ca-api')].properties.configuration.ingress.fqdn" \
  -o tsv | head -1)
curl -X POST "https://$API_URL/api/demo/trigger-rate-limit"
```

**What happens:**
- API makes 15 rapid calls to FreshFoods Wholesale API
- After `SUPPLIER_RATE_LIMIT` (default: 10), returns 429 with `retryAfter: 60`
- Loki receives 55+ error logs with `errorCode: SUPPLIER_RATE_LIMIT_429`
- Circuit breaker may trip if 429s persist

**Loki signature:**
```logql
{app="grocery-api"} | json | errorCode="SUPPLIER_RATE_LIMIT_429"
```

### Scenario B: OOMKill (Memory Exhaustion)

**Trigger:**
```bash
curl -X POST "https://$API_URL/api/demo/memory-leak?size=100"
```

**What happens:**
- Container memory grows toward its limit
- Azure triggers OOMKill → container restart → HTTP 503 responses
- `RestartCount` metric spikes in Azure Monitor

**Detection:**
```bash
az monitor metrics list --resource <app-resource-id> \
  --metric "RestartCount" --interval PT5M
```

### Scenario C: CPU Stress

**Trigger:**
```bash
curl -X POST "https://$API_URL/api/demo/cpu-stress?duration=300"
```

**What happens:**
- CPU spikes to > 80%, causing request timeouts
- HTTP 503/504 under load

### Scenario D: Circuit Breaker

Circuit breaker auto-trips after sustained supplier failures. No explicit trigger needed.

**Loki signature:**
```logql
{app="grocery-api"} | json | errorCode="CIRCUIT_OPEN"
```

**Recovery:** Circuit breaker auto-resets after the cool-down window. Do not intervene
unless it has not reset after 5+ minutes.

---

## Resource Scaling

| Container App | Min replicas | Max replicas | CPU | Memory |
|--------------|-------------|-------------|-----|--------|
| `ca-api` | 1 | 3 | 0.5 cores | 1.0 Gi |
| `ca-web` | 1 | 2 | 0.25 cores | 0.5 Gi |
| `ca-loki` | 1 | 1 | 0.5 cores | 1.0 Gi |

**Scale out `ca-api`:**
```bash
az containerapp update -g rg-aqsre -n ca-api-<suffix> \
  --min-replicas 2 --max-replicas 5
```

---

## Incident Response — Jira Integration

All SRE Agent investigations create or update tickets in:
- **Project:** SCRUM
- **Board:** `https://aq-r2d2.atlassian.net/jira/software/projects/SCRUM/boards`
- **Issue types:** Bug (incidents), Task (remediation), Story (improvements)

**Priority mapping:**
| Severity | Jira Priority |
|----------|--------------|
| All requests failing | Highest |
| > 50% error rate | High |
| Sustained 429s affecting users | Medium |
| Intermittent / single occurrence | Low |

---

## Source Code

- **Repository:** [github.com/Arturo-Quiroga-MSFT/SRE-AGENT-JAN-2026](https://github.com/Arturo-Quiroga-MSFT/SRE-AGENT-JAN-2026)
- **Language:** Node.js 18
- **Container images:** Built from `grocery-sre-demo/src/api/` and `grocery-sre-demo/src/web/`
- **IaC:** `grocery-sre-demo/infra/` (Bicep, deployed via `azd`)

### Key Files

| File | Purpose |
|------|---------|
| `grocery-sre-demo/src/api/index.js` | Main API — rate limiter, circuit breaker, Loki push, Prometheus metrics |
| `grocery-sre-demo/src/web/server.js` | Static frontend server |
| `grocery-sre-demo/infra/resources.bicep` | Container Apps, Loki, ACR, Grafana, Managed Identity |
| `grocery-sre-demo/infra/mcp-grafana/Dockerfile` | Custom Grafana MCP image (streamable HTTP fix) |
| `grocery-sre-demo/knowledge/loki-queries.md` | LogQL query reference |
| `grocery-sre-demo/knowledge/http-500-errors.md` | HTTP 500 investigation runbook |

---

## Troubleshooting Quick Reference

1. **Health check:** `curl https://<ca-api-url>/health`
2. **Recent errors:** `{app="grocery-api", level="error"}` in Grafana/Loki
3. **Restart count:** `az monitor metrics list --metric RestartCount`
4. **Restart a revision:** `az containerapp revision restart -g rg-aqsre -n <app> --revision <rev>`
5. **Scale out:** `az containerapp update -g rg-aqsre -n <app> --min-replicas 2`
6. **ACR password rotated?** Re-run: `az acr credential show -n <acr-name>` then update secret

---

## Known Operational Quirks

| Issue | Explanation |
|-------|-------------|
| Loki root URL returns 404 | Expected — only `/loki/api/v1/*` paths respond |
| ACR password rotation breaks container apps | Update `registry-password` secret + force new revision |
| Grafana MCP must use custom Dockerfile | Upstream image had SSE transport bug; `Dockerfile.grafana-mcp-streamable` is the fix |
| Agent can't see KB files in portal UI | Known April 2026 platform bug — files still active |

---

*Last updated: April 7, 2026*  
*Adapted from [microsoft/sre-agent starter-lab](https://github.com/microsoft/sre-agent/tree/main/labs/starter-lab/knowledge-base) for Loki/Grafana + Jira observability stack*
