# HTTP 500 Error Investigation Runbook

## Trigger Keywords

`500 error`, `internal server error`, `HTTP 500`, `server error`, `application error`,
`unresponsive`, `5xx`, `service unavailable`, `503`, `502`

## Scope

Azure Container Apps endpoints returning HTTP 5xx errors. Logs stored in **Loki**
(queried via Grafana MCP). Metrics exposed via Prometheus (`/metrics` endpoint) and
collectible via Azure CLI.

---

## Valid Azure Monitor Metric Names for Container Apps

**IMPORTANT: Use ONLY these metric names with `az monitor metrics list`:**

- `UsageNanoCores` — CPU usage (NOT CpuUsage, NOT CPUUsage)
- `WorkingSetBytes` — Memory usage (NOT MemoryUsage, NOT MemoryWorkingSet)
- `Requests` — HTTP request count
- `RestartCount` — Container restarts (OOM indicator)
- `Replicas` — Active replica count
- `CpuPercentage` — CPU percentage
- `MemoryPercentage` — Memory percentage

## Container App Logs CLI

**Use `az containerapp logs show` with `--tail` (NOT `--since`):**

```bash
az containerapp logs show -g rg-aqsre -n ca-api-<suffix> --tail 300
az containerapp logs show -g rg-aqsre -n ca-api-<suffix> --tail 300 --format text
```

---

## Phase 1: CPU and Memory Metrics (Check First)

### 1.1 CPU and Memory via Azure CLI

```bash
# Get container app resource ID
APP_ID=$(az containerapp show -g rg-aqsre -n ca-api-<suffix> --query id -o tsv)

# CPU usage last hour
az monitor metrics list --resource $APP_ID --metric "UsageNanoCores" --interval PT5M

# Memory usage last hour
az monitor metrics list --resource $APP_ID --metric "WorkingSetBytes" --interval PT5M

# Restart count (OOM indicator)
az monitor metrics list --resource $APP_ID --metric "RestartCount" --interval PT5M
```

### 1.2 Memory Pressure — Check Loki for OOMKill Signals

```logql
# OOM or memory pressure signals
{app="grocery-api"} |= "OOM"

# Container restart signals
{app="grocery-api"} |= "restart"

# Any memory-related warning or error
{app="grocery-api", level=~"warn|error"} |= "memory"
```

### Resource Thresholds Reference

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| CPU % | > 70% sustained | > 90% sustained | Scale out replicas |
| Memory % | > 75% sustained | > 90% sustained | Scale up or fix leak |
| RestartCount | > 2 in 30 min | > 5 in 30 min | Investigate OOMKill |

---

## Phase 2: Initial Triage

### 2.1 Get Container App Status

```bash
# Show full container app state
az containerapp show -g rg-aqsre -n ca-api-<suffix> -o json

# List revisions and their traffic weights
az containerapp revision list -g rg-aqsre -n ca-api-<suffix> -o table

# Show recent logs (last 300 lines)
az containerapp logs show -g rg-aqsre -n ca-api-<suffix> --tail 300
```

### 2.2 Quick Error Count via Loki

```logql
# All errors in last hour
count_over_time({app="grocery-api", level="error"}[1h])

# Error rate per 5-minute window
rate({app="grocery-api", level="error"}[5m])

# Errors grouped by error code
sum by (errorCode) (count_over_time({app="grocery-api"} | json [1h]))
```

---

## Phase 3: Identify Error Patterns

### 3.1 Top Error Messages

```logql
# All error logs in last hour
{app="grocery-api", level="error"} | json

# Specific 500 errors
{app="grocery-api"} |= "500"

# Errors with structured fields
{app="grocery-api", level="error"} | json | line_format "{{.errorCode}}: {{.message}}"
```

### 3.2 Error Rate Over Time

```logql
# Error count per 5-minute bucket
sum(count_over_time({app="grocery-api", level="error"}[5m]))

# Ratio of errors to total requests
sum(rate({app="grocery-api", level="error"}[5m])) /
sum(rate({app="grocery-api"}[5m]))
```

### 3.3 Known Error Codes in This App

| Error Code | Meaning | Phase to check |
|-----------|---------|---------------|
| `SUPPLIER_RATE_LIMIT_429` | FreshFoods API rate limit hit | Phase 5 |
| `CIRCUIT_OPEN` | Circuit breaker tripped — downstream failure | Phase 5 |
| `CHECKOUT_FAILED` | Order processing failure | Phase 4 |
| *(no errorCode, statusCode=500)* | Internal server error | Phase 4 |
| *(no errorCode, statusCode=503)* | Service unavailable / OOM restart | Phase 6 |

---

## Phase 4: Application Error Details

### 4.1 Structured Log Deep Dive

```logql
# Full structured error details
{app="grocery-api", level="error"} | json
| line_format "{{.time}} [{{.errorCode}}] {{.message}} status={{.statusCode}}"

# Errors with statusCode 500
{app="grocery-api"} | json | statusCode=`500`

# Errors with supplier context
{app="grocery-api", level="error"} | json | supplier != ""
```

### 4.2 Error Timeline

```logql
# First and last occurrence of each errorCode
{app="grocery-api", level="error"} | json | errorCode != ""
```

---

## Phase 5: Dependency Health (Supplier API / Circuit Breaker)

This app calls the FreshFoods Wholesale API for inventory. If that external call fails
or is rate limited, the grocery-api returns 500/429.

### 5.1 Supplier Rate Limit Errors

```logql
# Rate limit errors
{app="grocery-api"} |= "429"

# With full detail
{app="grocery-api"} | json | errorCode="SUPPLIER_RATE_LIMIT_429"

# Count over time
count_over_time({app="grocery-api"} |= "429" [1h])
```

### 5.2 Circuit Breaker Events

```logql
# Circuit breaker open
{app="grocery-api"} | json | errorCode="CIRCUIT_OPEN"

# Circuit breaker state changes
{app="grocery-api"} |= "circuit"
```

### 5.3 Dependency Decision Tree

```
Supplier API returning 429?
  YES → Check retryAfter field → implement backoff → create Jira P2 incident
  NO  → Check circuit breaker → confirm downstream is actually down → wait for auto-reset
        → If not auto-resetting → manual intervention may be needed
```

---

## Phase 6: Container Health (OOMKill / Restarts)

### 6.1 Restart Signals in Loki

```logql
# Any restart-related log
{app="grocery-api"} |= "restart"

# Memory warning signs
{app="grocery-api", level="warn"} | json
```

### 6.2 Restart Check via Azure CLI

```bash
# Check restart count metric
az monitor metrics list \
  --resource $(az containerapp show -g rg-aqsre -n ca-api-<suffix> --query id -o tsv) \
  --metric "RestartCount" \
  --interval PT5M

# Check container environment health
az containerapp env show -g rg-aqsre -n cae-<suffix>
```

### 6.3 Scale to Recover from OOMKill

```bash
# Increase memory limit
az containerapp update -g rg-aqsre -n ca-api-<suffix> --memory 1.0Gi

# Scale out replicas
az containerapp update -g rg-aqsre -n ca-api-<suffix> --min-replicas 2 --max-replicas 5
```

---

## Phase 7: Deployment Correlation

### 7.1 Check Recent Revision Changes

```bash
# List revisions with timestamps
az containerapp revision list -g rg-aqsre -n ca-api-<suffix> \
  --query "[].{name:name,created:properties.createdTime,active:properties.active,traffic:properties.trafficWeight}" \
  -o table

# Restart a specific revision
az containerapp revision restart -g rg-aqsre -n ca-api-<suffix> --revision <rev-name>
```

### 7.2 Correlate Errors with Deployment Time in Loki

```logql
# Errors since a specific time (adjust timestamp)
{app="grocery-api", level="error"} | json
```

*(Filter by timestamp in Grafana time picker to narrow to post-deployment window)*

---

## Phase 8: Remediation Actions

| Root Cause | Immediate Action | Command |
|-----------|-----------------|---------|
| Supplier rate limit (429) | Implement backoff; create Jira incident | See Phase 5 |
| OOMKill | Scale up memory or out replicas | See Phase 6.3 |
| Circuit breaker open | Confirm downstream health; wait for auto-reset | See Phase 5.3 |
| Bad deployment | Rollback to previous revision | `az containerapp revision restart` |
| Container crash loop | Check logs, then restart | `az containerapp logs show` |

---

## Quick Diagnosis Checklist

| Check | Query / Command | What to Look For |
|-------|----------------|-----------------|
| Error rate | `count_over_time({app="grocery-api", level="error"}[1h])` | Spike or sustained high rate |
| Error codes | `{app="grocery-api"} \| json \| errorCode != ""` | Known codes → known runbook |
| Restarts | `az monitor metrics list --metric RestartCount` | > 2 restarts in 30 min |
| Supplier 429 | `{app="grocery-api"} \|= "429"` | Rate limit in effect |
| Circuit open | `{app="grocery-api"} \| json \| errorCode="CIRCUIT_OPEN"` | Downstream failure |
| Deployments | `az containerapp revision list` | Recent revision = rollback candidate |

---

## Escalation Criteria

Escalate (create Jira P1) immediately if:
- Error rate > 50% for 5+ minutes
- All requests failing (100% error rate)
- OOMKill happening repeatedly (RestartCount > 5 in 30 min)
- Both rate limit AND circuit breaker active simultaneously
- Multiple container apps affected

---

*Last updated: April 7, 2026*  
*Adapted from [microsoft/sre-agent starter-lab](https://github.com/microsoft/sre-agent/tree/main/labs/starter-lab/knowledge-base) for Loki/Grafana observability stack*
