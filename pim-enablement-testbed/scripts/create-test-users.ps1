# Create the two test users needed for end-to-end PIM enablement testing.
#
# Creates:
#   - pim-requester@<tenant>  (will self-activate a PIM-eligible role)
#   - pim-approver@<tenant>   (will be in primaryApprovers of the role policy)
#
# Run as: Operator (your admin user with User.ReadWrite.All)
#
# Usage:
#   pwsh ./create-test-users.ps1 -TenantId <tid>
#
# Idempotent: re-running will skip users that already exist.

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string] $TenantId,

    # Initial password. The script forces a password change on first sign-in.
    [Parameter()] [string] $InitialPassword = 'TestP@ssw0rd!2026',

    # Domain suffix. Auto-detected from the signed-in tenant if omitted.
    [Parameter()] [string] $DomainSuffix
)

$ErrorActionPreference = 'Stop'

# --- Modules ---------------------------------------------------------------
# Import explicitly so we don't depend on auto-loading (Get-MgDomain lives
# in Microsoft.Graph.Identity.DirectoryManagement).
foreach ($mod in @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Users',
    'Microsoft.Graph.Identity.DirectoryManagement'
)) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        throw "Required module '$mod' is not installed. Run: Install-Module Microsoft.Graph -Scope CurrentUser"
    }
    Import-Module $mod -ErrorAction Stop | Out-Null
}

# --- Connect ---------------------------------------------------------------
Write-Host "==> Connecting to Microsoft Graph (TenantId=$TenantId)"
Connect-MgGraph -TenantId $TenantId -Scopes 'User.ReadWrite.All','Directory.Read.All' -NoWelcome | Out-Null
$ctx = Get-MgContext
Write-Host "    Signed in as: $($ctx.Account)"

# --- Resolve domain suffix -------------------------------------------------
if (-not $DomainSuffix) {
    try {
        $defaultDomain = (Get-MgDomain -ErrorAction Stop | Where-Object { $_.IsDefault }).Id
    } catch {
        Write-Warning "Get-MgDomain failed ($($_.Exception.Message)); falling back to signed-in user's UPN suffix."
        $defaultDomain = $null
    }
    if (-not $defaultDomain -and $ctx.Account -match '@(.+)$') {
        $defaultDomain = $Matches[1]
    }
    if (-not $defaultDomain) {
        throw "Could not auto-detect default domain. Pass -DomainSuffix."
    }
    $DomainSuffix = $defaultDomain
}
Write-Host "    Using domain suffix: $DomainSuffix"

# --- Users to create -------------------------------------------------------
$users = @(
    @{
        MailNickname  = 'pim-requester'
        DisplayName   = 'PIM Test Requester'
        GivenName     = 'PIM'
        Surname       = 'Requester'
        Role          = 'Submits PIM activation requests'
    },
    @{
        MailNickname  = 'pim-approver'
        DisplayName   = 'PIM Test Approver'
        GivenName     = 'PIM'
        Surname       = 'Approver'
        Role          = 'Approves PIM activation requests'
    }
)

# --- Create or skip --------------------------------------------------------
$results = @()
foreach ($u in $users) {
    $upn = "$($u.MailNickname)@$DomainSuffix"
    Write-Host ""
    Write-Host "==> $upn  ($($u.Role))"

    $existing = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "    Already exists (objectId=$($existing.Id)) — skipping create."
        $results += [pscustomobject]@{
            Upn       = $upn
            ObjectId  = $existing.Id
            Status    = 'Existing'
            Password  = '(unchanged)'
        }
        continue
    }

    if ($PSCmdlet.ShouldProcess($upn, "Create user")) {
        $passwordProfile = @{
            ForceChangePasswordNextSignIn = $true
            Password                      = $InitialPassword
        }

        $newUser = New-MgUser `
            -AccountEnabled `
            -DisplayName $u.DisplayName `
            -MailNickname $u.MailNickname `
            -UserPrincipalName $upn `
            -GivenName $u.GivenName `
            -Surname $u.Surname `
            -PasswordProfile $passwordProfile `
            -UsageLocation 'US'

        Write-Host "    Created (objectId=$($newUser.Id))"
        $results += [pscustomobject]@{
            Upn       = $upn
            ObjectId  = $newUser.Id
            Status    = 'Created'
            Password  = $InitialPassword
        }
    }
}

# --- Summary ---------------------------------------------------------------
Write-Host ""
Write-Host "============================================================"
Write-Host "Test users ready"
Write-Host "============================================================"
$results | Format-Table -AutoSize

Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Sign in to https://portal.azure.com once as each user to set a real password."
Write-Host "  2. Capture the ObjectIds above for the test scripts:"
Write-Host "       Requester ObjectId  -> use as -PrincipalUpn in assign-pim-eligibility.ps1"
Write-Host "       Approver  ObjectId  -> use as -ApproverObjectIds in configure-pim-approval.ps1"
Write-Host ""
Write-Host "  3. Run the E2E test sequence per test-results-May-5-2026.md"
