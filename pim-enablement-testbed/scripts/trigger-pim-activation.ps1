# Trigger a real PIM self-activation request to populate
# `roleAssignmentScheduleRequests` with `status=PendingApproval`, so the
# gap-filler `pim-mcp` server's `list_pending_pim_requests` tool returns a
# non-empty result for end-to-end demo purposes.
#
# This script:
#   1. Connects to Microsoft Graph with the delegated scopes Graph actually
#      requires (see `../docs/UPSTREAM_BUGS.md` BUG-001 for the
#      app-only equivalent quirk).
#   2. Lists the signed-in user's PIM-eligible Entra role assignments.
#   3. Lets you pick one interactively (or via -RoleDisplayName).
#   4. Submits a `selfActivate` request with justification + ticket info.
#   5. Polls `roleAssignmentScheduleRequests` for that request until it
#      reaches a terminal state (PendingApproval / Provisioned / Failed).
#
# IMPORTANT: The activation only lands as `PendingApproval` if the role's
# PIM policy has "Require approval to activate" enabled. Otherwise it goes
# straight to `Provisioned` and the pim-mcp tool (which filters for
# PendingApproval) will still see an empty result. Configure the policy in
# the Entra portal: PIM -> Microsoft Entra roles -> <role> -> Settings ->
# Edit -> Activation -> "Require approval to activate" = Yes (and add an
# approver other than yourself, otherwise you can self-approve).
#
# Usage:
#   pwsh ./trigger-pim-activation.ps1 -TenantId <tid>
#   pwsh ./trigger-pim-activation.ps1 -TenantId <tid> -RoleDisplayName "Privileged Role Administrator"
#   pwsh ./trigger-pim-activation.ps1 -TenantId <tid> -DurationHours 1 -Justification "SRE agent testbed demo"
#
# Requires: Microsoft.Graph PowerShell SDK
#   Install-Module Microsoft.Graph -Scope CurrentUser

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $TenantId,
    [string] $RoleDisplayName,
    [string] $Justification = "SRE agent testbed: validating gap-filler pim-mcp end-to-end",
    [string] $TicketNumber  = "TESTBED-001",
    [string] $TicketSystem  = "manual",
    [ValidateRange(1, 8)] [int] $DurationHours = 1
)

$ErrorActionPreference = 'Stop'

# --- 1. Prereqs ---------------------------------------------------------------

$requiredModules = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Identity.Governance', 'Microsoft.Graph.Users')
foreach ($m in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $m)) {
        Write-Host "Installing module $m ..." -ForegroundColor Yellow
        Install-Module $m -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module $m -ErrorAction Stop
}

# --- 2. Connect ---------------------------------------------------------------

$scopes = @(
    'RoleEligibilitySchedule.Read.Directory',
    'RoleAssignmentSchedule.ReadWrite.Directory',
    'RoleManagement.ReadWrite.Directory'
)
Write-Host "Connecting to Microsoft Graph (tenant $TenantId) ..." -ForegroundColor Cyan
Connect-MgGraph -TenantId $TenantId -Scopes $scopes -NoWelcome | Out-Null

$ctx = Get-MgContext
if (-not $ctx) { throw "Connect-MgGraph failed." }
$me  = Get-MgUser -UserId $ctx.Account
Write-Host "Signed in as: $($me.UserPrincipalName)  (oid=$($me.Id))" -ForegroundColor Green

# --- 3. List eligible roles ---------------------------------------------------

Write-Host "`nListing PIM-eligible Entra role assignments ..." -ForegroundColor Cyan
$eligible = Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance `
    -Filter "principalId eq '$($me.Id)'" `
    -ExpandProperty roleDefinition

if (-not $eligible -or $eligible.Count -eq 0) {
    Write-Host @"

You have no PIM-eligible Entra role assignments.

Create one in the portal first:
  Microsoft Entra admin center -> Identity governance -> Privileged Identity Management
  -> Microsoft Entra roles -> Assignments -> Add assignments
  Pick a role (e.g. 'Privileged Role Administrator'), assign yourself as Eligible.

Then re-run this script.
"@ -ForegroundColor Yellow
    return
}

$rows = $eligible | ForEach-Object {
    [pscustomobject]@{
        Role           = $_.RoleDefinition.DisplayName
        RoleId         = $_.RoleDefinitionId
        DirectoryScope = $_.DirectoryScopeId
        Ends           = $_.EndDateTime
    }
}
$rows | Format-Table -AutoSize | Out-Host

# --- 4. Pick a role -----------------------------------------------------------

if ($RoleDisplayName) {
    $picked = $eligible | Where-Object { $_.RoleDefinition.DisplayName -eq $RoleDisplayName } | Select-Object -First 1
    if (-not $picked) { throw "No eligible role named '$RoleDisplayName' found for $($me.UserPrincipalName)." }
} elseif ($eligible.Count -eq 1) {
    $picked = $eligible[0]
} else {
    $name = Read-Host "Enter the exact Role display name to activate"
    $picked = $eligible | Where-Object { $_.RoleDefinition.DisplayName -eq $name } | Select-Object -First 1
    if (-not $picked) { throw "No eligible role named '$name' found." }
}

Write-Host "`nActivating: $($picked.RoleDefinition.DisplayName)  scope=$($picked.DirectoryScopeId)" -ForegroundColor Cyan

# --- 5. Submit selfActivate request ------------------------------------------

$body = @{
    action           = 'selfActivate'
    principalId      = $me.Id
    roleDefinitionId = $picked.RoleDefinitionId
    directoryScopeId = $picked.DirectoryScopeId
    justification    = $Justification
    ticketInfo       = @{
        ticketNumber = $TicketNumber
        ticketSystem = $TicketSystem
    }
    scheduleInfo = @{
        startDateTime = (Get-Date).ToUniversalTime().ToString("o")
        expiration   = @{
            type     = 'AfterDuration'
            duration = "PT${DurationHours}H"
        }
    }
}

$created = New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -BodyParameter $body
Write-Host "Submitted request id=$($created.Id) status=$($created.Status)" -ForegroundColor Green

# --- 6. Poll for terminal state ----------------------------------------------

$terminal = @('PendingApproval','Provisioned','Failed','Denied','Canceled','Revoked')
$deadline = (Get-Date).AddSeconds(60)
$last = $created
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 3
    $last = Get-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -UnifiedRoleAssignmentScheduleRequestId $created.Id
    Write-Host "  status=$($last.Status)" -ForegroundColor DarkGray
    if ($terminal -contains $last.Status) { break }
}

Write-Host "`n=== Result ===" -ForegroundColor Cyan
$last | Select-Object Id, Status, Action, PrincipalId, RoleDefinitionId, DirectoryScopeId, CreatedDateTime, Justification | Format-List | Out-Host

switch ($last.Status) {
    'PendingApproval' {
        Write-Host "PendingApproval — pim-mcp's list_pending_pim_requests will now return this entry." -ForegroundColor Green
        Write-Host "Re-run: python pim-enablement-testbed/scripts/smoke-test-pim-mcp.py" -ForegroundColor Green
    }
    'Provisioned' {
        Write-Host "Provisioned immediately — the role's PIM policy does NOT require approval." -ForegroundColor Yellow
        Write-Host "To produce a PendingApproval, enable 'Require approval to activate' in the role's PIM settings, then re-run." -ForegroundColor Yellow
    }
    default {
        Write-Host "Terminal status: $($last.Status). Inspect in the Entra portal under PIM -> My requests." -ForegroundColor Yellow
    }
}
