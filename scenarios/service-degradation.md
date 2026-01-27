# Scenario: Service Degradation Detection

## Overview
Application experiences increasing response times and intermittent 5xx errors due to resource constraints or downstream dependency issues. This scenario demonstrates how SRE Agent can detect degradation early and recommend remediation.

## Symptoms
- Increased response latency (P95 > 2 seconds)
- Intermittent 500, 502, 503, or 504 errors
- High CPU or memory utilization
- Database connection pool exhaustion
- Downstream service timeouts

## How to Trigger (Demo Environment)

### Option 1: CPU Stress Test
```bash
# Get API container app name
API_NAME=$(az containerapp list -g $RG --query "[?contains(name,'api')].name" -o tsv | head -1)

# Add CPU stress endpoint (if not already implemented)
API_URL=$(az containerapp show --name $API_NAME -g $RG --query "properties.configuration.ingress.fqdn" -o tsv)

# Trigger CPU load
curl -X POST "https://$API_URL/api/demo/cpu-stress?duration=300"
```

### Option 2: Memory Leak Simulation
```bash
# Simulate memory leak
curl -X POST "https://$API_URL/api/demo/memory-leak?size=100"
```

### Option 3: Database Connection Exhaustion
```bash
# Open many connections without closing
for i in {1..50}; do
  curl -X GET "https://$API_URL/api/products?slow=true" &
done
```

### Option 4: Load Testing
```bash
# Install hey (HTTP load generator)
# macOS: brew install hey
# Linux: download from https://github.com/rakyll/hey

# Send sustained load
hey -z 5m -c 50 "https://$API_URL/api/products"
```

## Expected Log Patterns in Loki

### Warning Signs (Early Detection)
```logql
# Slow response times
{app="grocery-api", level="warn"} |= "slow response"

# High duration queries
{app="grocery-api"} | json | duration > 2000

# Resource warnings
{app="grocery-api", level="warn"} |= "memory" or "cpu"
```

### Error Patterns
```logql
# 5xx server errors
{app="grocery-api", level="error"} |= "500" or "502" or "503" or "504"

# Timeout errors
{app="grocery-api", level="error"} |= "timeout" or "ETIMEDOUT"

# Resource exhaustion
{app="grocery-api", level="error"} |= "ENOMEM" or "out of memory"
```

### Sample Log Entries
```json
// Warning - Slow response
{
  "timestamp": "2026-01-26T11:15:23.456Z",
  "level": "warn",
  "event": "slow_response",
  "message": "Request took longer than expected",
  "duration": 2345,
  "endpoint": "/api/products",
  "threshold": 1000
}

// Error - Service unavailable
{
  "timestamp": "2026-01-26T11:16:45.789Z",
  "level": "error",
  "event": "service_error",
  "errorCode": "SERVICE_UNAVAILABLE",
  "message": "Downstream service unavailable",
  "statusCode": 503,
  "service": "database",
  "retries": 3
}
```

## SRE Agent Investigation Flow

### Step 1: Initial Prompt
```
@DiagnosticExpert: Users are reporting slow page loads and intermittent errors on the product catalog. Can you investigate the container app's health and performance?
```

### Step 2: Agent Actions (Total: 7-12 minutes)
1. ✅ Checks recent errors in Loki (~15-20 seconds):
   ```logql
   {app="grocery-api", level=~"warn|error"} [1h]
   ```
2. ✅ Analyzes error trends (~20 seconds):
   ```logql
   sum by (statusCode) (count_over_time({app="grocery-api"} | json [1h]))
   ```
3. ✅ Reviews resource metrics from Azure Monitor (~30-45 seconds)
4. ✅ Checks application logs for patterns (~20-30 seconds)
5. ✅ Identifies correlation between high load and errors (~40 seconds)

**Performance Metrics:**
- Total response time: 7-12 minutes (more complex than rate limit scenario)
- Number of tool calls: 4-6 (multiple data sources)
- Estimated token usage: 5,000-8,000 tokens
  - Input tokens (context + logs): ~3,000
  - Output tokens (comprehensive analysis): ~2,000-5,000
- Log entries analyzed: ~1,000-1,500

### Step 3: Root Cause Analysis Options

#### Scenario A: Resource Exhaustion
- **Issue:** Container CPU/Memory reaching limits
- **Evidence:** High utilization metrics + OOM errors in logs
- **Solution:** Scale up resources or scale out replicas

#### Scenario B: Database Connection Pool
- **Issue:** Connection pool exhausted under load
- **Evidence:** "connection timeout" or "pool exhausted" in logs
- **Solution:** Increase pool size or optimize queries

#### Scenario C: Downstream Dependency
- **Issue:** External service degradation causing cascading failures
- **Evidence:** Timeouts when calling specific service
- **Solution:** Implement circuit breaker, increase timeouts

### Step 4: Ticket Creation
Agent creates Jira ticket with:

**Summary:** Service degradation on grocery-api - Slow responses and 5xx errors

**Description:**
```
Root Cause Analysis
===================
The grocery-api service is experiencing performance degradation with increased 
response times and intermittent 5xx errors.

Timeline
--------
- Degradation started: 2026-01-26 11:12 UTC
- Warning logs: 127 instances in past hour
- Error logs: 43 instances in past hour
- P95 latency: 2.4s (normal: 350ms)

Evidence from Logs
------------------
Query: {app="grocery-api", level=~"warn|error"} [1h]

Pattern identified:
- 89 slow response warnings (duration > 2s)
- 38 "service unavailable" errors (503)
- 5 "out of memory" warnings

Metrics Analysis
----------------
- CPU: 85% (up from normal 30%)
- Memory: 720MB / 1GB (72% utilization)
- Active requests: 45 (normal: 5-10)
- Database connections: 48/50 (96% pool utilization)

Root Cause
----------
Database connection pool exhaustion under sustained load. The service is 
configured with only 50 max connections, and long-running queries are 
holding connections open, starving new requests.

Impact
------
- Slow page loads for product catalog
- ~8% of requests failing with 503 errors
- User experience significantly degraded
- Potential revenue impact

Immediate Mitigation
--------------------
1. Scale Container App to 3 replicas (currently 1):
   ```bash
   az containerapp update --name ca-api-xxxxx \
     --resource-group rg-sre-poc-partner \
     --min-replicas 3
   ```

2. Increase database connection pool:
   ```bash
   az containerapp update --name ca-api-xxxxx \
     --resource-group rg-sre-poc-partner \
     --set-env-vars "DB_POOL_SIZE=100"
   ```

3. Restart service to apply changes

Short-term Remediation
----------------------
1. Optimize slow database queries identified:
   - `SELECT * FROM products` (full table scan)
   - Add indexes on frequently queried columns

2. Implement connection pooling best practices:
   - Set connection timeout to 5s
   - Implement query timeout (10s)
   - Add connection pool monitoring

3. Add autoscaling rules:
   - Scale up when CPU > 70% for 5 minutes
   - Scale up when memory > 80%
   - Scale up when HTTP queue length > 100

Long-term Prevention
--------------------
1. Implement load testing in CI/CD pipeline
2. Add comprehensive monitoring and alerting:
   - P95 latency alerts
   - Connection pool utilization alerts
   - Error rate threshold alerts

3. Consider caching layer for product catalog
4. Implement circuit breaker for database calls
5. Add rate limiting to protect against traffic spikes

References
----------
- Grafana dashboard: [link]
- Container App metrics: [link]
- Database performance insights: [link]
```

**Priority:** Critical  
**Labels:** `incident`, `automated`, `performance`, `production-impact`  
**Components:** `grocery-api`, `database`  
**Assignee:** On-call engineer

## Metrics to Monitor

### Key Performance Indicators
```promql
# Request latency percentiles
histogram_quantile(0.95, http_request_duration_seconds_bucket)
histogram_quantile(0.99, http_request_duration_seconds_bucket)

# Error rates
rate(http_requests_total{status=~"5.."}[5m])

# Throughput
rate(http_requests_total[5m])

# Resource utilization
container_cpu_usage_seconds_total
container_memory_working_set_bytes
```

### Loki Queries for Trends
```logql
# Error rate over time
sum(count_over_time({app="grocery-api", level="error"}[5m]))

# Slow request trend
sum(count_over_time({app="grocery-api"} | json | duration > 2000 [5m]))

# Top error codes
topk(5, sum by (statusCode) (count_over_time({app="grocery-api"} | json [1h])))
```

## Prevention Measures

### Autoscaling Configuration
```bash
# Configure autoscaling rules
az containerapp update \
  --name ca-api-xxxxx \
  --resource-group rg-sre-poc-partner \
  --min-replicas 2 \
  --max-replicas 10 \
  --scale-rule-name cpu-scaling \
  --scale-rule-type cpu \
  --scale-rule-metadata "type=Utilization" "value=70"

az containerapp update \
  --name ca-api-xxxxx \
  --resource-group rg-sre-poc-partner \
  --scale-rule-name http-scaling \
  --scale-rule-type http \
  --scale-rule-metadata "concurrentRequests=50"
```

### Alert Rules
```yaml
# Critical degradation alert
- alert: ServiceDegradation
  expr: |
    (
      histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 2
      AND
      rate(http_requests_total{status=~"5.."}[5m]) > 0.05
    )
  for: 10m
  labels:
    severity: critical
  annotations:
    summary: "Service degradation detected - high latency and errors"

# Resource exhaustion warning
- alert: HighResourceUsage
  expr: |
    (
      container_cpu_usage_seconds_total > 0.8
      OR
      container_memory_working_set_bytes / container_spec_memory_limit_bytes > 0.8
    )
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "High resource utilization detected"
```

### Code Improvements
```javascript
// Add connection pool monitoring
const pool = new Pool({
  max: 50,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000
});

pool.on('error', (err) => {
  logger.error('Database pool error', { error: err.message });
});

// Monitor pool metrics
setInterval(() => {
  logger.info('Connection pool stats', {
    total: pool.totalCount,
    idle: pool.idleCount,
    waiting: pool.waitingCount
  });
}, 60000);

// Add query timeout
const result = await pool.query({
  text: 'SELECT * FROM products WHERE category = $1',
  values: [category],
  timeout: 10000  // 10 second timeout
});
```

## Related Scenarios
- [Rate Limit Incident](rate-limit-incident.md) - Similar investigation flow
- Database Failover - When primary database becomes unavailable
- DDoS Attack Response - Traffic spike causing service unavailability

## References
- [Azure Container Apps Scaling](https://learn.microsoft.com/azure/container-apps/scale-app)
- [Performance Troubleshooting](https://learn.microsoft.com/azure/architecture/antipatterns/)
- [SRE Best Practices](https://learn.microsoft.com/azure/architecture/framework/devops/overview)
