# One-time provisioning of the Microsoft MCP Server for Enterprise in a tenant,
# plus the custom MCP Client app and the agent service-account user.
#
# PLACEHOLDER scaffold. Fill in the TODO sections and run:
#   pwsh ./provision-enterprise-mcp.ps1 -TenantId <tid> -McpClientAppName "..." -ServiceAccountUpn "svc-...@<tenant>"
#
# Reference:
#   https://learn.microsoft.com/en-us/graph/mcp-server/overview
#   https://github.com/microsoft/EnterpriseMCP

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $TenantId,
    [Parameter(Mandatory)] [string] $McpClientAppName,
    [Parameter(Mandatory)] [string] $ServiceAccountUpn
)

$ErrorActionPreference = 'Stop'

# Microsoft MCP Server for Enterprise — fixed AppId (do not change)
$EnterpriseMcpAppId = 'e8c77dc2-69b3-43f4-bc51-3213c9d915b4'

# Read-only scopes the PIM Enablement agent needs.
# These names were verified live in tenant MngEnvMCAP094150 on 2026-05-04 against
# the 41 PublishedPermissionScopes the MCP server exposes. Role* scopes use the
# `.Read.Directory` suffix (mirroring Graph), NOT `.Read.All`. There is NO
# `MCP.Directory.Read.All` scope. Always re-discover before changing this list:
#   (Get-EntraBetaServicePrincipal -Filter "AppId eq '$EnterpriseMcpAppId'" -Property PublishedPermissionScopes).PublishedPermissionScopes |
#     Where-Object { $_.IsEnabled -and -not $_.AdditionalProperties['isPrivate'] } |
#     Select-Object Value, AdminConsentDisplayName | Sort-Object Value
$RequiredScopes = @(
    'MCP.RoleManagement.Read.Directory',
    'MCP.RoleEligibilitySchedule.Read.Directory',
    'MCP.RoleAssignmentSchedule.Read.Directory',
    'MCP.User.Read.All',
    'MCP.GroupMember.Read.All',
    'MCP.LicenseAssignment.Read.All',
    'MCP.Organization.Read.All'
)

Write-Host "==> Installing / verifying Microsoft.Entra.Beta module"
if (-not (Get-Module -ListAvailable -Name Microsoft.Entra.Beta)) {
    Install-Module Microsoft.Entra.Beta -Force -AllowClobber -Scope CurrentUser
}

Write-Host "==> Connecting to Entra ($TenantId)"
Connect-Entra -TenantId $TenantId -Scopes 'Application.ReadWrite.All','DelegatedPermissionGrant.ReadWrite.All','User.ReadWrite.All','RoleManagement.ReadWrite.Directory'

Write-Host "==> Step 1: Provision the MCP Server service principal in the tenant"
# TODO: idempotent check first — only POST if SP for $EnterpriseMcpAppId is not already present.
#   $existing = Get-EntraBetaServicePrincipal -Filter "AppId eq '$EnterpriseMcpAppId'"
#   if (-not $existing) { New-EntraBetaServicePrincipal -AppId $EnterpriseMcpAppId }
Write-Host "  (stub) would ensure SP exists for AppId $EnterpriseMcpAppId"

Write-Host "==> Step 2: Register the custom MCP Client app: $McpClientAppName"
# TODO: New-EntraBetaApplication ... with the right RedirectUris (Foundry generates one per connector;
# you may need to come back here after creating the connector and patch RedirectUris).
Write-Host "  (stub) would create app registration: $McpClientAppName"
$mcpClientAppId = '<MCP_CLIENT_APP_ID>'  # TODO: capture from creation output

Write-Host "==> Step 3: Grant MCP scopes to the client app"
Write-Host "  Scopes:"
$RequiredScopes | ForEach-Object { Write-Host "    - $_" }
# Grant-EntraBetaMCPServerPermission -ApplicationId $mcpClientAppId -Scopes $RequiredScopes
Write-Host "  (stub) would invoke Grant-EntraBetaMCPServerPermission"

Write-Host "==> Step 4: Provision service-account user: $ServiceAccountUpn"
# TODO: New-MgUser ... cert-based credential preferred; if password used, force MFA + CA policy.
Write-Host "  (stub) would create user: $ServiceAccountUpn"

Write-Host "==> Step 5: Assign service account as PIM-eligible (read-only roles only)"
# TODO: New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest for:
#   - Reader (Azure RBAC at test RG scope)
#   - Monitoring Reader
#   - Log Analytics Reader
# Do NOT grant any approver / writer role.
Write-Host "  (stub) would create PIM eligibility for read-only roles"

Write-Host ""
Write-Host "Provisioning complete (scaffold)."
Write-Host "Next steps:"
Write-Host "  1. Capture MCP Client App Id and update agent/Foundry connector config."
Write-Host "  2. Sign in to the Foundry connector once as $ServiceAccountUpn to consent."
Write-Host "  3. Run scripts/verify-deployment.sh"
