## Dashboards

### Grafana

| Dashboard | UID | URL | Notes |
|---|---|---|---|
| SRE Troubleshooting Cockpit | `sre-cockpit-v1` | [Open](https://amg-ps64h2ydsavgc-cvauf6fsdra3c0ed.eus2.grafana.azure.com/d/sre-cockpit-v1) | Main operational dashboard |
| Grafana Explore (Loki) | — | [Open](https://amg-ps64h2ydsavgc-cvauf6fsdra3c0ed.eus2.grafana.azure.com/explore?left=%7B%22datasource%22%3A%22bfbkeigsjyebkb%22%7D) | Ad-hoc log queries |

### SRE Troubleshooting Cockpit Panels

| Panel | Type | Query |
|---|---|---|
| Error Rate (per 5 min) | Time series | `rate({app="$service", level="error"} [$__interval])` |
| Warning Rate (per 5 min) | Time series | `rate({app="$service", level="warn"} [$__interval])` |
| Error Count by Error Code (1h) | Bar chart | `sum by (errorCode) (count_over_time({app="$service", level="error"} \| json [1h]))` |
| Errors vs Warnings vs Info (1h) | Pie chart | `count_over_time({app="$service", level="error/warn/info"} [1h])` |
| Recent Error Logs | Logs panel | `{app="$service", level="error"}` |
| Rate Limit (429) Events Over Time | Time series | `count_over_time({app="$service"} \|= "429" [5m])` |

**Variables:** `$service` (default: `grocery-api`), `$datasource` (Loki UID)

### Grafana Alert Rules

| Rule | UID | Folder | Condition | State |
|---|---|---|---|---|
| Grocery API - Rate Limit 429 Errors Detected | `bfge66fq0yjnkf` | `sre-alerts` | >5 errors in 5 min window | Pending/Firing |

**Labels:** `severity=high`, `service=grocery-api`, `error_type=rate_limit_429`, `team=sre`

### Access

- **Grafana:** SSO via Entra ID (Azure AD)
- **Grafana Service Account Token:** Non-expiring, used by MCP server
- **Azure Portal dashboard:** `198f0a43-f1a5-4a49-bda5-41c925456771-dashboard` in `aq-foundry-rg`
