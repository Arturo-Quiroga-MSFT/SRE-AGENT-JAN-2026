# PIM End-to-End Reproduction Guide

Step-by-step recipe to reproduce the SRE-agent / Microsoft Graph PIM gap-filler validation that was performed in `MngEnvMCAP094150.onmicrosoft.com` on 2026-05-05. Three identities are involved:

| Role        | Identity                                          | Purpose                                                  |
|-------------|---------------------------------------------------|----------------------------------------------------------|
| Operator    | A user with **Privileged Role Administrator**     | Runs `assign-pim-eligibility.ps1` and `configure-pim-approval.ps1` |
| Requester   | Any standard user (e.g. `requester@tenant`)       | Runs `trigger-pim-activation.ps1` to self-activate       |
| Approver    | A user **other than the Requester**               | Approves the request in the Entra portal                 |

`<TID>` below = your tenant ID.

## 0. Prereqs (one-time)

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

The `pim-mcp` Container App must already be deployed and the agent MI granted Graph app roles. See `../README.md` and `grant-pim-mcp-app-role.ps1`.

## 1. Operator: assign Requester as PIM-eligible

```powershell
pwsh ./assign-pim-eligibility.ps1 `
  -TenantId <TID> `
  -RoleDisplayName "Privileged Role Administrator" `
  -PrincipalUpn "requester@<tenant>.onmicrosoft.com" `
  -DurationDays 30
```

Expected: `status=Provisioned`. The Requester now appears in PIM → Microsoft Entra roles → Assignments → **Eligible**.

## 2. Operator: require approval on the role's PIM activation policy

First inspect (no changes):

```powershell
pwsh ./configure-pim-approval.ps1 `
  -TenantId <TID> `
  -RoleDisplayName "Privileged Role Administrator" -WhatIf
```

Then apply, listing approvers (must NOT include the Requester):

```powershell
pwsh ./configure-pim-approval.ps1 `
  -TenantId <TID> `
  -RoleDisplayName "Privileged Role Administrator" `
  -ApproverObjectIds @('<approver-user-oid>')
```

Expected: rule dump shows `isApprovalRequired=true` and your approver in `primaryApprovers`.

## 3. Requester: submit a self-activation

Sign in as the Requester (`Connect-MgGraph` will pop the browser):

```powershell
pwsh ./trigger-pim-activation.ps1 `
  -TenantId <TID> `
  -RoleDisplayName "Privileged Role Administrator" `
  -DurationHours 1 `
  -Justification "Testbed end-to-end validation"
```

Expected: `status=PendingApproval`. The request now lives in `roleAssignmentScheduleRequests` with `status=PendingApproval`.

If you instead see `status=Provisioned`, step 2 didn't take effect (or the requester is also an approver and auto-approved). Re-check step 2 with `-WhatIf`.

## 4. Validate the gap-filler picks it up

From this repo root, with the Python venv activated:

```bash
python ./pim-enablement-testbed/scripts/smoke-test-pim-mcp.py
```

Expected (truncated):

```json
{
  "value": [
    {
      "id": "<request-guid>",
      "status": "PendingApproval",
      "action": "selfActivate",
      "principalId": "<requester-oid>",
      "roleDefinitionId": "<role-guid>",
      "directoryScopeId": "/",
      "justification": "Testbed end-to-end validation",
      "createdDateTime": "2026-05-05T...Z"
    }
  ],
  "fetchedCount": 1,
  "pendingCount": 1
}
```

That confirms the full chain: MCP SSE → FastMCP → DefaultAzureCredential → IMDS → MI token → Graph 200 → JSON normalized for the SRE agent.

## 5. (Optional) Approver closes the loop

In the Entra portal as the Approver: PIM → Approve requests → approve. Re-run the smoke test and `pendingCount` returns to 0; the request now lives in `roleAssignmentScheduleInstances` (active).

## 6. Cleanup

```powershell
# Revoke the eligibility (Operator):
# Use Entra portal -> PIM -> Microsoft Entra roles -> Assignments -> Eligible -> Remove
# Or programmatically with action=adminRemove on roleEligibilityScheduleRequests.

# Restore default (no-approval) policy if desired:
# Re-run configure-pim-approval.ps1 with no -ApproverObjectIds will only print
# current state. To DISABLE approval, edit the script's $body to set
# isApprovalRequired=$false, or use the portal.
```

## Known runtime quirks (read before filing tickets)

See `../docs/UPSTREAM_BUGS.md`:

- **BUG-001**: app-only LIST `roleAssignmentScheduleRequests` requires `RoleAssignmentSchedule.ReadWrite.Directory` despite docs claiming `Read.Directory` is sufficient.
- **BUG-002**: `$filter`, `$orderby`, `$expand` are all rejected on this collection — server filters client-side instead.
- **BUG-003**: Enterprise MCP doesn't expose a Graph PIM-write scope; this gap-filler exists exactly because of that.
- App-role propagation lag of 5–60+ minutes after grant (resource-side claim cache). If step 4 fails with `403 PermissionScopeNotGranted` immediately after first deploy, wait and re-run.
