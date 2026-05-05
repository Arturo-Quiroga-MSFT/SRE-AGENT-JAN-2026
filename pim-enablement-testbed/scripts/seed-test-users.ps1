# Seed test users and groups for the PIM Enablement testbed.
# PLACEHOLDER — fill in tenant + group/user data, then run with:
#   pwsh ./seed-test-users.ps1

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $TenantId,
    [Parameter()] [string] $UserPasswordProfile = 'TempP@ssw0rd!2026'
)

$ErrorActionPreference = 'Stop'

# Required modules
# Install-Module Microsoft.Graph -Scope CurrentUser

Connect-MgGraph -TenantId $TenantId -Scopes 'User.ReadWrite.All','Group.ReadWrite.All','RoleManagement.ReadWrite.Directory'

# TODO: define your test users here
$testUsers = @(
    @{ DisplayName = 'PIM Test SRE 1'; Mail = 'pim.test.sre1'; }
    @{ DisplayName = 'PIM Test SRE 2'; Mail = 'pim.test.sre2'; }
)

# TODO: define on-call groups
$testGroups = @(
    'oncall-prod-test',
    'oncall-platform-test'
)

Write-Host "Provisioning test users..."
foreach ($u in $testUsers) {
    # TODO: New-MgUser ...
    Write-Host "  (stub) would create user: $($u.DisplayName)"
}

Write-Host "Provisioning test groups..."
foreach ($g in $testGroups) {
    # TODO: New-MgGroup ...
    Write-Host "  (stub) would create group: $g"
}

# TODO: assign each test user as PIM-eligible to a Reader role on the test RG.
#       New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest ...

Write-Host "Done (scaffold)."
