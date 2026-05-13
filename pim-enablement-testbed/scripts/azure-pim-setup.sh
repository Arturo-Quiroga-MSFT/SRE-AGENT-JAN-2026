#!/usr/bin/env bash
# azure-pim-setup.sh — PIM-on-Azure-Resources setup for Wave B "Approve" path
#
# Run this as a user holding User Access Administrator (or Owner) on the
# subscription, AND with permission to manage PIM policies (Privileged Role
# Administrator at tenant scope, OR User Access Administrator scoped above
# the target resource).
#
# What it does (idempotent):
#   1. Creates the target resource group (if missing).
#   2. Resolves requester + approver UPNs to Entra object IDs.
#   3. Patches the PIM role-management policy for `Reader` at the RG scope:
#        - isApprovalRequired      = true
#        - approvalMode            = SingleStage
#        - primaryApprovers        = [pim-approver]
#        - requestor justification = required
#   4. Creates an `AdminAssign` roleEligibilityScheduleRequest granting
#      `pim-requester` permanent eligibility for `Reader` at the RG scope.
#   5. Prints the IDs needed by `azure-pim-activate.sh`.
#
# Usage:
#   ./azure-pim-setup.sh \
#       [SUBSCRIPTION_ID=7a28b21e-0d3e-4435-a686-d92889d4ee96] \
#       [LOCATION=eastus2] \
#       [RG_NAME=rg-pim-testbed] \
#       [REQUESTER_UPN=pim-requester@MngEnvMCAP094150.onmicrosoft.com] \
#       [APPROVER_UPN=pim-approver@MngEnvMCAP094150.onmicrosoft.com] \
#       [ROLE_NAME=Reader]
#
# Outputs (printed and also written to ./.azure-pim-setup.env for the
# activate script to consume):
#   SUBSCRIPTION_ID
#   RG_NAME
#   SCOPE                       (the full ARM scope string)
#   ROLE_DEFINITION_ID          (the built-in role's GUID)
#   ROLE_DEFINITION_PATH        (the full /subscriptions/.../roleDefinitions/<guid> form)
#   REQUESTER_OID
#   APPROVER_OID
#   ELIGIBILITY_SCHEDULE_ID     (the GUID activate.sh links against)

set -euo pipefail

SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-7a28b21e-0d3e-4435-a686-d92889d4ee96}"
LOCATION="${LOCATION:-eastus2}"
RG_NAME="${RG_NAME:-rg-pim-testbed}"
REQUESTER_UPN="${REQUESTER_UPN:-pim-requester@MngEnvMCAP094150.onmicrosoft.com}"
APPROVER_UPN="${APPROVER_UPN:-pim-approver@MngEnvMCAP094150.onmicrosoft.com}"
ROLE_NAME="${ROLE_NAME:-Reader}"

SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}"
ENV_FILE="$(cd "$(dirname "$0")" && pwd)/.azure-pim-setup.env"

bold()  { printf "\033[1m%s\033[0m\n" "$*"; }
info()  { printf "\033[36m%s\033[0m\n" "$*"; }
ok()    { printf "\033[32m%s\033[0m\n" "$*"; }
warn()  { printf "\033[33m%s\033[0m\n" "$*"; }

require() { command -v "$1" >/dev/null || { echo "missing dependency: $1" >&2; exit 1; }; }
require az
require jq

bold "==> Step 0: Confirm az login context"
az account set --subscription "$SUBSCRIPTION_ID"
SIGNED_IN=$(az account show --query user.name -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
info "    signed in as: $SIGNED_IN"
info "    tenant:       $TENANT_ID"
info "    subscription: $SUBSCRIPTION_ID"

bold "==> Step 1: Ensure resource group $RG_NAME exists"
if az group show -n "$RG_NAME" >/dev/null 2>&1; then
  ok "    RG already exists"
else
  az group create -n "$RG_NAME" -l "$LOCATION" \
    --tags purpose=pim-testbed managed-by=azure-pim-setup.sh wave=B >/dev/null
  ok "    RG created in $LOCATION"
fi

bold "==> Step 2: Resolve principal object IDs"
REQUESTER_OID=$(az ad user show --id "$REQUESTER_UPN" --query id -o tsv)
APPROVER_OID=$(az ad user show --id "$APPROVER_UPN" --query id -o tsv)
[[ -n "$REQUESTER_OID" ]] || { echo "could not resolve REQUESTER_UPN $REQUESTER_UPN" >&2; exit 1; }
[[ -n "$APPROVER_OID"  ]] || { echo "could not resolve APPROVER_UPN $APPROVER_UPN" >&2; exit 1; }
info "    requester: $REQUESTER_UPN -> $REQUESTER_OID"
info "    approver:  $APPROVER_UPN -> $APPROVER_OID"

bold "==> Step 3: Resolve role definition ($ROLE_NAME)"
ROLE_JSON=$(az role definition list --name "$ROLE_NAME" --scope "/subscriptions/${SUBSCRIPTION_ID}" -o json)
ROLE_DEFINITION_ID=$(echo "$ROLE_JSON" | jq -r '.[0].name')
ROLE_DEFINITION_PATH=$(echo "$ROLE_JSON" | jq -r '.[0].id')
[[ -n "$ROLE_DEFINITION_ID" && "$ROLE_DEFINITION_ID" != "null" ]] \
  || { echo "could not resolve role $ROLE_NAME" >&2; exit 1; }
info "    role definition: $ROLE_DEFINITION_ID"
info "    role path:       $ROLE_DEFINITION_PATH"

bold "==> Step 4: Find the PIM role-management policy assignment for $ROLE_NAME at $SCOPE"
# Policy assignments live on the scope. Filter atScope() returns inheritable
# assignments; we need the one whose roleDefinitionId points at our role.
POLICY_ASSIGNMENT=$(az rest --method get \
  --url "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/roleManagementPolicyAssignments?api-version=2020-10-01&\$filter=atScope()" \
  -o json)

POLICY_ID=$(echo "$POLICY_ASSIGNMENT" | jq -r --arg rid "$ROLE_DEFINITION_PATH" \
  '.value[] | select(.properties.roleDefinitionId==$rid) | .properties.policyId' | head -1)

if [[ -z "$POLICY_ID" || "$POLICY_ID" == "null" ]]; then
  echo "could not find roleManagementPolicyAssignment for $ROLE_NAME at $SCOPE" >&2
  echo "raw response:" >&2
  echo "$POLICY_ASSIGNMENT" | jq . >&2
  exit 1
fi
info "    policy id: $POLICY_ID"

bold "==> Step 5: Patch the policy: require approval, set $APPROVER_UPN as approver"
# Read current policy, replace the Approval_EndUser_Assignment rule, PATCH it back.
CURRENT_POLICY=$(az rest --method get \
  --url "https://management.azure.com${POLICY_ID}?api-version=2020-10-01" -o json)

NEW_APPROVAL_RULE=$(jq -n \
  --arg oid "$APPROVER_OID" \
  --arg upn "$APPROVER_UPN" \
  '{
    id: "Approval_EndUser_Assignment",
    ruleType: "RoleManagementPolicyApprovalRule",
    target: {
      caller: "EndUser",
      operations: ["All"],
      level: "Assignment",
      inheritableSettings: [],
      enforcedSettings: []
    },
    setting: {
      isApprovalRequired: true,
      isApprovalRequiredForExtension: false,
      isRequestorJustificationRequired: true,
      approvalMode: "SingleStage",
      approvalStages: [{
        approvalStageTimeOutInDays: 1,
        isApproverJustificationRequired: true,
        escalationTimeInMinutes: 0,
        primaryApprovers: [{
          "@odata.type": "#Microsoft.Graph.singleUser",
          id: $oid,
          userType: "User",
          description: $upn
        }],
        isEscalationEnabled: false,
        escalationApprovers: []
      }]
    }
  }')

PATCHED_RULES=$(echo "$CURRENT_POLICY" | jq --argjson newrule "$NEW_APPROVAL_RULE" '
  .properties.rules |= map(if .id == "Approval_EndUser_Assignment" then $newrule else . end)
  | .properties.rules
')

PATCH_BODY=$(jq -n --argjson rules "$PATCHED_RULES" '{ properties: { rules: $rules } }')

az rest --method patch \
  --url "https://management.azure.com${POLICY_ID}?api-version=2020-10-01" \
  --headers "Content-Type=application/json" \
  --body "$PATCH_BODY" >/dev/null

ok "    policy patched: approval required, approver = $APPROVER_UPN"

bold "==> Step 6: Admin-assign $REQUESTER_UPN as Eligible for $ROLE_NAME at $SCOPE"
ELIGIBILITY_REQUEST_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

ELIG_BODY=$(jq -n \
  --arg principal "$REQUESTER_OID" \
  --arg roledef "$ROLE_DEFINITION_PATH" \
  --arg start "$START_TIME" \
  '{
    properties: {
      principalId:      $principal,
      roleDefinitionId: $roledef,
      requestType:      "AdminAssign",
      justification:    "Wave B testbed: granting Reader eligibility on rg-pim-testbed for end-to-end Approve-path validation",
      scheduleInfo: {
        startDateTime: $start,
        expiration:    { type: "AfterDuration", duration: "P365D" }
      }
    }
  }')

# Check if eligibility already exists; if so, just look it up.
EXISTING=$(az rest --method get \
  --url "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/roleEligibilitySchedules?api-version=2020-10-01&\$filter=assignedTo('${REQUESTER_OID}')" \
  -o json 2>/dev/null || echo '{"value":[]}')

EXISTING_SCHED_ID=$(echo "$EXISTING" | jq -r --arg rid "$ROLE_DEFINITION_PATH" \
  '.value[]? | select(.properties.roleDefinitionId==$rid and (.properties.scope|ascii_downcase)==("'"${SCOPE}"'"|ascii_downcase)) | .name' | head -1)

if [[ -n "$EXISTING_SCHED_ID" && "$EXISTING_SCHED_ID" != "null" ]]; then
  ok "    eligibility already exists: $EXISTING_SCHED_ID (skipping AdminAssign)"
  ELIGIBILITY_SCHEDULE_ID="$EXISTING_SCHED_ID"
else
  ELIG_RESPONSE=$(az rest --method put \
    --url "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/roleEligibilityScheduleRequests/${ELIGIBILITY_REQUEST_ID}?api-version=2020-10-01" \
    --headers "Content-Type=application/json" \
    --body "$ELIG_BODY" -o json)
  ELIG_STATUS=$(echo "$ELIG_RESPONSE" | jq -r '.properties.status')
  ELIGIBILITY_SCHEDULE_ID=$(echo "$ELIG_RESPONSE" | jq -r '.properties.targetRoleEligibilityScheduleId // .name')
  info "    request status: $ELIG_STATUS"
  ok   "    eligibility schedule id: $ELIGIBILITY_SCHEDULE_ID"
fi

bold "==> Step 7: Persist context to $ENV_FILE"
cat > "$ENV_FILE" <<EOF
# Generated by azure-pim-setup.sh on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Source this file before running azure-pim-activate.sh.
export SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
export TENANT_ID="$TENANT_ID"
export RG_NAME="$RG_NAME"
export SCOPE="$SCOPE"
export ROLE_NAME="$ROLE_NAME"
export ROLE_DEFINITION_ID="$ROLE_DEFINITION_ID"
export ROLE_DEFINITION_PATH="$ROLE_DEFINITION_PATH"
export REQUESTER_UPN="$REQUESTER_UPN"
export REQUESTER_OID="$REQUESTER_OID"
export APPROVER_UPN="$APPROVER_UPN"
export APPROVER_OID="$APPROVER_OID"
export ELIGIBILITY_SCHEDULE_ID="$ELIGIBILITY_SCHEDULE_ID"
EOF
ok "    wrote $ENV_FILE"

bold ""
bold "==> Done. Next steps:"
echo "  1. (Optional) Switch the SCRUM Jira ticket to status To Do, type Task."
echo "  2. Sign the requester in:"
echo "       az logout && az login --tenant $TENANT_ID --username $REQUESTER_UPN"
echo "  3. Source the env file and run the activate script:"
echo "       source $ENV_FILE"
echo "       TICKET_NUMBER=SCRUM-XX ./pim-enablement-testbed/scripts/azure-pim-activate.sh"
echo "  4. The activate script prints the requestId to feed into fire-sre-agent-trigger.sh."
