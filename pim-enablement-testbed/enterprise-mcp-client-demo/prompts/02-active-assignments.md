# Prompt 02 — Who currently holds privileged roles?

**Tier required:** 1 (`MCP.RoleAssignmentSchedule.Read.Directory`) + 2 (`MCP.User.Read.All`)

**Tools expected:** `enterprise-mcp.microsoft_graph_get`

## Prompt

> Using enterprise-mcp, show me every currently active PIM role assignment in the tenant. Include the role name, the principal's UPN, when the assignment started, and when it expires. Sort by expiry time, soonest first. Highlight any assignment that expires in the next hour.

## What success looks like

- Agent calls `/roleManagement/directory/roleAssignmentSchedules` filtered to active assignments.
- Sorted output, expiry highlighted (e.g. bold or 🔴).
- For our testbed tenant when an activation is live: `pim-requester` shown holding `Privileged Role Administrator` with the matching `endDateTime`.

## Why this matters for SRE

This is the "who has the keys right now?" report on demand. In an incident, the SRE can ask before assuming role-elevated activity is malicious vs. an active legitimate elevation.

## Common failure modes

- **Empty result** → no PIM activation is live. Trigger one with `../../scripts/trigger-pim-activation.ps1`.
- **Tier 2 not granted** → UPNs show as OIDs. Re-run grant with Tier 2.
