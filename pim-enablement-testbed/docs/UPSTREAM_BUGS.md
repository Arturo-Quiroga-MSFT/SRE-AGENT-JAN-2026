# Upstream Bugs / Doc Issues Discovered During PIM Enablement Live Test

> Findings to file with Microsoft Graph and Microsoft MCP Server for Enterprise teams.
> Captured during live testing in tenant `MngEnvMCAP094150.onmicrosoft.com` on 2026-05-04 / 2026-05-05.

---

## BUG-001 — Graph runtime requires `*ReadWrite.Directory` for read-only LIST of `roleAssignmentScheduleRequests`

### Severity

High — forces over-privileged grants in production deployments and contradicts the published documentation.

### Endpoint

`GET https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleRequests`

### Documented permissions (per [Microsoft Learn](https://learn.microsoft.com/en-us/graph/api/rbacapplication-list-roleassignmentschedulerequests?view=graph-rest-1.0&tabs=http#permissions))

| Permission type | Least privileged |
|---|---|
| Delegated (work or school) | `RoleAssignmentSchedule.Read.Directory` |
| Application | `RoleAssignmentSchedule.Read.Directory` |

### Actual runtime behavior

Both delegated and application tokens carrying `RoleAssignmentSchedule.Read.Directory` receive:

```json
{
  "error": {
    "code": "UnknownError",
    "message": "{\"errorCode\":\"PermissionScopeNotGranted\",\"message\":\"Authorization failed due to missing permission scope RoleAssignmentSchedule.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleAssignmentSchedule.Remove.Directory.\",\"instanceAnnotations\":[]}"
  }
}
```

Granting any of `RoleAssignmentSchedule.ReadWrite.Directory`, `RoleManagement.ReadWrite.Directory`, or `RoleAssignmentSchedule.Remove.Directory` resolves the 403.

### Reproduction

1. Tenant with Entra ID P2 active (we used a P2 trial in `MngEnvMCAP094150`).
2. Create a workload identity (User-Assigned Managed Identity in our case).
3. Grant **only** `RoleAssignmentSchedule.Read.Directory` (Graph application role) to the MI.
4. Wait at least 60 minutes for app-role propagation across Graph's resource-side cache.
5. From a workload that uses the MI, call:

   ```http
   GET /v1.0/roleManagement/directory/roleAssignmentScheduleRequests?$top=5
   Authorization: Bearer <MI-issued Graph token>
   ```

6. Observe HTTP 403 with the message above.

### Impact

Forces customers (including regulated banking environments) to grant a tenant-wide `*ReadWrite.Directory` Graph permission to a workload that only needs to read. This is unacceptable for least-privilege deployments and we had to add explicit threat-model and compliance call-outs in our reference architecture to justify the over-grant (see `threat-model.md` in this folder, Residual Risk #4).

### Requested fix

Either:

1. **Preferred:** Update Graph runtime to honor `RoleAssignmentSchedule.Read.Directory` (and the matching delegated read-only scope) for the LIST `roleAssignmentScheduleRequests` endpoint.
2. **Alternative:** Update the documentation to reflect the actual required scopes, AND publish a least-privilege read-only scope that works for this collection.

### Workaround in our codebase

`pim-mcp` Managed Identity is granted `RoleAssignmentSchedule.ReadWrite.Directory`. The MCP server source code registers exactly one read tool and one health tool — no write code path is reachable from the MCP transport. PR review on `mcp-servers/pim-mcp/**` is the compensating control.

---

## BUG-002 — Graph rejects `$filter` and `$orderby` on `roleAssignmentScheduleRequests` collection

### Severity

Medium — forces client-side filtering, increases token consumption, and contradicts standard OData expectations.

### Endpoint

`GET https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleRequests`

### Behavior

| Query | Response |
|---|---|
| `?$filter=status eq 'PendingApproval'` | `400 InvalidFilter — The status eq 'PendingApproval' filter is invalid.` |
| `?$orderby=createdDateTime desc` | `400 InvalidFilter — The  filter is invalid.` (note the empty filter token in the message) |
| No query options | 200 OK |
| `$select` and `$expand` | 200 OK |

### Expected behavior

Standard OData semantics. At minimum, `$filter` on `status` (an enum-valued property) and `$orderby` on `createdDateTime` should work, since both are on the documented response schema.

### Impact

Forces consumers to over-fetch and filter client-side. We over-fetch up to 4× the requested page and filter `status == 'PendingApproval'` in `pim-mcp`. This is wasteful at scale and surfaces a confusing 400 to anyone copy-pasting the example queries from the Graph docs.

### Requested fix

Either:

1. Implement `$filter` on `status` and `$orderby` on `createdDateTime` (and other timestamp fields).
2. If unsupported by design, document the restriction explicitly on the LIST endpoint page and provide a recommended sort/filter pattern.

### Workaround in our codebase

`pim-mcp` over-fetches and filters in Python. See `mcp-servers/pim-mcp/tools.py` `list_pending_pim_requests`.

---

## BUG-003 — Microsoft MCP Server for Enterprise lacks scopes to reach the PIM Requests collection

### Severity

Medium — forces customers to bolt on a custom MCP server for one endpoint, defeating the "single hosted MCP" value proposition for PIM scenarios.

### Endpoint affected

The Microsoft MCP Server for Enterprise (`https://mcp.svc.cloud.microsoft/enterprise`, AppId `e8c77dc2-69b3-43f4-bc51-3213c9d915b4`) currently publishes 41 scopes, all `MCP.*Read.*`. None map to a Graph permission that satisfies the runtime requirement of BUG-001. As a result, the Enterprise MCP server cannot serve `roleAssignmentScheduleRequests` at all today.

### Confirmed via

`Get-EntraBetaServicePrincipal -Filter "appId eq 'e8c77dc2-69b3-43f4-bc51-3213c9d915b4'" -Property 'PublishedPermissionScopes'` enumerated all 41 scopes; only `MCP.RoleManagement.Read.Directory`, `MCP.RoleAssignmentSchedule.Read.Directory`, and `MCP.RoleEligibilitySchedule.Read.Directory` map to the role-management surface, and per BUG-001 none of these are sufficient to LIST schedule requests.

### Requested fix

Publish a `MCP.RoleAssignmentScheduleRequest.Read.Directory` (or equivalent) scope on the Enterprise MCP service principal, mapped to whichever Graph permission the runtime actually requires (per BUG-001 resolution).

### Workaround in our codebase

Hybrid architecture: ~90% of PIM reads via Enterprise MCP, plus a single-tool custom MCP (`pim-mcp`) using app-only Graph auth via Managed Identity for this one endpoint. We will retire `pim-mcp` once BUG-001 and BUG-003 are both resolved.

---

## Status

- [ ] BUG-001 filed at <https://github.com/microsoftgraph/microsoft-graph-docs-contrib/issues> (TBD)
- [ ] BUG-002 filed at same (TBD)
- [ ] BUG-003 filed via the MCP Server for Enterprise feedback channel (TBD)
- [ ] Internal escalation via Partner Solutions Architect channel — pending Zafin demo
