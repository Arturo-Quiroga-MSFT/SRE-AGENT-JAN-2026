# Prompt 01 — List PIM-eligible role assignments

**Tier required:** 1 (`MCP.RoleEligibilitySchedule.Read.Directory`)

**Tools expected:** `enterprise-mcp.microsoft_graph_suggest_queries` then `enterprise-mcp.microsoft_graph_get`

## Prompt (paste into Copilot Chat — Agent Mode)

> Using the enterprise-mcp tools, list every PIM-eligible role assignment in this tenant. For each one, show the principal display name, the role definition display name, the scope, and the start/end timestamps. Group the output by role.

## What success looks like

- The agent calls `microsoft_graph_get` against `/roleManagement/directory/roleEligibilitySchedules` (or `roleEligibilityScheduleInstances`).
- Result is a grouped table, not a JSON dump.
- For our testbed tenant: should include `pim-requester` eligible for `Privileged Role Administrator`.

## Common failure modes

- **403 Forbidden** → Tier 1 scope not consented. Re-run `grant-vscode-mcp-scopes.ps1 -Tier 1`.
- **Names show as OIDs** → agent didn't expand `principalId`. Re-prompt: "expand the `principalId` to the user UPN using the user resource."
