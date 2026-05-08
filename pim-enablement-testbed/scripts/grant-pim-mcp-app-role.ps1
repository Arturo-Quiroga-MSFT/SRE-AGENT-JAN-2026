# Grant the Microsoft Graph application permissions the gap-filler `pim-mcp`
# server needs on the agent's User-Assigned Managed Identity.
#
# The pim-mcp server uses app-only Graph auth (DefaultAzureCredential picks up
# the MI inside Container Apps via AZURE_CLIENT_ID) to call:
#   GET /v1.0/roleManagement/directory/roleAssignmentScheduleRequests
#
# Per Microsoft Graph docs, `RoleAssignmentSchedule.Read.Directory` should be
# sufficient. **In practice (verified live in MngEnvMCAP094150 on 2026-05-05),
# Graph runtime requires `RoleAssignmentSchedule.ReadWrite.Directory`** even
# for the read-only LIST call. See `../docs/UPSTREAM_BUGS.md` (BUG-001).
# Both grants are made below (Read.Directory left in place for when Microsoft
# fixes the runtime to honor the documented least-privilege scope).
#
# The `pim-mcp` MCP server source registers exactly one read tool plus a
# health probe; no write code path is reachable from MCP clients. PR review
# on `mcp-servers/pim-mcp/**` is the compensating control. See
# `../docs/threat-model.md` Residual Risk #4.
#
# Run once per environment after `azd up` (or after creating the agent MI):
#   pwsh ./grant-pim-mcp-app-role.ps1 -TenantId <tid> -AgentMiPrincipalId <object-id-from-bicep-output>
#
# References:
#   https://learn.microsoft.com/en-us/graph/api/rbacapplication-list-roleassignmentschedulerequests?view=graph-rest-1.0&tabs=http#permissions
#   ./../docs/UPSTREAM_BUGS.md

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $TenantId,
    [Parameter(Mandatory)] [string] $AgentMiPrincipalId,
    [string[]] $RequiredAppRoles = @(
        # ReadWrite is the role Graph runtime ACTUALLY enforces today (BUG-001).
        'RoleAssignmentSchedule.ReadWrite.Directory',
        # Read is what the docs SAY is sufficient. Kept so this script becomes
        # a no-op when Microsoft fixes the runtime; you can then remove the
        # ReadWrite grant manually.
        'RoleAssignmentSchedule.Read.Directory',
        # Required by `get_user` (resolves principalId -> displayName/UPN).
        'User.Read.All',
        # Required by `get_role_definition` (resolves roleDefinitionId -> name).
        # NOTE (0.7.0): also satisfies `list_eligible_role_assignments` against
        # /roleManagement/directory/roleEligibilityScheduleInstances, so no
        # separate RoleEligibilitySchedule.Read.Directory grant is required.
        # If you prefer the documented least-privilege scope instead, grant
        # 'RoleEligibilitySchedule.Read.Directory' and remove RoleManagement.
        'RoleManagement.Read.Directory',
        # Required by `get_request_approver` (Graph beta
        # /roleManagement/directory/roleAssignmentApprovals/{id}/steps).
        'PrivilegedAccess.Read.AzureAD',
        # Required by `get_user_group_memberships` (added 0.9.0; closes
        # validation rule R004). Read-only transitive group memberships:
        # GET /users/{id}/transitiveMemberOf.
        'GroupMember.Read.All'
    )
)

$ErrorActionPreference = 'Stop'

# Microsoft Graph SP (well-known appId)
$GraphAppId = '00000003-0000-0000-c000-000000000000'

if (-not (Get-Module -ListAvailable -Name Microsoft.Entra.Beta)) {
    Write-Host "==> Installing Microsoft.Entra.Beta module"
    Install-Module Microsoft.Entra.Beta -Force -AllowClobber -Scope CurrentUser
}

Write-Host "==> Connecting to Entra ($TenantId)"
Connect-Entra -TenantId $TenantId -Scopes 'AppRoleAssignment.ReadWrite.All','Application.Read.All' -NoWelcome | Out-Null

Write-Host "==> Resolving Microsoft Graph service principal"
$graphSp = Get-EntraBetaServicePrincipal -Filter "appId eq '$GraphAppId'"
if (-not $graphSp) {
    throw "Microsoft Graph service principal not found in tenant $TenantId."
}

Write-Host "==> Verifying agent MI exists (PrincipalId: $AgentMiPrincipalId)"
$mi = Get-EntraBetaServicePrincipal -ServicePrincipalId $AgentMiPrincipalId
if (-not $mi) {
    throw "Managed Identity service principal $AgentMiPrincipalId not found."
}
Write-Host "    DisplayName: $($mi.DisplayName)"

$existingAssignments = Get-EntraBetaServicePrincipalAppRoleAssignment -ServicePrincipalId $AgentMiPrincipalId

$grantFailures = @()

foreach ($roleValue in $RequiredAppRoles) {
    Write-Host "==> Processing app role: $roleValue"
    $appRole = $graphSp.AppRoles | Where-Object { $_.Value -eq $roleValue -and $_.AllowedMemberTypes -contains 'Application' }
    if (-not $appRole) {
        Write-Warning "    Graph does not publish application app role '$roleValue' — skipping."
        continue
    }

    $alreadyGranted = $existingAssignments | Where-Object { $_.ResourceId -eq $graphSp.Id -and $_.AppRoleId -eq $appRole.Id }
    if ($alreadyGranted) {
        Write-Host "    Already granted (Id: $($alreadyGranted.Id)) — skipping."
        continue
    }

    Write-Host "    Granting..."
    try {
        # ErrorAction=Stop converts the underlying non-terminating Graph 403
        # into a catchable terminating error, so we don't print "Done." after
        # a silent failure (caused by the caller lacking PRA / Global Admin).
        New-EntraBetaServicePrincipalAppRoleAssignment `
            -ServicePrincipalId $AgentMiPrincipalId `
            -PrincipalId        $AgentMiPrincipalId `
            -ResourceId         $graphSp.Id `
            -AppRoleId          $appRole.Id `
            -ErrorAction        Stop | Out-Null
        Write-Host "    Done."
    }
    catch {
        $msg = $_.Exception.Message
        Write-Warning "    GRANT FAILED for '$roleValue': $msg"
        if ($msg -match 'Authorization_RequestDenied|Insufficient privileges|403') {
            Write-Warning "    Hint: granting Microsoft Graph application app roles requires the caller to hold"
            Write-Warning "          Privileged Role Administrator (or Global Administrator) at directory scope."
            Write-Warning "          Activate PRA via PIM in this tenant, then re-run this script."
        }
        $grantFailures += $roleValue
    }
}

Write-Host ""
Write-Host "==> Verification"
$assignments = Get-EntraBetaServicePrincipalAppRoleAssignment -ServicePrincipalId $AgentMiPrincipalId |
    Where-Object { $_.ResourceId -eq $graphSp.Id }
$assignedRoleValues = @()
foreach ($a in $assignments) {
    $role = $graphSp.AppRoles | Where-Object Id -eq $a.AppRoleId
    if ($role) {
        $assignedRoleValues += $role.Value
        "    {0} -> {1}" -f $mi.DisplayName, $role.Value
    }
}

# Fail loudly if any required role is missing, so a partial grant can't be
# mistaken for success on the next deploy / smoke test.
$missing = @()
foreach ($required in $RequiredAppRoles) {
    $publishedAsApp = $graphSp.AppRoles | Where-Object { $_.Value -eq $required -and $_.AllowedMemberTypes -contains 'Application' }
    if (-not $publishedAsApp) { continue }   # already warned above
    if ($assignedRoleValues -notcontains $required) {
        $missing += $required
    }
}

if ($missing.Count -gt 0 -or $grantFailures.Count -gt 0) {
    Write-Host ""
    Write-Error "Grant INCOMPLETE. Missing required app roles on '$($mi.DisplayName)':`n  - $($missing -join "`n  - ")"
    if ($grantFailures.Count -gt 0) {
        Write-Error "Grant cmdlet errored on:`n  - $($grantFailures -join "`n  - ")"
    }
    exit 1
}

Write-Host ""
Write-Host "Grant complete. The pim-mcp Container App can now call"
Write-Host "  GET /v1.0/roleManagement/directory/roleAssignmentScheduleRequests"
Write-Host "as the Managed Identity."
Write-Host ""
Write-Host "NOTE: Newly-granted Graph app roles can take 5–60 minutes to propagate"
Write-Host "      across Graph's resource-side claim cache. Expect intermittent 403s"
Write-Host "      during that window. See ../docs/UPSTREAM_BUGS.md (BUG-001)."
Write-Host ""
Write-Host "Smoke test from Cloud Shell or any az-logged-in shell:"
Write-Host "  az rest --method GET --url 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleRequests?\$top=1'"
