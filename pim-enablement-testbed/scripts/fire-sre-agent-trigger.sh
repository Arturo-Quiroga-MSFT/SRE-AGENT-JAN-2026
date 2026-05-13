#!/usr/bin/env bash
# fire-sre-agent-trigger.sh
#
# POSTs a push-mode payload to the `pim-request-created` HTTP trigger on the
# `aq-main` SRE Agent. Mints an ARM bearer token whose audience is the SRE
# Agent app ID (59f0a04a-b322-4310-adc9-39ac41e9631e) — the trigger rejects
# anything else with `{"error":"unauthorized"}`.
#
# Usage:
#   ./fire-sre-agent-trigger.sh                       # uses defaults below (F2 re-run)
#   ./fire-sre-agent-trigger.sh path/to/payload.json  # custom payload file
#   PAYLOAD='{"requestId":"...","ticketNumber":"SCRUM-25",...}' ./fire-sre-agent-trigger.sh
#
# Override any input via env var (see DEFAULTS section). All values land in the
# JSON body verbatim; the agent reads `source` to tag the run, `justification`
# becomes the audit-comment header, `requestId` is the PIM request to validate.
#
# Prereqs: `az login` against the tenant that owns the SRE Agent (`aq-main`
# is in tenant `a172a259-b1c7-4944-b2e1-6d551f954711`).

set -euo pipefail

# ---- Trigger endpoint (constant for aq-main / pim-request-created) ----------
TRIGGER_URL="${TRIGGER_URL:-https://aq-main--2cdce1d3.daa74423.eastus2.azuresre.ai/api/v1/httptriggers/trigger/2c2f62e3-773f-48d1-a4e5-199fc692c4f9}"
SRE_AGENT_APP_ID="${SRE_AGENT_APP_ID:-59f0a04a-b322-4310-adc9-39ac41e9631e}"

# ---- DEFAULTS (F2 re-run fixture — SCRUM-26 / Done) -------------------------
REQUEST_ID="${REQUEST_ID:-502e2ccc-8f6d-4f95-8912-e7c6b2b62fd8}"
PRINCIPAL_UPN="${PRINCIPAL_UPN:-pim-requester@MngEnvMCAP094150.onmicrosoft.com}"
PRINCIPAL_ID="${PRINCIPAL_ID:-8a986e7c-f44b-44e0-a8a2-cfc1071faf92}"
ROLE_DISPLAY_NAME="${ROLE_DISPLAY_NAME:-Privileged Role Administrator}"
ROLE_DEF_ID="${ROLE_DEF_ID:-e8611ab8-c189-46e8-94e1-60213ab1f814}"
SCOPE="${SCOPE:-/}"
TICKET_NUMBER="${TICKET_NUMBER:-SCRUM-26}"
TICKET_SYSTEM="${TICKET_SYSTEM:-Jira}"
JUSTIFICATION="${JUSTIFICATION:-Wave B smoke F2 RE-RUN - validate v3 schema loaded (R001/R001b/R001c FAIL + R001d HumanReview + R003 v3 identity-map)}"
SOURCE="${SOURCE:-manual-curl-wave-b-f2-rerun}"
# durationHours: agent uses this as the R007 input when get_request_status
# returns 404 (ARM-scoped PIM requests aren't visible on the Graph endpoint).
# Must match what azure-pim-activate.sh actually submitted.
DURATION_HOURS="${DURATION_HOURS:-1}"

# ---- Build payload ----------------------------------------------------------
if [[ "${1:-}" != "" && -f "${1}" ]]; then
  PAYLOAD="$(cat "${1}")"
  echo "Using payload from file: ${1}"
elif [[ "${PAYLOAD:-}" != "" ]]; then
  echo "Using payload from \$PAYLOAD env var"
else
  PAYLOAD=$(cat <<JSON
{
  "requestId": "${REQUEST_ID}",
  "principalUpn": "${PRINCIPAL_UPN}",
  "principalId": "${PRINCIPAL_ID}",
  "roleDisplayName": "${ROLE_DISPLAY_NAME}",
  "roleDefinitionId": "${ROLE_DEF_ID}",
  "directoryScopeId": "${SCOPE}",
  "ticketNumber": "${TICKET_NUMBER}",
  "ticketSystem": "${TICKET_SYSTEM}",
  "justification": "${JUSTIFICATION}",
  "source": "${SOURCE}",
  "durationHours": ${DURATION_HOURS}
}
JSON
)
fi

# ---- Mint bearer token (ARM audience = SRE Agent app) -----------------------
echo "Minting bearer token (audience=${SRE_AGENT_APP_ID})..."
TOKEN=$(az account get-access-token \
  --resource "${SRE_AGENT_APP_ID}" \
  --query accessToken -o tsv 2>/dev/null) || {
    echo "ERROR: az account get-access-token failed. Run 'az login' first." >&2
    exit 1
  }
if [[ -z "${TOKEN}" ]]; then
  echo "ERROR: empty token returned." >&2
  exit 1
fi

# ---- Fire ------------------------------------------------------------------
echo "POST ${TRIGGER_URL}"
echo "Payload:"
echo "${PAYLOAD}" | jq . 2>/dev/null || echo "${PAYLOAD}"
echo

curl -sS -X POST "${TRIGGER_URL}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}" | jq .
