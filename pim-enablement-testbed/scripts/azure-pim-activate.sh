#!/usr/bin/env bash
# azure-pim-activate.sh — submits a real SelfActivate PIM request against
# the Reader eligibility provisioned by azure-pim-setup.sh.
#
# RUN THIS AS THE REQUESTER. Before running:
#   az logout
#   az login --tenant $TENANT_ID --username $REQUESTER_UPN
#   source pim-enablement-testbed/scripts/.azure-pim-setup.env
#
# What it does:
#   1. Submits a roleAssignmentScheduleRequest with requestType=SelfActivate,
#      linked to the eligibility schedule from setup.
#   2. Polls until the request reaches a terminal state (PendingApproval is
#      the expected one because step 5 of setup configured the policy that way).
#   3. Prints the requestId, which you then feed into the SRE agent trigger:
#
#        REQUEST_ID=<printed-id> \
#        PRINCIPAL_UPN=$REQUESTER_UPN \
#        PRINCIPAL_ID=$REQUESTER_OID \
#        ROLE_DISPLAY_NAME=$ROLE_NAME \
#        ROLE_DEF_ID=$ROLE_DEFINITION_ID \
#        SCOPE=$SCOPE \
#        TICKET_NUMBER=$TICKET_NUMBER \
#        TICKET_SYSTEM=Jira \
#        JUSTIFICATION="$JUSTIFICATION" \
#        SOURCE="manual-azure-pim-real-activation-approve-path" \
#        ./pim-enablement-testbed/scripts/fire-sre-agent-trigger.sh
#
# Required env (load via `source .azure-pim-setup.env`):
#   SUBSCRIPTION_ID, RG_NAME, SCOPE, ROLE_DEFINITION_PATH, ROLE_DEFINITION_ID,
#   REQUESTER_UPN, REQUESTER_OID, ELIGIBILITY_SCHEDULE_ID
#
# Optional env (override defaults):
#   TICKET_NUMBER     -- Jira key (e.g. SCRUM-34). Required for R001 to PASS.
#   TICKET_SYSTEM     -- default "Jira"
#   DURATION_HOURS    -- default 1 (must be <= 8 to satisfy R007)
#   JUSTIFICATION     -- default "..."

set -euo pipefail

: "${SUBSCRIPTION_ID:?source pim-enablement-testbed/scripts/.azure-pim-setup.env first}"
: "${SCOPE:?source pim-enablement-testbed/scripts/.azure-pim-setup.env first}"
: "${ROLE_DEFINITION_PATH:?source pim-enablement-testbed/scripts/.azure-pim-setup.env first}"
: "${REQUESTER_UPN:?source pim-enablement-testbed/scripts/.azure-pim-setup.env first}"
: "${REQUESTER_OID:?source pim-enablement-testbed/scripts/.azure-pim-setup.env first}"
: "${ELIGIBILITY_SCHEDULE_ID:?source pim-enablement-testbed/scripts/.azure-pim-setup.env first}"

TICKET_NUMBER="${TICKET_NUMBER:?set TICKET_NUMBER=SCRUM-XX (required for R001 PASS)}"
TICKET_SYSTEM="${TICKET_SYSTEM:-Jira}"
DURATION_HOURS="${DURATION_HOURS:-1}"
JUSTIFICATION="${JUSTIFICATION:-Wave B real PIM activation: read-only investigation against rg-pim-testbed for ${TICKET_NUMBER}}"

bold()  { printf "\033[1m%s\033[0m\n" "$*"; }
info()  { printf "\033[36m%s\033[0m\n" "$*"; }
ok()    { printf "\033[32m%s\033[0m\n" "$*"; }
warn()  { printf "\033[33m%s\033[0m\n" "$*"; }

require() { command -v "$1" >/dev/null || { echo "missing dependency: $1" >&2; exit 1; }; }
require az
require jq
require uuidgen

bold "==> Verify az login context matches REQUESTER_UPN"
# pim-requester has no subscription RBAC (only the RG-scoped eligibility we
# just provisioned). The user signs in via:
#   az login --tenant $TENANT_ID --allow-no-subscriptions
# az account show in that state still returns the user identity, but
# subscriptions are empty. We do NOT call `az account set` -- instead we use
# `az rest` against the ARM management plane directly with the bearer token
# the user already has.
SIGNED_IN=$(az account show --query user.name -o tsv 2>/dev/null || echo "")
if [[ "$SIGNED_IN" != "$REQUESTER_UPN" ]]; then
  warn "    Currently signed in as: ${SIGNED_IN:-<none>}"
  warn "    Required:               $REQUESTER_UPN"
  echo  "    Run: az logout && az login --tenant \$TENANT_ID --allow-no-subscriptions"
  echo  "         (then sign in as $REQUESTER_UPN in the browser)"
  exit 1
fi
ok   "    signed in as $SIGNED_IN"

bold "==> Submit SelfActivate request"
REQUEST_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

ACTIVATE_BODY=$(jq -n \
  --arg principal "$REQUESTER_OID" \
  --arg roledef   "$ROLE_DEFINITION_PATH" \
  --arg linked    "$ELIGIBILITY_SCHEDULE_ID" \
  --arg start     "$START_TIME" \
  --arg duration  "PT${DURATION_HOURS}H" \
  --arg just      "$JUSTIFICATION" \
  --arg ticket    "$TICKET_NUMBER" \
  --arg sys       "$TICKET_SYSTEM" \
  '{
    properties: {
      principalId:      $principal,
      roleDefinitionId: $roledef,
      requestType:      "SelfActivate",
      linkedRoleEligibilityScheduleId: $linked,
      justification:    $just,
      scheduleInfo: {
        startDateTime: $start,
        expiration:    { type: "AfterDuration", duration: $duration }
      },
      ticketInfo: {
        ticketNumber: $ticket,
        ticketSystem: $sys
      }
    }
  }')

info "    request id:   $REQUEST_ID"
info "    scope:        $SCOPE"
info "    duration:     PT${DURATION_HOURS}H"
info "    ticket:       $TICKET_NUMBER ($TICKET_SYSTEM)"

# pim-requester has no subscription RBAC -- only the RG-scoped eligibility we
# just provisioned. `az rest` validates the subscription against the user's
# subscription list before sending and fails ("Subscription ... not found").
# Bypass by minting an ARM bearer token via `az account get-access-token` (which
# DOES work for tenant-level accounts) and POST/GET via curl directly.
ARM_TOKEN=$(az account get-access-token --resource https://management.azure.com/ --query accessToken -o tsv)
[[ -n "$ARM_TOKEN" ]] || { echo "could not mint ARM bearer token" >&2; exit 1; }

RESPONSE=$(curl -sS -X PUT \
  -H "Authorization: Bearer $ARM_TOKEN" \
  -H "Content-Type: application/json" \
  --data "$ACTIVATE_BODY" \
  "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/${REQUEST_ID}?api-version=2020-10-01")

INITIAL_STATUS=$(echo "$RESPONSE" | jq -r '.properties.status // (.error.code + ": " + .error.message)')
info "    initial status: $INITIAL_STATUS"

bold "==> Poll for terminal state (up to 60s)"
DEADLINE=$(($(date +%s) + 60))
LAST_STATUS="$INITIAL_STATUS"
while (( $(date +%s) < DEADLINE )); do
  sleep 3
  POLL=$(curl -sS \
    -H "Authorization: Bearer $ARM_TOKEN" \
    "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/${REQUEST_ID}?api-version=2020-10-01")
  LAST_STATUS=$(echo "$POLL" | jq -r '.properties.status // "Unknown"')
  printf "    status=%s\n" "$LAST_STATUS"
  case "$LAST_STATUS" in
    PendingApproval|Provisioned|Failed|Denied|Canceled|Revoked|Granted) break ;;
  esac
done

bold ""
bold "==> Result"
echo "    request id:    $REQUEST_ID"
echo "    final status:  $LAST_STATUS"

case "$LAST_STATUS" in
  PendingApproval)
    ok ""
    ok "    Request is PendingApproval. The pim-mcp tool list_pending_pim_requests"
    ok "    will now return this entry. Now fire the SRE agent trigger:"
    cat <<EOF

      REQUEST_ID="$REQUEST_ID" \\
      PRINCIPAL_UPN="$REQUESTER_UPN" \\
      PRINCIPAL_ID="$REQUESTER_OID" \\
      ROLE_DISPLAY_NAME="$ROLE_NAME" \\
      ROLE_DEF_ID="$ROLE_DEFINITION_ID" \\
      SCOPE="$SCOPE" \\
      TICKET_NUMBER="$TICKET_NUMBER" \\
      TICKET_SYSTEM="$TICKET_SYSTEM" \\
      JUSTIFICATION="$JUSTIFICATION" \\
      SOURCE="manual-azure-pim-real-activation-approve-path" \\
        ./pim-enablement-testbed/scripts/fire-sre-agent-trigger.sh

EOF
    ;;
  Provisioned|Granted)
    warn ""
    warn "    Request was auto-approved -- the policy patch in setup did not stick"
    warn "    or applied to the wrong rule. Check the role-management policy at $SCOPE."
    ;;
  *)
    warn ""
    warn "    Terminal status $LAST_STATUS. Inspect via:"
    echo  "      az rest --method get --url \"https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/${REQUEST_ID}?api-version=2020-10-01\""
    ;;
esac
