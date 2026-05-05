# Configure a Microsoft Entra role's PIM activation policy to require approval,
# so that a `selfActivate` request lands as `status=PendingApproval` (which is
# what the gap-filler `pim-mcp` server's `list_pending_pim_requests` tool
# filters for).
#
# Without this, most default policies auto-approve activation and the request
# goes straight to `Provisioned`, leaving the pim-mcp tool with an empty
# result set and no demo data.
#
# This script:
#   1. Resolves the role definition by display name (e.g. "Privileged Role Administrator").
#   2. Finds the unifiedRoleManagementPolicy scoped to that role at directory scope "/".
#   3. Updates the `Approval_EndUser_Assignment` rule:
#        - isApprovalRequired = $true
#        - primaryApprovers   = the user object ID(s) you supply
#   4. Prints a verification dump.
#
# IMPORTANT: PIM requires approvers OTHER than the requester. If you intend to
# self-activate as user X, pass approver(s) other than X via -ApproverObjectIds.
# (Otherwise X can self-approve and the request still skips `PendingApproval`.)
#
# Usage:
#   pwsh ./configure-pim-approval.ps1 -TenantId <tid> `
#        -RoleDisplayName "Privileged Role Administrator" `
#        -ApproverObjectIds @('<user-or-group-oid-1>','<user-or-group-oid-2>')
#
#   # Dry-run (show current policy, no changes):
#   pwsh ./configure-pim-approval.ps1 -TenantId <tid> -RoleDisplayName "Privileged Role Administrator" -WhatIf
#
# Requires:
#   Install-Module Microsoft.Graph -Scope CurrentUser
#
# References:
#   https://learn.microsoft.com/en-us/graph/api/resources/unifiedrolemanagementpolicyapprovalrule
#   https://learn.microsoft.com/en-us/graph/api/unifiedrolemanagementpolicyrule-update

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string]   $TenantId,
    [Parameter(Mandatory)] [string]   $RoleDisplayName,
    [string[]] $ApproverObjectIds,
    [ValidateSet('User','Group')] [string] $ApproverType = 'User'
)

$ErrorActionPreference = 'Stop'

# --- 1. Prereqs ---------------------------------------------------------------

$requiredModules = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Identity.Governance')
foreach ($m in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $m)) {
        Write-Host "Installing module $m ..." -ForegroundColor Yellow
        Install-Module $m -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module $m -ErrorAction Stop
}

# --- 2. Connect ---------------------------------------------------------------

# RoleManagementPolicy.ReadWrite.Directory is required to update PIM policies.
$scopes = @('RoleManagementPolicy.ReadWrite.Directory', 'RoleManagement.Read.Directory', 'Directory.Read.All')
Write-Host "Connecting to Microsoft Graph (tenant $TenantId) ..." -ForegroundColor Cyan
Connect-MgGraph -TenantId $TenantId -Scopes $scopes -NoWelcome | Out-Null

# --- 3. Resolve role definition ----------------------------------------------

$role = Get-MgRoleManagementDirectoryRoleDefinition -Filter "displayName eq '$RoleDisplayName'" -ErrorAction Stop | Select-Object -First 1
if (-not $role) { throw "Role '$RoleDisplayName' not found." }
Write-Host "Role: $($role.DisplayName)  id=$($role.Id)" -ForegroundColor Green

# --- 4. Find the role-management policy assignment for this role at scope '/'

# PolicyAssignments map (scope, role) -> policyId. We need the policyId for
# directory scope '/' and this roleDefinitionId.
$assignment = Get-MgPolicyRoleManagementPolicyAssignment `
    -Filter "scopeId eq '/' and scopeType eq 'DirectoryRole' and roleDefinitionId eq '$($role.Id)'" `
    -ErrorAction Stop | Select-Object -First 1

if (-not $assignment) { throw "No PIM policy assignment found for role '$RoleDisplayName' at directory scope '/'." }
$policyId = $assignment.PolicyId
Write-Host "Policy: $policyId" -ForegroundColor Green

# --- 5. Pull current rules and find the end-user approval rule ---------------

$rules = Get-MgPolicyRoleManagementPolicyRule -UnifiedRoleManagementPolicyId $policyId
$approvalRule = $rules | Where-Object { $_.Id -eq 'Approval_EndUser_Assignment' } | Select-Object -First 1
if (-not $approvalRule) { throw "Rule 'Approval_EndUser_Assignment' not found on policy $policyId." }

Write-Host "`n=== Current Approval_EndUser_Assignment rule ===" -ForegroundColor Cyan
$approvalRule.AdditionalProperties | ConvertTo-Json -Depth 10 | Out-Host

if (-not $ApproverObjectIds -or $ApproverObjectIds.Count -eq 0) {
    Write-Host "`nNo -ApproverObjectIds supplied — printing current state only (no changes)." -ForegroundColor Yellow
    return
}

# --- 6. Build updated rule body ----------------------------------------------

# odata type for approver collection
$approverOdataType = if ($ApproverType -eq 'Group') { '#microsoft.graph.groupMembers' } else { '#microsoft.graph.singleUser' }

# Build primaryApprovers array. For singleUser entries each approver is a
# separate object with userId; for groupMembers it's groupId per object.
$primaryApprovers = @()
foreach ($oid in $ApproverObjectIds) {
    if ($ApproverType -eq 'Group') {
        $primaryApprovers += @{ '@odata.type' = $approverOdataType; groupId = $oid }
    } else {
        $primaryApprovers += @{ '@odata.type' = $approverOdataType; userId  = $oid }
    }
}

$body = @{
    '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyApprovalRule'
    id            = 'Approval_EndUser_Assignment'
    target        = @{
        '@odata.type'      = '#microsoft.graph.unifiedRoleManagementPolicyRuleTarget'
        caller             = 'EndUser'
        operations         = @('All')
        level              = 'Assignment'
        inheritableSettings = @()
        enforcedSettings    = @()
    }
    setting = @{
        isApprovalRequired               = $true
        isApprovalRequiredForExtension   = $false
        isRequestorJustificationRequired = $true
        approvalMode                     = 'SingleStage'
        approvalStages                   = @(
            @{
                approvalStageTimeOutInDays      = 1
                isApproverJustificationRequired = $true
                escalationTimeInMinutes         = 0
                isEscalationEnabled             = $false
                primaryApprovers                = $primaryApprovers
                escalationApprovers             = @()
            }
        )
    }
}

# --- 7. Apply -----------------------------------------------------------------

if ($PSCmdlet.ShouldProcess("policy $policyId / rule Approval_EndUser_Assignment", "Set isApprovalRequired=true with $($primaryApprovers.Count) approver(s)")) {
    Update-MgPolicyRoleManagementPolicyRule `
        -UnifiedRoleManagementPolicyId $policyId `
        -UnifiedRoleManagementPolicyRuleId 'Approval_EndUser_Assignment' `
        -BodyParameter $body | Out-Null
    Write-Host "Updated." -ForegroundColor Green
}

# --- 8. Verify ---------------------------------------------------------------

$verify = Get-MgPolicyRoleManagementPolicyRule `
    -UnifiedRoleManagementPolicyId $policyId `
    -UnifiedRoleManagementPolicyRuleId 'Approval_EndUser_Assignment'
Write-Host "`n=== Updated Approval_EndUser_Assignment rule ===" -ForegroundColor Cyan
$verify.AdditionalProperties | ConvertTo-Json -Depth 10 | Out-Host

Write-Host "`nDone. Now run trigger-pim-activation.ps1 to submit a self-activate request." -ForegroundColor Green
Write-Host "If the requester is one of the approvers, PIM may still auto-approve — use a different identity." -ForegroundColor Yellow
