# Scenario: Rate Limit Incident Response

## Overview
External supplier API starts rate limiting requests, causing product inventory checks to fail. This scenario demonstrates how SRE Agent can automatically detect, diagnose, and triage rate limit issues.

## Symptoms
- Users see "Unable to check inventory" errors
- 429 HTTP status codes in logs
- Increased error rate on product catalog endpoints
- Supplier API returning `Retry-After` headers

## How to Trigger (Demo Environment)

### Option 1: API Endpoint
```bash
# Get your API URL
API_URL=$(az containerapp list -g $RG --query "[?contains(name,'api')].properties.configuration.ingress.fqdn" -o tsv | head -1)

# Trigger rate limit scenario
curl -X POST "https://$API_URL/api/demo/trigger-rate-limit"

# Expected response:
# {
#   "message": "Rate limit scenario triggered",
#   "requestsMade": 15,
#   "errorsEncountered": 10
# }
```

### Option 2: Web UI
```bash
# Get web app URL
WEB_URL=$(az containerapp list -g $RG --query "[?contains(name,'web')].properties.configuration.ingress.fqdn" -o tsv | head -1)

echo "Open: https://$WEB_URL"
# Click "Trigger Rate Limit (Demo)" button
```

### Option 3: Simulate Real Traffic
```bash
# Make rapid successive requests to trigger rate limiting
for i in {1..20}; do
  curl "https://$API_URL/api/products" &
done
wait
```

## Expected Log Patterns in Loki

### Error Logs
```logql
# Rate limit errors
{app="grocery-api", level="error"} |= "429"

# Detailed view with JSON parsing
{app="grocery-api"} | json | errorCode="SUPPLIER_RATE_LIMIT_429"
```

### Sample Log Entry
```json
{
  "timestamp": "2026-01-26T10:45:23.123Z",
  "level": "error",
  "app": "grocery-api",
  "event": "supplier_rate_limited",
  "errorCode": "SUPPLIER_RATE_LIMIT_429",
  "message": "FreshFoods Wholesale API rate limit exceeded",
  "statusCode": 429,
  "retryAfter": 60,
  "endpoint": "/api/inventory/check",
  "supplier": "FreshFoods Wholesale"
}
```

## SRE Agent Investigation Flow

### Step 1: Initial Prompt
```
@DiagnosticExpert: My container app ca-api-xxxxx in resource group rg-sre-poc-partner is experiencing rate limit errors from a supplier API when checking product inventory. Can you investigate?
```

### Step 2: Agent Actions (Total: 5-8 minutes)
1. ✅ Reads `loki-queries.md` knowledge file (~5 seconds)
2. ✅ Queries Loki via Grafana MCP (~10-15 seconds):
   ```logql
   {app="grocery-api", level="error"} |= "429"
   ```
3. ✅ Analyzes error frequency (~10 seconds):
   ```logql
   count_over_time({app="grocery-api"} |= "429" [1h])
   ```
4. ✅ Extracts error details (errorCode, retryAfter, supplier) (~5 seconds)
5. ✅ Identifies pattern: 55+ rate limit errors in past hour (~10 seconds)

**Performance Metrics:**
- Total response time: 5-8 minutes
- Number of tool calls: 2-3
- Estimated token usage: 3,000-5,000 tokens
  - Input tokens (context): ~2,000
  - Output tokens (analysis + ticket): ~1,500-3,000

### Step 3: Root Cause Analysis (~30 seconds of agent processing)
- **Issue:** External supplier API (FreshFoods Wholesale) rate limiting
- **Limit:** 5 requests per 60 seconds
- **Affected Endpoint:** `/api/inventory/check`
- **Impact:** Product inventory unavailable to customers
- **Timeline:** Started at ~10:42 AM UTC
- **Analysis time:** Agent processes ~500 log entries in ~30 seconds
 (~30-45 seconds)
Agent creates Jira ticket with:

**Time breakdown:**
- Ticket composition: ~20 seconds
- Jira API call via MCP: ~10-25 seconds
Agent creates Jira ticket with:

**Summary:** Rate limit errors on grocery-api from FreshFoods Supplier API

**Description:**
```
Root Cause Analysis
===================
The grocery-api service is experiencing significant rate limiting from the 
FreshFoods Wholesale API when checking product inventory.

Timeline
--------
- Issue started: 2026-01-26 10:42 UTC
- Error count: 55+ occurrences in past hour
- Error code: SUPPLIER_RATE_LIMIT_429

Evidence
--------
Loki query: {app="grocery-api"} | json | errorCode="SUPPLIER_RATE_LIMIT_429"

Sample error:
{
  "event": "supplier_rate_limited",
  "statusCode": 429,
  "retryAfter": 60,
  "supplier": "FreshFoods Wholesale"
}

Impact
------
- Users cannot view product inventory
- Checkout flow affected for products from FreshFoods
- Degraded user experience

Remediation Steps
-----------------
1. **Immediate:**
   - Implement exponential backoff with retry logic
   - Cache inventory data for 30-60 seconds

2. **Short-term:**
   - Contact FreshFoods to increase rate limit
   - Add rate limit monitoring/alerting

3. **Long-term:**
   - Implement request batching for inventory checks
   - Add circuit breaker pattern for external APIs
   - Consider alternative suppliers with higher limits

References
----------
- Grafana dashboard: [link]
- Container App logs: [link]
- SRE Agent investigation: [link]
```

**Priority:** High  
**Labels:** `incident`, `automated`, `rate-limit`, `external-api`  
**Components:** `grocery-api`, `supplier-integration`  
**Assignee:** On-call engineer

## Metrics to Monitor

### During Incident
```promql
# Error rate
rate(http_requests_total{status="429"}[5m])

# Request latency (may spike during retries)
histogram_quantile(0.95, http_request_duration_seconds_bucket)

# External API health
up{job="supplier-api"}
```

### Post-Remediation
- Monitor for recurrence
- Track implementation of exponential backoff
- Verify caching reduces supplier API calls

## Prevention Measures

### Code Changes
```javascript
// Before: Direct API calls without rate limit handling
async function checkInventory(productId) {
  return await supplierAPI.get(`/inventory/${productId}`);
}

// After: Exponential backoff with caching
async function checkInventory(productId) {
  // Check cache first
  const cached = await cache.get(`inventory:${productId}`);
  if (cached) return cached;
  
  // Call with retry logic
  const inventory = await retryWithBackoff(
    () => supplierAPI.get(`/inventory/${productId}`),
    { maxRetries: 3, baseDelay: 1000 }
  );
  
  // Cache for 60 seconds
  await cache.set(`inventory:${productId}`, inventory, 60);
  return inventory;
}
```

### Monitoring Setup
```yaml
# Alert rule for rate limiting
- alert: SupplierAPIRateLimit
  expr: |
    sum(rate(http_requests_total{status="429"}[5m])) > 0.1
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Supplier API rate limiting detected"
```

## Related Scenarios
- [Service Degradation](service-degradation.md) - Similar investigation flow for 5xx errors
- External API Timeout - When supplier API becomes unresponsive
- Circuit Breaker Activation - Automatic failover when external dependencies fail

## References
- [Azure SRE Agent Documentation](https://learn.microsoft.com/en-us/azure/sre-agent/overview)
- [Loki Query Reference](../grocery-sre-demo/knowledge/loki-queries.md)
- Rate Limiting Best Practices: https://learn.microsoft.com/azure/architecture/patterns/throttling
