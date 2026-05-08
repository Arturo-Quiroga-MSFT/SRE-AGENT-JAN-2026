<#
.SYNOPSIS
    Lists all live-published, enabled, non-private MCP.* scopes on the
    Microsoft MCP Server service principal.

.DESCRIPTION
    Microsoft adds and renames scopes on the MCP Server SP frequently
    during the public preview. ALWAYS run this before editing the grant
    script — the names you find here are the only valid inputs to
    Grant-EntraBetaMCPServerPermission.

    Output is grouped by suggested tier so you can quickly see which
    Tier 3 scope guesses (in README) are real and which need renaming.

.EXAMPLE
    pwsh ./discover-mcp-scopes.ps1

.NOTES
    Requires: Microsoft.Entra.Beta >= 1.0.13, an interactive sign-in
    with at least Application.Read.All.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$mcpAppId = 'e8c77dc2-69b3-43f4-bc51-3213c9d915b4'

Write-Host "==> Connecting to Entra (interactive)" -ForegroundColor Cyan
Connect-Entra -Scopes 'Application.Read.All' | Out-Null

Write-Host "==> Reading published scopes from MCP Server SP ($mcpAppId)" -ForegroundColor Cyan
$sp = Get-EntraBetaServicePrincipal `
    -Property 'PublishedPermissionScopes' `
    -Filter "AppId eq '$mcpAppId'"

$scopes = $sp.PublishedPermissionScopes |
    Where-Object {
        $_.IsEnabled -eq $true -and
        $_.AdditionalProperties['isPrivate'] -ne $true
    } |
    Select-Object Value, AdminConsentDisplayName |
    Sort-Object Value

Write-Host ""
Write-Host "Published, enabled, non-private MCP.* scopes:" -ForegroundColor Green
$scopes | Format-Table -AutoSize

Write-Host ""
Write-Host "Total: $($scopes.Count)" -ForegroundColor Green
Write-Host ""
Write-Host "Tier-cross-check (compare to enterprise-mcp-client-demo/README.md):" -ForegroundColor Cyan
$tierExpected = @{
    'Tier 1 (PIM core)' = @(
        'MCP.RoleManagement.Read.Directory',
        'MCP.RoleEligibilitySchedule.Read.Directory',
        'MCP.RoleAssignmentSchedule.Read.Directory'
    )
    'Tier 2 (identity context)' = @(
        'MCP.User.Read.All',
        'MCP.GroupMember.Read.All',
        'MCP.LicenseAssignment.Read.All',
        'MCP.Organization.Read.All'
    )
    'Tier 3 (SRE / audit broadening)' = @(
        'MCP.AuditLog.Read.All',
        'MCP.Group.Read.All',
        'MCP.Application.Read.All',
        'MCP.Policy.Read.All',
        'MCP.Device.Read.All'
    )
    'Tier 4 (security & risk)' = @(
        'MCP.SecurityAlert.Read.All',
        'MCP.SecurityIncident.Read.All',
        'MCP.IdentityRiskyUser.Read.All',
        'MCP.ServiceHealth.Read.All'
    )
}

$published = $scopes.Value
foreach ($tier in $tierExpected.Keys | Sort-Object) {
    Write-Host ""
    Write-Host $tier -ForegroundColor Yellow
    foreach ($s in $tierExpected[$tier]) {
        if ($published -contains $s) {
            Write-Host "  [OK] $s" -ForegroundColor Green
        } else {
            Write-Host "  [MISSING] $s  (search published list above for nearest match)" -ForegroundColor Red
        }
    }
}
