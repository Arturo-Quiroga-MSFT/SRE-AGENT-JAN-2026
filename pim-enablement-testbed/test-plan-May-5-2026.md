

## What "thoroughly testing PIM enablement from SRE agent end-to-end" needs to cover

Three layers, each with a pass/fail signal:

### Layer 1 — Plumbing (does it connect?)
- Foundry SRE agent → `pim-mcp` SSE endpoint handshake succeeds
- Agent discovers `list_pending_pim_requests` tool
- MI auth works; first call returns 200 with empty array (no pending requests)
- Latency: tool-call round-trip < 2s p50

### Layer 2 — Functional (does it produce the right answer?)
End-to-end with a real PIM request triggered via `trigger-pim-activation.ps1`:
- Requester triggers activation → request shows `PendingApproval`
- Within polling interval, agent sees it via `list_pending_pim_requests`
- Agent enriches with: requester identity, role/scope, justification, ticket lookup (Jira MCP)
- Agent applies validation rules (even placeholder ones)
- Agent posts a structured recommendation — Adaptive Card OR plain Teams message OR conversation output (whatever's wired today)
- Approver sees the recommendation, can act in PIM portal
- Audit trail lands somewhere durable

### Layer 3 — Operational (does it survive contact with reality?)
- Polling cadence behavior at idle (no requests for an hour — does the agent spam logs / cost money?)
- What happens when `pim-mcp` is down? (Foundry retry behavior, agent error message)
- What happens when Graph throttles? (BUG-001 means more permission scope = more throttle exposure)
- What happens when two requests are pending simultaneously?
- Cold-start latency (ACA min-replicas, Foundry cold session)

## Suggested test sequence

| Step | Action | Pass criteria | Owner |
|---|---|---|---|
| 1 | Wire `pim-mcp` (SSE `/sse`) into the SRE agent in Foundry | Tool discovered in Foundry portal | You |
| 2 | Run `assign-pim-eligibility.ps1` for test requester | Eligibility visible in Entra portal | You |
| 3 | Run `configure-pim-approval.ps1` to require approval | Policy rule shows `isApprovalRequired=true` | You |
| 4 | Run `trigger-pim-activation.ps1` — submit real activation | Request enters `PendingApproval` | You |
| 5 | Ask SRE agent in chat: *"Are there any pending PIM requests?"* | Agent calls tool, returns the request | Agent |
| 6 | Ask: *"Should this PIM request be approved?"* | Agent enriches, applies rules, returns reasoning | Agent |
| 7 | Approver acts in PIM portal | Status flips to `Provisioned` | Approver |
| 8 | Ask agent again | Returns empty (request no longer pending) | Agent |
| 9 | Inspect Jira ticket | Audit comment present (if wired) | You |
| 10 | Check Foundry trace + ACA logs | Full reasoning chain visible end-to-end | You |

## What to instrument *before* you start testing

So you can answer "is MCP the right choice?" with data, not gut feel:

1. **Latency budget**: track p50/p95 of `list_pending_pim_requests` round-trip from Foundry. If it's >5s consistently, that's evidence for the Function-OpenAPI alternative.
2. **Cost per day**: ACA + Graph API calls + Foundry tokens. Rough check: is the cost defensible vs. a Function on Consumption?
3. **Failure modes log**: every error you hit during testing → tag as "MCP-specific" vs "would happen with any transport". This is the cleanest signal for the V2 decision.
4. **Reasoning quality**: capture 5–10 agent transcripts. Does the agent reason well about the data, or does it hallucinate around the structured payload? This is independent of transport but tells you if the *tool contract* is right.

## A scoring rubric for the decision

After testing, score each dimension 1–5. If MCP wins or ties on most, keep it. If Function-OpenAPI would have clearly won on 3+, plan the V2 swap.

| Dimension | What to measure | MCP must beat threshold |
|---|---|---|
| End-to-end latency (Layer 1) | p95 < 5s | Pass |
| Reliability under retry/cold-start | Zero unrecoverable errors in 20 trials | Pass |
| Foundry integration friction | Setup time, debug-loop time | Subjective |
| Compliance story strength | Can you explain it in one sentence? | Pass |
| Cost @ projected volume | < $100/mo at demo scale | Pass |
| Agent reasoning quality | Useful in 8/10 trials | Pass (transport-independent) |

