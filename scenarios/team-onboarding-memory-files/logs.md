## Log Sources

### Primary: Loki (via Grafana)
- **Datasource UID:** `bfbkeigsjyebkb`
- **Datasource name:** `loki`
- **Grafana URL:** `https://amg-ps64h2ydsavgc-cvauf6fsdra3c0ed.eus2.grafana.azure.com`
- **Push endpoint:** `https://ca-loki.icymeadow-96da5d2b.eastus2.azurecontainerapps.io`

### Labels

| Label | Values | Notes |
|---|---|---|
| `app` | `grocery-api` | Main app identifier |
| `job` | `grocery-api` | Same as app |
| `level` | `error`, `warn`, `info` | Log severity |
| `environment` | `production` | Always production in this PoC |

### Structured JSON Fields (parsed with `| json`)

| Field | Example | Notes |
|---|---|---|
| `event` | `supplier_rate_limit_exceeded`, `inventory_check_failed`, `rate_limit_demo_complete` | Primary event classifier |
| `errorCode` | `SUPPLIER_RATE_LIMIT_429`, `CIRCUIT_OPEN` | Machine-readable error code |
| `statusCode` | `429` | HTTP status from supplier |
| `productId` | `PROD001`–`PROD008` | Affected product |
| `productName` | `Organic Bananas`, `Whole Milk`, etc. | Human-readable product |
| `supplier` | `FreshFoods Wholesale API` | External dependency name |
| `requestCount` | `6`–`30` | Requests sent in current window |
| `limit` | `5` (was `10`) | Supplier rate limit threshold |
| `retryAfter` | `23`–`60` | Seconds to wait before retry |
| `duration` | `975`–`2765` (ms) | Request duration (warn events) |

### First Queries

**Errors last hour:**
```logql
{app="grocery-api", level="error"} |= "429"
```

**Error count (instant):**
```logql
count_over_time({app="grocery-api"} |= "429" [1h])
```

**Breakdown by event type:**
```logql
sum by (event) (count_over_time({app="grocery-api", level="error"} | json [1h]))
```

**Error by errorCode (bar chart):**
```logql
sum by (errorCode) (count_over_time({app="grocery-api", level="error"} | json [1h]))
```

**Warnings (slow responses, latency):**
```logql
{app="grocery-api", level="warn"}
```

**All logs for baseline:**
```logql
{app="grocery-api"}
```

**Rate over time (5m buckets):**
```logql
rate({app="grocery-api", level="error"} [$__interval])
```

### Correlation

- No distributed tracing / `operation_Id` — single-service demo app
- Correlate by `productId` across `supplier_rate_limit_exceeded` and `inventory_check_failed` events
- Correlate by timestamp — errors cluster in bursts (same `retryAfter` window)

### AKS Testbed Logs (Log Analytics / KQL)

For the AKS private testbed, logs go to Log Analytics (not Loki):

**Key tables:** `KubePodInventory`, `ContainerLog`, `Perf`

**Pod restart count:**
```kusto
KubePodInventory
| where Namespace == "grocery"
| where isnotempty(PodRestartCount)
| summarize MaxRestarts = max(toint(PodRestartCount)) by Name, Namespace
```

**Gotcha:** Column is `PodRestartCount` (not `RestartCount`), pod name column is `Name` (not `PodName`).

### Known Pitfall

When querying Loki, **always use** `{app="grocery-api"}` — NOT `{container_app="ca-api-ps64h2ydsavgc"}`. The container app name is not a Loki label.
