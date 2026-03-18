# Root Cause Analysis (RCA) Report

---

## 1. Incident Header

| Field | Value |
|---|---|
| **Incident ID** | RCA-GROCERY-429-20260318 |
| **Severity** | High |
| **Status** | Investigating |
| **Duration** | 2026-03-18 13:10 UTC — Ongoing |
| **Impacted Services** | `grocery-api` (production) |
| **Impacted Supplier** | FreshFoods Wholesale API |
| **Impacted Customers** | All grocery-web users attempting inventory checks or product availability lookups |

---

## 2. Executive Summary

The `grocery-api` production service is experiencing widespread HTTP 429 (Too Many Requests) errors when calling the FreshFoods Wholesale API for inventory checks. The application is sending 11–25 requests per rate-limit window against a supplier-imposed limit of 10, causing all inventory lookups across 8 product categories to intermittently fail. Customers using the grocery-web frontend are unable to view real-time product availability, degrading the shopping experience.

---

## 3. Timeline

| Time (UTC) | Event | Source |
|---|---|---|
| 13:10:39 | First `inventory_check_failed` error detected (PROD004 — Free-Range Eggs) | Loki logs (`{app="grocery-api"}`) |
| 13:10:39 | First `supplier_rate_limit_exceeded` event (PROD001 — 19 req vs limit of 10) | Loki logs |
| 13:10:39 – 13:11:34 | Sustained burst of 44 rate-limit errors across 8 products | Loki logs (count_over_time) |
| 13:11:34 | Most recent error observed (PROD003 — Sourdough Bread) | Loki logs |
| 13:20:00 | SRE Agent investigation initiated | SRE Agent |
| — | **No Grafana alert fired** (no alert rules configured for 429 errors) | Grafana alert rules (empty) |
| — | **No Grafana incident created** (no active incidents found) | Grafana incidents |

---

## 4. Root Cause

### Technical Root Cause

The `grocery-api` service is exceeding the **FreshFoods Wholesale API** rate limit. The supplier enforces a limit of **10 requests per rate-limit window**, but the application is sending between **11 and 25 requests** per window — up to **2.5x the allowed threshold**.

**Evidence from logs:**

| Metric | Value |
|---|---|
| Error code | `SUPPLIER_RATE_LIMIT_429` |
| Supplier rate limit | 10 requests/window |
| Observed request counts | 11, 12, 13, 14, 16, 17, 18, 19, 20, 22, 24, 25 |
| Retry-After headers | 30–60 seconds |
| Total 429 errors (last 1h) | **44** |
| Affected products | 8 (all products in catalog) |

**Two distinct error event types observed:**

1. **`supplier_rate_limit_exceeded`** — Direct rate-limit rejection from FreshFoods API (includes `requestCount` and `limit` fields)
2. **`inventory_check_failed`** — Downstream inventory check failures caused by the rate limiting (product-specific, customer-visible)

### Why It Happened (Systemic Factors)

1. **No client-side rate limiting**: The `grocery-api` does not implement any request throttling, token bucket, or sliding window rate limiter before calling the FreshFoods Wholesale API.
2. **No circuit breaker pattern**: When rate-limited, the service continues sending requests rather than backing off, worsening the problem.
3. **Per-product inventory calls**: Each product triggers an independent API call to the supplier rather than using batch/bulk queries, multiplying the request volume (8 products = 8+ API calls per user session).
4. **No retry-after honoring**: Despite receiving `retryAfter` values (30–60s) in error responses, the service does not appear to respect them — errors continue at 1–3 second intervals.

### Why It Was Not Caught Earlier

1. **No alert rules configured**: Grafana has zero alert rules defined — there is no automated detection of 429 error spikes.
2. **No Prometheus metrics**: Only Loki log ingestion is configured; no Prometheus datasource exists for metrics-based alerting on error rates or latency.
3. **No active incident management**: No Grafana incidents were open, indicating the monitoring-to-incident pipeline is not established.

---

## 5. Impact Assessment

| Dimension | Impact |
|---|---|
| **Services affected** | `grocery-api` (inventory check and product availability features) |
| **Customer impact** | Users cannot view real-time inventory/availability for any of 8 products. Shopping experience degraded — users may see stale data or "unavailable" status for in-stock items. |
| **Products affected** | Organic Bananas, Whole Milk, Sourdough Bread, Free-Range Eggs, Avocados, Ground Coffee, Chicken Breast, Greek Yogurt |
| **Data loss** | None — orders and health checks continue to function |
| **SLA impact** | At risk — inventory check availability significantly degraded. If SLA targets include product availability accuracy, these are likely breached. |
| **Blast radius** | All users of `grocery-web` making inventory/availability requests. Core ordering flow is operational but relies on potentially stale inventory data. |

---

## 6. Mitigation Actions Taken

| # | Action | Status | Notes |
|---|---|---|---|
| 1 | Investigated and identified root cause via Loki log analysis | Completed | SRE Agent — 2026-03-18 13:20 UTC |
| 2 | Generated RCA document with corrective action plan | Completed | This document |
| 3 | Immediate rate limiting / circuit breaker implementation | **Pending** | Requires App Team action |
| 4 | Supplier API rate limit increase request | **Pending** | Requires business/vendor management action |

**Recommended Immediate Mitigations:**

- **Reduce request volume**: Implement request deduplication or caching for inventory responses (TTL: 30–60s aligned with retryAfter values)
- **Respect retryAfter**: Implement backoff logic that honors the `retryAfter` header from the supplier
- **Batch API calls**: If the FreshFoods API supports batch inventory queries, consolidate per-product calls into a single request

---

## 7. Corrective Actions (Prevent Recurrence)

| # | Action | Owner | Priority | Due Date | Status |
|---|---|---|---|---|---|
| 1 | Implement client-side rate limiter (token bucket, max 10 req/window) for FreshFoods API calls | App Team | **Critical** | TBD | Open |
| 2 | Add circuit breaker pattern (trip on 3+ consecutive 429s, half-open after retryAfter period) | App Team | **High** | TBD | Open |
| 3 | Implement response caching for inventory data (TTL 30–60s) | App Team | **High** | TBD | Open |
| 4 | Honor `retryAfter` headers with exponential backoff | App Team | **High** | TBD | Open |
| 5 | Investigate batch/bulk inventory API from FreshFoods to reduce call volume | App Team / Vendor Mgmt | **Medium** | TBD | Open |
| 6 | Create Grafana alert rule for 429 error rate threshold (> 5 errors in 5 min) | SRE Team | **Critical** | 2026-03-18 | **Done** — UID `bfge66fq0yjnkf`, folder "SRE Alerts" |
| 7 | Add Prometheus metrics exporter for HTTP error codes and supplier API latency | SRE Team | **High** | TBD | Open |
| 8 | Create runbook for supplier rate-limit incidents (escalation path, vendor contact) | SRE Team | **Medium** | TBD | Open |
| 9 | Request rate limit increase from FreshFoods Wholesale API vendor | Vendor Management | **Medium** | TBD | Open |
| 10 | Implement graceful degradation — serve cached/stale inventory when rate-limited | App Team | **Medium** | TBD | Open |

---

## 8. Customer Communication Draft

> **Subject: Service Notice — Temporary Product Availability Display Issue**
>
> Dear Valued Customer,
>
> **What happened:**
> Starting at approximately 1:10 PM UTC on March 18, 2026, some users may have experienced intermittent issues viewing real-time product availability on our grocery platform. Product listings and ordering remained functional, but inventory status for some items may have appeared temporarily unavailable or outdated.
>
> **What we did:**
> Our engineering team identified the issue within minutes and is actively working on a permanent resolution. The issue is related to how our system communicates with a supplier partner to retrieve live inventory data.
>
> **Current status:**
> The service is operational. Some inventory checks may experience brief delays. Ordering is unaffected.
>
> **What we are doing to prevent this from happening again:**
> We are implementing additional safeguards in our systems to ensure more resilient communication with our supply chain partners, including improved request management and automated monitoring to detect issues faster.
>
> We sincerely apologize for any inconvenience. If you have questions or concerns, please contact our support team at [support@grocery-web.com].
>
> Thank you for your patience,
> **The Grocery Web Team**

---

## 9. Evidence Links

### Grafana Dashboards

- **SRE Troubleshooting Cockpit**: [Open Dashboard](https://amg-ps64h2ydsavgc-cvauf6fsdra3c0ed.eus2.grafana.azure.com/d/sre-cockpit-v1?from=now-1h&to=now)
  - Includes: Error Rate, Error Count by Code, Rate Limit (429) Events Over Time panels

### Loki Queries Used

| Query | Purpose |
|---|---|
| `{app="grocery-api"} \|= "429"` | All 429-related log entries |
| `count_over_time({app="grocery-api"} \|= "429" [1h])` | Total 429 error count (result: 44) |
| `{app="grocery-api", level="error"}` | All error-level logs |
| `{app="grocery-api", level="info"}` | Normal operation logs (baseline comparison) |

- **Loki Explore**: [Open in Grafana Explore](https://amg-ps64h2ydsavgc-cvauf6fsdra3c0ed.eus2.grafana.azure.com/explore?left=%7B%22datasource%22%3A%22bfbkeigsjyebkb%22%7D&from=now-1h&to=now)

### Related Incidents

- No prior related incidents found in Grafana Incident Management.
- No Jira tickets were referenced (no Jira integration detected).

---

## 10. Appendix: Sample Error Logs

**`supplier_rate_limit_exceeded` event (showing request overshoot):**
```json
{
  "event": "supplier_rate_limit_exceeded",
  "productId": "PROD001",
  "supplier": "FreshFoods Wholesale API",
  "requestCount": 25,
  "limit": 10,
  "retryAfter": 47,
  "errorCode": "SUPPLIER_RATE_LIMIT_429",
  "statusCode": 429,
  "message": "FreshFoods Wholesale API rate limit exceeded",
  "level": "error",
  "time": "2026-03-18T13:10:49.000Z"
}
```

**`inventory_check_failed` event (customer-visible failure):**
```json
{
  "event": "inventory_check_failed",
  "productId": "PROD005",
  "productName": "Avocados",
  "reason": "supplier_rate_limit",
  "errorCode": "SUPPLIER_RATE_LIMIT_429",
  "supplier": "FreshFoods Wholesale API",
  "retryAfter": 33,
  "statusCode": 429,
  "message": "Unable to check inventory for Avocados - supplier rate limited",
  "level": "error",
  "time": "2026-03-18T13:11:13.000Z"
}
```

---

*Report generated by Azure SRE Agent on 2026-03-18 13:20 UTC*
*Classification: Internal — Share with caution. Section 8 is approved for external customer communication.*
