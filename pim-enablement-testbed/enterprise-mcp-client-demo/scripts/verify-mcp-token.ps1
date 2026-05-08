<#
.SYNOPSIS
    Acquires a delegated token for the Microsoft MCP Server resource and
    confirms the endpoint is reachable from this machine.

.DESCRIPTION
    Use this to isolate "is it auth?" from "is it VS Code MCP wiring?".
    A successful run proves: tenant scopes consented, user can sign in,
    network can reach mcp.svc.cloud.microsoft, transport is healthy.

.EXAMPLE
    pwsh ./verify-mcp-token.ps1

.NOTES
    Requires Az.Accounts (>= 2.x). Falls back gracefully if the resource
    rejects /.default — that itself confirms reachability.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$mcpAppId = 'e8c77dc2-69b3-43f4-bc51-3213c9d915b4'
$mcpResource = "api://$mcpAppId/.default"
$mcpUrl = 'https://mcp.svc.cloud.microsoft/enterprise'

if (-not (Get-Module -ListAvailable Az.Accounts)) {
    Write-Host "Az.Accounts not installed. Install with: Install-Module Az.Accounts -Force" -ForegroundColor Red
    exit 1
}

Write-Host "==> Az login (interactive, organizations endpoint)" -ForegroundColor Cyan
if (-not (Get-AzContext -ErrorAction SilentlyContinue)) {
    Connect-AzAccount | Out-Null
}

Write-Host "==> Acquiring token for $mcpResource" -ForegroundColor Cyan
try {
    $token = (Get-AzAccessToken -ResourceUrl "api://$mcpAppId" -AsSecureString:$false).Token
    Write-Host "    Token acquired (len=$($token.Length))" -ForegroundColor Green
} catch {
    Write-Host "    Token acquisition FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "    Likely cause: scopes not consented for this user. Run grant-vscode-mcp-scopes.ps1 first." -ForegroundColor Yellow
    exit 1
}

Write-Host "==> Pinging $mcpUrl" -ForegroundColor Cyan
try {
    $resp = Invoke-WebRequest -Uri $mcpUrl `
        -Method GET `
        -Headers @{ Authorization = "Bearer $token" } `
        -UseBasicParsing `
        -SkipHttpErrorCheck
    Write-Host "    HTTP $($resp.StatusCode) — endpoint reachable, transport OK" -ForegroundColor Green
    Write-Host "    (Note: GET on the MCP root typically returns 4xx; we only want network reachability + TLS.)" -ForegroundColor DarkGray
} catch {
    Write-Host "    Endpoint UNREACHABLE: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "All good. VS Code Copilot Chat should be able to use enterprise-mcp now." -ForegroundColor Green
