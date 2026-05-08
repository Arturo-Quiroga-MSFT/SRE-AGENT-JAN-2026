# PIM Tools via Enterprise MCP — Coverage Reference

> Reference card answering: *"What PIM-related tools are accessible via the
> Microsoft Enterprise MCP server, and where does our gap-filler fit?"*
>
> Captured: 2026-05-08. Source of truth: live discovery against
> `MngEnvMCAP094150` (40 published MCP scopes) + the testbed
> [`docs/enterprise-mcp-setup.md`](enterprise-mcp-setup.md).

---

## Architectural distinction

The Enterprise MCP server **does not expose PIM-specific tools.** It exposes
**three generic Microsoft Graph tools**, and "PIM" is a set of Graph
endpoints those tools can reach — gated by the `MCP.Role*` and related
scopes you grant to the client.

## Tools the Enterprise MCP server actually publishes (3 total)

| Tool | What it does |
|---|---|
| `microsoft_graph_suggest_queries` | RAG over a curated catalog of Graph examples — agent uses it to discover the right URL/filter for a question |
| `microsoft_graph_get` | Executes a read-only Graph call under the signed-in user's delegated permissions |
| `microsoft_graph_list_properties` | Schema lookup (`$select`/`$expand` shape discovery) |

That's it. Every "PIM tool" is actually a **Graph endpoint reached via `microsoft_graph_get`**.

---

## PIM-relevant Graph endpoints reachable today (read-only)

| Graph endpoint | What it answers | Required scope |
|---|---|---|
| `/roleManagement/directory/roleDefinitions` | Catalog of every directory role (PRA, GA, App Admin…) + their template IDs | `MCP.RoleManagement.Read.Directory` |
| `/roleManagement/directory/roleEligibilitySchedules` | "Who is *eligible* to activate which role at which scope" | `MCP.RoleEligibilitySchedule.Read.Directory` |
| `/roleManagement/directory/roleEligibilityScheduleInstances` | Same, but instance-expanded (point-in-time view) | `MCP.RoleEligibilitySchedule.Read.Directory` |
| `/roleManagement/directory/roleAssignmentSchedules` | "Who currently *holds* a role and when does it expire" | `MCP.RoleAssignmentSchedule.Read.Directory` |
| `/roleManagement/directory/roleAssignmentScheduleInstances` | Active assignments instance-expanded | `MCP.RoleAssignmentSchedule.Read.Directory` |
| `/roleManagement/directory/roleAssignments` | Permanent (non-PIM) directory role assignments | `MCP.RoleManagement.Read.Directory` |
| `/policies/roleManagementPolicies` | The rules: MFA required? Approval required? Max duration? Justification required? | `MCP.Policy.Read.All` (Tier 3) |
| `/policies/roleManagementPolicyAssignments` | Which policy applies to which role at which scope | `MCP.Policy.Read.All` (Tier 3) |
| `/identityGovernance/privilegedAccess/group/...` | PIM for Groups (PIM-eligible group membership) | `MCP.RoleManagement.Read.Directory` + `MCP.GroupMember.Read.All` |
| `/auditLogs/directoryAudits?$filter=category eq 'RoleManagement'` | Audit history of every PIM activation/approval/denial | `MCP.AuditLog.Read.All` (Tier 3) |

---

## The one PIM endpoint Enterprise MCP **cannot** reach

| Endpoint | Why blocked |
|---|---|
| `/roleManagement/directory/roleAssignmentScheduleRequests` (filtered to `status eq 'PendingApproval'`) | Requires `RoleAssignmentSchedule.ReadWrite.Directory` *delegated* permission. Enterprise MCP only mirrors `Read.*` scopes in current preview. |

This is the structural gap our custom [`pim-mcp`](../mcp-servers/pim-mcp/) server fills with **7 tools** using app-only auth via Managed Identity.

---

## Side-by-side coverage

```
┌─────────────────────────────────────────────┬──────────────────────────────┐
│ ENTERPRISE MCP (Microsoft-hosted)           │ PIM-MCP (our gap-filler)     │
│ Tools: 3 generic (Graph-get / suggest /     │ Tools: 7 PIM-specific        │
│        list-properties)                     │                              │
│ Auth:  Delegated OAuth (user signs in)      │ Auth:  App-only via MI       │
│                                             │                              │
│ ✅ Role definitions                          │ ✅ list_pending_pim_requests │
│ ✅ Eligibility schedules                     │     (the structural gap)    │
│ ✅ Active assignments                        │ ✅ get_request_status        │
│ ✅ Role-management policies                  │ ✅ get_request_approver      │
│ ✅ PIM audit history (auditLogs)             │ ✅ list_active_role_         │
│ ✅ User / group / license context            │     assignments             │
│ ❌ PendingApproval requests                  │ ✅ get_user                  │
│                                             │ ✅ get_role_definition       │
│                                             │ ✅ health                    │
└─────────────────────────────────────────────┴──────────────────────────────┘
```

---

## Practical implication for the demo

In the [`enterprise-mcp-client-demo/prompts/`](../enterprise-mcp-client-demo/prompts/) folder, every prompt that says "uses `enterprise-mcp.microsoft_graph_get`" really means *"the agent picks a Graph URL and the MCP server runs it."* The agent does the heavy lifting; the MCP server is essentially a guarded HTTP proxy with a query-suggestion catalog bolted on.

That's also why [`04-hybrid-pending.md`](../enterprise-mcp-client-demo/prompts/04-hybrid-pending.md) is the showpiece: it's the only prompt where the agent **must** switch tool servers mid-conversation, because no `microsoft_graph_get` call can fulfill the PendingApproval read.

---

## Cross-references

- [`enterprise-mcp-setup.md`](enterprise-mcp-setup.md) — full provisioning + scope discovery
- [`../enterprise-mcp-client-demo/README.md`](../enterprise-mcp-client-demo/README.md) — VS Code client demo (4 tiers, 6 prompts)
- [`../mcp-servers/pim-mcp/`](../mcp-servers/pim-mcp/) — gap-filler MCP source
- [`../README.md`](../README.md) §"F4. PIM access — hybrid" — architectural rationale
