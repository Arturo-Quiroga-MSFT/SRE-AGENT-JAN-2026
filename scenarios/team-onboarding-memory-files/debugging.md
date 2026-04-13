## Debugging & Runbooks

### Issue 1: Supplier Rate Limiting (429) — MOST COMMON

**Symptoms:** Users see "Unable to check inventory", Loki shows `SUPPLIER_RATE_LIMIT_429` errors

**Runbook:**
1. Query Loki: `{app="grocery-api", level="error"} |= "429"` (last 1h)
2. Count errors: `count_over_time({app="grocery-api"} |= "429" [1h])`
3. Check breakdown: `sum by (event) (count_over_time({app="grocery-api", level="error"} | json [1h]))`
4. Check current rate limit config: `az containerapp show -g rg-aqsre -n ca-api-ps64h2ydsavgc --query "properties.template.containers[0].env"`
5. If count > 20 → Create Jira ticket with RCA
6. **Immediate fix:** Increase `SUPPLIER_RATE_LIMIT` env var or implement backoff

**Root cause pattern:** App sends 8 parallel per-product calls per batch. With limit=5, it overshoots by up to 6x. No client-side throttling, no circuit breaker, no retry-after honoring.

**Past incidents:**
- 2026-03-18: limit=10, requestCount up to 25 (2.5x overshoot), 44 errors
- 2026-04-01: limit changed to 5 via config update, requestCount up to 49
- 2026-04-06: limit=5, requestCount up to 30 (6x overshoot), 25 errors

**Corrective actions still open:** Client-side rate limiter, circuit breaker, response caching, batch API calls, retry-after honoring, Prometheus metrics

---

### Issue 2: Jira MCP Auth Failure — RECURRING

**Symptoms:** `jira_create_issue` returns "Invalid user Jira token or configuration"

**Runbook:**
1. Check Jira MCP container health: `az containerapp show -g rg-aqsre -n ca-mcp-jira`
2. Check container logs: `az containerapp logs show -g rg-aqsre -n ca-mcp-jira --tail 20`
3. Verify Jira API token is valid at `https://aq-r2d2.atlassian.net`
4. Generate new token at `https://id.atlassian.com/manage-profile/security/api-tokens`
5. Update container env var: `az containerapp update -g rg-aqsre -n ca-mcp-jira --set-env-vars "JIRA_API_TOKEN=<new-token>"`

---

### Issue 3: MCP Connector 405 Method Not Allowed

**Symptoms:** Connector validation fails in Azure portal with 405

**Root cause:** MCP server is in SSE mode, not Streamable-HTTP

**Fix:** Rebuild custom image with Streamable-HTTP:
```dockerfile
FROM grafana/mcp-grafana:latest
ENTRYPOINT ["/app/mcp-grafana","-t","streamable-http","--address","0.0.0.0:8000","--endpoint-path","/mcp"]
```
Build: `az acr build --registry crps64h2ydsavgc --image grafana-mcp-streamable:latest --file Dockerfile.grafana-mcp-streamable .`

---

### Issue 4: Container App Can't Pull Image from ACR

**Fix:** `az containerapp registry set --name <app> --resource-group rg-aqsre --server crps64h2ydsavgc.azurecr.io --identity system`

---

### Issue 5: azd up Fails (npm ci error)

**Symptoms:** `npm error code EUSAGE` — missing `package-lock.json`

**Fix:** Generate lock files first: `cd src/api && npm install && cd ../web && npm install`, then commit them.

---

### Issue 6: Knowledge Base Files Not Visible in UI

**Status:** Known platform bug (April 2026). Files are still active and used by the agent. Raise Azure support ticket.

---

### Issue 7: Repository Connector Stays "Pending"

**Status:** Known indexing issue (April 2026). Workaround: use MCP server alternative.

---

### AKS Private Cluster — Common Gotchas

| Issue | Fix |
|---|---|
| `az aks command invoke` file path error | Use basename only in `--command`, not `/mnt/` prefix |
| `kubectl rollout status` fails via command invoke | Streaming commands not supported — use `kubectl get` with sleep |
| `az aks command invoke` returns exit code 1 falsely | Always use `--output json` and parse with Python |
| KQL `RestartCount` column not found | Correct column is `PodRestartCount` in `KubePodInventory` |
| KQL `PodName` column not found | Correct column is `Name` in `KubePodInventory` |
| Multi-period alert validation fails | Must include `bin(TimeGenerated, 5m)` in KQL aggregation |

### DiagnosticExpert Investigation Workflow

1. **COLLECT** — Query Loki for errors, warnings, and baseline
2. **CLASSIFY** — Fault domain: INFRA / APP / MIXED (with confidence)
3. **ANALYZE** — Structured output: Summary, Timeline, RCA, Mitigations, What to Monitor, Evidence Links
4. **TICKET** — Create Jira ticket with full structured analysis
