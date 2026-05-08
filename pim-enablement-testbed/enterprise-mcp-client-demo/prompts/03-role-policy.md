# Prompt 03 — Approval policy for a role

**Tier required:** 1 (`MCP.RoleManagement.Read.Directory`)

**Tools expected:** `enterprise-mcp.microsoft_graph_suggest_queries` then `enterprise-mcp.microsoft_graph_get`

## Prompt

> Using enterprise-mcp, show me the approval and MFA policy for the `Privileged Role Administrator` role in this tenant. Specifically: is approval required? Who are the approvers? Is MFA enforced on activation? What is the maximum activation duration? Tell me which `unifiedRoleManagementPolicy` rules drive each answer.

## What success looks like

- Agent walks `/policies/roleManagementPolicies` and `/policies/roleManagementPolicyAssignments`, finds the policy assigned to PRA at directory scope.
- Per-rule answers (`Approval_EndUser_Assignment`, `Enablement_EndUser_Assignment`, `Expiration_EndUser_Assignment`).
- For our testbed: should report `isApprovalRequired = true` after `configure-pim-approval.ps1` was run.

## Why this matters

Same data the agent triages against in production. Having an engineer ask this on-demand sanity-checks policy drift between tenants and gives partner architects a way to inspect their config without leaving the editor.

## Common failure modes

- **Agent returns the wrong policy** → multiple policies can match a role; ask "filter to the policy whose `roleDefinitionId` equals `e8611ab8-c189-46e8-94e1-60213ab1f814`".
