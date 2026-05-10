# Zafin PIM Enablement — Trigger Mechanism Options

**Date:** 2026-05-10
**Owner:** Arturo Quiroga (PSA)
**Audience:** Zafin platform / SRE leads (Poornika et al.)
**Status:** Discussion draft — pick one for the PoC, plan the second for production

## Context

Per Poornika's PIM Enablement use-case email, the SRE Agent must:

1. Detect a pending PIM activation request.
2. Validate the requester's group membership, ticket, role, scope, etc.
3. Post an approve / not-approve recommendation with reasoning to Teams (or equivalent).
4. **Never auto-approve** — banking compliance requires human-in-the-loop.

Today's PoC covers steps 2 and 3 end-to-end (proven in `SRE-AGENT-CHATS/11.md` —
first live R004 PASS verdict). What is **not** yet covered is **step 1: how
the agent learns a request is waiting**.

At Zafin's volume of **~2,000–3,000 tickets/day** (≈ 1 every 30 s at peak),
relying on a human to prompt the agent is a non-starter for the stated
**5–10% Q2 / 25% Q3 ticket-automation targets**. We need a trigger.

This document compares three viable trigger mechanisms so we can choose
deliberately with Zafin.

---

## Option A — Scheduled SRE Agent prompt  *(lowest effort, recommended for PoC)*

Configure a saved prompt in Azure SRE Agent that fires on a fixed cadence
(e.g., every 1–5 min). The prompt itself is the same one humans use today:

> List pending PIM requests via `PIM-MCP_list_pending_pim_requests`. For
> each, run the full R001–R008 evaluation and post the Adaptive Card to
> Teams.

| Aspect | Detail |
|---|---|
| Trigger source | SRE Agent built-in scheduler |
| Latency | Worst case = polling interval (e.g., 5 min) |
| New infra | None |
| Operational cost | Agent invocations × frequency; predictable |
| Compliance footprint | Unchanged — same agent, same audit trail |
| Effort | **Hours** |

**Pros**

- Zero new components. Works today.
- Same audit surface (SRE Agent threads) as manual runs.
- Trivially throttled by adjusting the schedule.

**Cons**

- Polling latency. At every-5-min, requesters wait up to 5 min for the
  recommendation card.
- Cost scales linearly with frequency, even when the queue is empty.
- No backpressure — every tick lists the same backlog if the agent is
  slow to drain it.

**When to pick it:** PoC and early production. Acceptable while ticket
volumes stay below ~500/day per region.

---

## Option B — Logic App / Azure Function timer trigger  *(medium effort)*

A timer-triggered Azure Function (or Logic App) running every 30–60 s:

1. Calls the `pim-mcp` `list_pending_pim_requests` tool (or Graph
   directly) to get the current queue.
2. For each request ID **not already seen**, invokes the SRE Agent via
   its REST/conversation API with a templated prompt scoped to that one
   request ID.
3. Persists seen request IDs in a small store (Cosmos DB / Table
   Storage) to prevent duplicate evaluations.

| Aspect | Detail |
|---|---|
| Trigger source | Azure Functions / Logic Apps timer |
| Latency | 30–60 s |
| New infra | Function or Logic App + small state store + MI grants |
| Operational cost | Per-execution Function billing + state store |
| Compliance footprint | Function MI needs `RoleManagement.Read.Directory`; same agent audit trail |
| Effort | **Days** |

**Pros**

- Tighter latency than Option A.
- Per-request invocation = cleaner agent threads (one per request).
- Easy to add backpressure, retry, and dedupe logic.
- Familiar shape for Zafin's existing automation patterns.

**Cons**

- Still polling — Graph throttling counts against Zafin's tenant.
- One more component to deploy, secure, monitor, alert on.
- State store needs eviction policy (retain seen IDs only N days).

**When to pick it:** Late-PoC and production. Right answer for ~500–
3,000 requests/day if change-notification subscription overhead is
unwanted.

---

## Option C — Microsoft Graph change notifications (push)  *(highest effort, best at scale)*

Subscribe to Graph change notifications for
`roleAssignmentScheduleRequests`. When a new request is created, Graph
POSTs to a webhook endpoint we own, which then triggers the agent.

| Aspect | Detail |
|---|---|
| Trigger source | Microsoft Graph webhook (push) |
| Latency | Sub-second |
| New infra | Public HTTPS endpoint (Function/App Service) + subscription renewal job + secret store |
| Operational cost | Lower per-event than polling; subscription mgmt overhead |
| Compliance footprint | Webhook endpoint must validate HMAC + Graph client-state; secret rotation policy required |
| Effort | **Weeks** (build) + **ongoing** (renewals, validation) |

**Pros**

- Event-driven. No wasted calls when the queue is empty.
- Sub-second latency end to end.
- Scales cleanly to Zafin's full target volume.

**Cons / risks**

- **Verify support first.** `roleAssignmentScheduleRequests` must be on
  Graph's supported-resources list for change notifications. If not,
  fall back to Option B. *(Open ask — confirm against current Graph
  docs before committing.)*
- Subscription lifecycle: most Graph subscriptions expire every
  ~70 hours (4230 min) and require automated renewal. Missed renewal
  = silent miss of all PIM requests until detected.
- Public webhook endpoint = additional attack surface. Must validate
  the Graph validation handshake, the HMAC signature on every payload,
  and the `clientState` token.
- Secret rotation, certificate renewal, WAF rules — all standard but
  non-zero ongoing operational cost.

**When to pick it:** Production at full Zafin scale (≥ 1,000/day
sustained, or any latency-critical compliance window). Plan the
migration from Option B once volume justifies it.

---

## Comparison matrix

| Dimension | Option A — Scheduled prompt | Option B — Function timer | Option C — Graph webhook |
|---|---|---|---|
| Latency (worst case) | 1–5 min | 30–60 s | < 1 s |
| New components | 0 | 1 Function + 1 store | 1 Function + 1 store + 1 subscription mgr |
| Dev effort | Hours | Days | Weeks |
| Operational effort | Negligible | Low | Medium (renewals, secrets) |
| Graph throttling exposure | Low (single caller, low rate) | Medium (1×/min) | None (push) |
| Resilience to agent downtime | Auto-retries on next tick | Auto-retries on next tick | Graph retries with backoff for ~24 h, then drops |
| Maturity for Zafin volume target | PoC only | Up to ~3k/day | Full target + headroom |
| Compliance audit trail | Same SRE Agent threads | Same + Function logs | Same + Function logs + subscription audit |
| Time-to-value | Today | This week | Multi-sprint |

---

## Recommendation

**Ship Option A first**, in parallel with the work needed to close the
remaining functional gaps (Jira read loop for R001/R002/R003, Teams
webhook for delivery — see `SRE-AGENT-CHATS/11.md` Verdict section).
This proves the end-to-end workflow inside the next sprint with zero
new infrastructure.

**Plan Option B as the production trigger** for Zafin handoff. Build
it once R001–R008 are all functionally green and the recommendation
card is being delivered to Teams. Sized at days, not weeks.

**Treat Option C as a Q3 stretch goal**, contingent on:

1. Confirming `roleAssignmentScheduleRequests` supports Graph change
   notifications in Zafin's tenant geography.
2. Real measured pain from Option B latency (rare at 60-s polling).
3. Ops team having capacity for subscription-renewal automation.

---

## Open questions for Zafin

1. What latency between request and recommendation card is acceptable?
   (Drives A vs B vs C.)
2. Is there an existing internal Function App / Logic App pattern we
   should reuse for Option B, or do we deploy fresh?
3. For Option C: is a public HTTPS endpoint allowed under Zafin's
   network policy? If not, can we front the Function with API
   Management + Private Endpoint?
4. Where should "seen request IDs" be persisted — existing Cosmos DB
   account, Storage Table, or new tenant-scoped store?
5. What is the policy on Graph subscription secrets — Key Vault with
   rotation cadence X, or shared with the existing PIM-MCP MI?

---

## Out of scope (for this document)

- The actual approval action — Zafin is explicit that **fully
  autonomous approvals are not acceptable**. All three options stop at
  posting a recommendation. The human still clicks Approve in PIM.
- Any tool that *writes* to Graph (the pim-mcp server is read-only by
  architectural enforcement, not policy).
- Data residency / region pinning of the trigger component itself —
  needs a separate conversation tied to Zafin's existing landing zone.
