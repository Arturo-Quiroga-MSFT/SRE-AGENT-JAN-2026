# Prompt 04 — Hybrid pending-request triage (the showpiece)

**Tier required:** 1 + 2

**Tools expected:**
- `enterprise-mcp.microsoft_graph_get` — for role + user resolution
- `pim-mcp.list_pending_pim_requests` — for the PendingApproval read that Enterprise MCP cannot serve
- `pim-mcp.get_user`, `pim-mcp.get_role_definition` — fallback enrichment (works even if Tier 2 missing)

## Prompt

> List every PIM activation request that is currently in PendingApproval. For each request, show the requester's UPN, the role they want, the scope, the justification text, and the ticket reference if any. Use enterprise-mcp where you can; fall back to pim-mcp for anything Enterprise MCP refuses to return. Tell me which tool gave you each piece of data.

## What success looks like

The agent's reasoning trace shows:

1. Tries Enterprise MCP first for `roleAssignmentScheduleRequests?$filter=status eq 'PendingApproval'`.
2. Receives a structural permission error (the documented `RoleAssignmentSchedule.ReadWrite.Directory` requirement that Enterprise MCP won't satisfy in the current preview).
3. Falls back to `pim-mcp.list_pending_pim_requests`.
4. Uses Enterprise MCP `microsoft_graph_get` for user + role definition expansion.
5. Final answer attributes each field to its source tool.

## Why this is the showpiece

This single prompt **demonstrates the entire architectural argument** for the testbed: Enterprise MCP for ~90% of Graph reads, the gap-filler `pim-mcp` for the one structural blocker, agent reasoning to combine them transparently. If the partner only watches one prompt, this is it.

## Common failure modes

- **Agent doesn't try Enterprise MCP first** → restate: "I want to see Enterprise MCP attempt this even if it fails — it's the test."
- **No pending requests** → trigger one: `../../scripts/trigger-pim-activation.ps1 -RoleDisplayName "Privileged Role Administrator" -DurationHours 4 -Justification "Hybrid demo"`.
