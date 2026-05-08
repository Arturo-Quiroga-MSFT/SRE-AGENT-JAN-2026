<#
.SYNOPSIS
    Grants tiered MCP.* scopes on the Microsoft MCP Server SP to the
    Visual Studio Code built-in client app.

.DESCRIPTION
    Uses the pre-registered VS Code client app (no custom app
    registration required). Tiers map to the README:
      1 = PIM core
      2 = identity context
      3 = SRE / audit broadening (Zafin-friendly extension)

    ALWAYS run discover-mcp-scopes.ps1 first to confirm Tier 3 names are
    actually published in the target tenant. Edit $Tier3 below if the
    discovery script reports MISSING scopes.

.PARAMETER Tier
    Comma-separated list of tier numbers to grant. Default: 1,2.

.EXAMPLE
    pwsh ./grant-vscode-mcp-scopes.ps1                  # PIM minimum
    pwsh ./grant-vscode-mcp-scopes.ps1 -Tier 1,2,3      # Full SRE set
    pwsh ./grant-vscode-mcp-scopes.ps1 -Tier 1          # Roles only

.NOTES
    Requires: PowerShell 7+, Microsoft.Entra.Beta >= 1.0.13, tenant
    admin with Application.ReadWrite.All and
    DelegatedPermissionGrant.ReadWrite.All.
#>
[CmdletBinding()]
param(
    [int[]] $Tier = @(1, 2)
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$Tier1 = @(
    'MCP.RoleManagement.Read.Directory',
    'MCP.RoleEligibilitySchedule.Read.Directory',
    'MCP.RoleAssignmentSchedule.Read.Directory'
)

$Tier2 = @(
    'MCP.User.Read.All',
    'MCP.GroupMember.Read.All',
    'MCP.LicenseAssignment.Read.All',
    'MCP.Organization.Read.All'
)

# EDIT after running discover-mcp-scopes.ps1 if any name is reported MISSING.
$Tier3 = @(
    'MCP.AuditLog.Read.All',
    'MCP.Group.Read.All',
    'MCP.Application.Read.All',
    'MCP.Policy.Read.All',
    'MCP.Device.Read.All'
)

$selected = @()
if ($Tier -contains 1) { $selected += $Tier1 }
if ($Tier -contains 2) { $selected += $Tier2 }
if ($Tier -contains 3) { $selected += $Tier3 }
$selected = $selected | Sort-Object -Unique

Write-Host "==> Tiers requested: $($Tier -join ', ')" -ForegroundColor Cyan
Write-Host "==> Scopes to grant ($($selected.Count)):" -ForegroundColor Cyan
$selected | ForEach-Object { Write-Host "    - $_" }

Write-Host ""
Write-Host "==> Connecting to Entra (interactive — needs tenant admin)" -ForegroundColor Cyan
Connect-Entra -Scopes 'Application.ReadWrite.All','DelegatedPermissionGrant.ReadWrite.All' | Out-Null

Write-Host "==> Granting MCP scopes to the VS Code built-in client app" -ForegroundColor Cyan
Grant-EntraBetaMCPServerPermission `
    -ApplicationName 'VisualStudioCode' `
    -Scopes $selected

Write-Host ""
Write-Host "Done. Re-launch VS Code; the next call to enterprise-mcp will trigger consent." -ForegroundColor Green
Write-Host "To revoke later:" -ForegroundColor Yellow
Write-Host "    Revoke-EntraBetaMCPServerPermission -ApplicationName 'VisualStudioCode' -Scopes <name1>,<name2>"
