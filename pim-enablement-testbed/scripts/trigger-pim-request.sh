#!/usr/bin/env bash
# Trigger a synthetic PIM activation request against the test tenant.
# PLACEHOLDER — fill in $USER_OBJECT_ID, $ROLE_DEF_ID, and $SCOPE before running.

set -euo pipefail

USER_OBJECT_ID="${USER_OBJECT_ID:-PLACEHOLDER-user-object-id}"
ROLE_DEF_ID="${ROLE_DEF_ID:-acdd72a7-3385-48ef-bd42-f606fba81ae7}"  # Reader
SCOPE="${SCOPE:-/subscriptions/PLACEHOLDER-sub-id/resourceGroups/rg-pim-enablement-testbed}"
TICKET_NUMBER="${TICKET_NUMBER:-INC-DEMO-001}"
JUSTIFICATION="${JUSTIFICATION:-Synthetic activation for PIM Enablement testbed}"

echo "Submitting PIM activation request..."
echo "  user:   $USER_OBJECT_ID"
echo "  role:   $ROLE_DEF_ID"
echo "  scope:  $SCOPE"
echo "  ticket: $TICKET_NUMBER"

# TODO: replace with real Graph call once tenant is provisioned.
# az rest --method POST \
#   --uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleRequests" \
#   --headers "Content-Type=application/json" \
#   --body "{
#     \"action\": \"selfActivate\",
#     \"principalId\": \"$USER_OBJECT_ID\",
#     \"roleDefinitionId\": \"$ROLE_DEF_ID\",
#     \"directoryScopeId\": \"$SCOPE\",
#     \"justification\": \"$JUSTIFICATION\",
#     \"scheduleInfo\": {
#       \"startDateTime\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
#       \"expiration\": { \"type\": \"AfterDuration\", \"duration\": \"PT2H\" }
#     },
#     \"ticketInfo\": {
#       \"ticketNumber\": \"$TICKET_NUMBER\",
#       \"ticketSystem\": \"Jira\"
#     }
#   }"

echo "(stub) Activation request submitted."
