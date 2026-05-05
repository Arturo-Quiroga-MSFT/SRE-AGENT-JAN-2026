# Assign a Microsoft Entra role to a principal (user or group) as PIM-eligible,
# so that principal can later submit a `selfActivate` request via
# `trigger-pim-activation.ps1`.
#
# This script:
#   1. Resolves the role definition by display name (e.g. "Privileged Role Administrator").
#   2. Resolves the principal by UPN (user) or display name (group), or accepts a raw object ID.
#   3. Submits a `roleEligibilityScheduleRequest` with action=adminAssign.
#   4. Polls until terminal state and prints the resulting eligibility.
#
# IMPORTANT: The signed-in user running this script must hold (active or
# activated) "Privileged Role Administrator" or "Global Administrator" to
# assign Entra-role eligibility to others.
#
# Usage examples:
#   # Assign a user as eligible (permanent eligibility):
#   pwsh ./assign-pim-eligibility.ps1 -TenantId <tid> `
#        -RoleDisplayName "Privileged Role Administrator" `
#        -PrincipalUpn "alice@contoso.onmicrosoft.com"
#
#   # Time-bound eligibility (e.g. 30 days):
#   pwsh ./assign-pim-eligibility.ps1 -TenantId <tid> `
#        -RoleDisplayName "Privileged Role Administrator" `
#        -PrincipalUpn "alice@contoso.onmicrosoft.com" `
#        -DurationDays 30
#
#   # Assign a group as eligible (members inherit eligibility, requires role-assignable group):
#   pwsh ./assign-pim-eligibility.ps1 -TenantId <tid> `
#        -RoleDisplayName "Privileged Role Administrator" `
#        -PrincipalGroupName "PIM-PrivilegedRoleAdmins" -DurationDays 90
#
#   # Raw object id (skip lookup):
#   pwsh ./assign-pim-eligibility.ps1 -TenantId <tid> `
#        -RoleDisplayName "Privileged Role Administrator" `
#        -PrincipalObjectId "00000000-0000-0000-0000-000000000000"
#
# Requires: Microsoft.Graph PowerShell SDK
#   Install-Module Microsoft.Graph -Scope CurrentUser
#
# References:
#   https://learn.microsoft.com/en-us/graph/api/rbacapplication-post-roleeligibilityschedulerequests
#   https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/groups-features

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string] $TenantId,
    [Parameter(Mandatory)] [string] $RoleDisplayName,

    # Provide exactly one of these three:
    [string] $PrincipalUpn,
    [string] $PrincipalGroupName,
    [string] $PrincipalObjectId,

    [string] $DirectoryScopeId = '/',
    [string] $Justification    = "SRE agent testbed: granting eligibility for end-to-end PIM demo",
    [string] $TicketNumber     = "TESTBED-001",
    [string] $TicketSystem     = "manual",

    # 0 = permanent eligibility; otherwise time-bound in days.
    [ValidateRange(0, 365)] [int] $DurationDays = 0
)

$ErrorActionPreference = 'Stop'

# --- 1. Validate principal selector ------------------------------------------

$selectors = @($PrincipalUpn, $PrincipalGroupName, $PrincipalObjectId) | Where-Object { $_ }
if ($selectors.Count -ne 1) {
    throw "Provide exactly one of: -PrincipalUpn, -PrincipalGroupName, -PrincipalObjectId"
}

# --- 2. Prereqs ---------------------------------------------------------------

$requiredModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Identity.Governance',
    'Microsoft.Graph.Users',
    'Microsoft.Graph.Groups'
)
foreach ($m in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $m)) {
        Write-Host "Installing module $m ..." -ForegroundColor Yellow
        Install-Module $m -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module $m -ErrorAction Stop
}

# --- 3. Connect ---------------------------------------------------------------

$scopes = @(
    'RoleEligibilitySchedule.ReadWrite.Directory',
    'RoleManagement.ReadWrite.Directory',
    'Directory.Read.All'
)
Write-Host "Connecting to Microsoft Graph (tenant $TenantId) ..." -ForegroundColor Cyan
Connect-MgGraph -TenantId $TenantId -Scopes $scopes -NoWelcome | Out-Null

# --- 4. Resolve role definition ----------------------------------------------

$role = Get-MgRoleManagementDirectoryRoleDefinition -Filter "displayName eq '$RoleDisplayName'" -ErrorAction Stop | Select-Object -First 1
if (-not $role) { throw "Role '$RoleDisplayName' not found." }
Write-Host "Role:      $($role.DisplayName)  id=$($role.Id)" -ForegroundColor Green

# --- 5. Resolve principal ----------------------------------------------------

if ($PrincipalObjectId) {
    $principalId   = $PrincipalObjectId
    $principalKind = 'object-id'
    $principalName = $PrincipalObjectId
}
elseif ($PrincipalUpn) {
    $u = Get-MgUser -Filter "userPrincipalName eq '$PrincipalUpn'" -ErrorAction Stop | Select-Object -First 1
    if (-not $u) { throw "User '$PrincipalUpn' not found." }
    $principalId   = $u.Id
    $principalKind = 'user'
    $principalName = $u.UserPrincipalName
}
else {
    $g = Get-MgGroup -Filter "displayName eq '$PrincipalGroupName'" -ErrorAction Stop | Select-Object -First 1
    if (-not $g) { throw "Group '$PrincipalGroupName' not found." }
    if (-not $g.IsAssignableToRole) {
        throw "Group '$PrincipalGroupName' is not role-assignable. Recreate it with isAssignableToRole=true (cannot be changed after creation)."
    }
    $principalId   = $g.Id
    $principalKind = 'group'
    $principalName = $g.DisplayName
}
Write-Host "Principal: $principalName  ($principalKind $principalId)" -ForegroundColor Green
Write-Host "Scope:     $DirectoryScopeId" -ForegroundColor Green

# --- 6. Build schedule -------------------------------------------------------

$startUtc = (Get-Date).ToUniversalTime().ToString("o")
if ($DurationDays -gt 0) {
    $expiration = @{ type = 'AfterDuration'; duration = "P${DurationDays}D" }
    Write-Host "Duration:  $DurationDays days" -ForegroundColor Green
} else {
    $expiration = @{ type = 'NoExpiration' }
    Write-Host "Duration:  permanent" -ForegroundColor Green
}

$body = @{
    action           = 'adminAssign'
    justification    = $Justification
    roleDefinitionId = $role.Id
    directoryScopeId = $DirectoryScopeId
    principalId      = $principalId
    ticketInfo       = @{
        ticketNumber = $TicketNumber
        ticketSystem = $TicketSystem
    }
    scheduleInfo     = @{
        startDateTime = $startUtc
        expiration    = $expiration
    }
}

# --- 7. Submit ---------------------------------------------------------------

if (-not $PSCmdlet.ShouldProcess("$principalName -> $($role.DisplayName) at $DirectoryScopeId", "adminAssign roleEligibilityScheduleRequest")) {
    Write-Host "WhatIf: not submitting." -ForegroundColor Yellow
    return
}

$created = New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest -BodyParameter $body
Write-Host "`nSubmitted request id=$($created.Id) status=$($created.Status)" -ForegroundColor Green

# --- 8. Poll for terminal state ---------------------------------------------

$terminal = @('Provisioned','Failed','Denied','Canceled','Revoked','PendingApproval')
$deadline = (Get-Date).AddSeconds(60)
$last = $created
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 3
    $last = Get-MgRoleManagementDirectoryRoleEligibilityScheduleRequest -UnifiedRoleEligibilityScheduleRequestId $created.Id
    Write-Host "  status=$($last.Status)" -ForegroundColor DarkGray
    if ($terminal -contains $last.Status) { break }
}

Write-Host "`n=== Result ===" -ForegroundColor Cyan
$last | Select-Object Id, Status, Action, PrincipalId, RoleDefinitionId, DirectoryScopeId, CreatedDateTime, Justification | Format-List | Out-Host

switch ($last.Status) {
    'Provisioned' {
        Write-Host "Eligibility provisioned. The principal can now self-activate this role." -ForegroundColor Green
        Write-Host "Next: pwsh ./trigger-pim-activation.ps1 -TenantId $TenantId -RoleDisplayName `"$($role.DisplayName)`"" -ForegroundColor Green
    }
    'PendingApproval' {
        Write-Host "Eligibility request is pending admin approval (your tenant requires approval for adminAssign)." -ForegroundColor Yellow
    }
    default {
        Write-Host "Terminal status: $($last.Status). Inspect in the Entra portal under PIM -> Microsoft Entra roles -> Assignments." -ForegroundColor Yellow
    }
}
