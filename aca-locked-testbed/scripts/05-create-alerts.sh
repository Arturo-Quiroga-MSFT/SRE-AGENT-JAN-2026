#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# 05-create-alerts.sh — Create Log Analytics alert rules
#
# Must be run AFTER the container apps have been running for a
# few minutes so the Log Analytics tables exist.
#
# The tables (ContainerAppConsoleLogs, ContainerAppSystemLogs)
# are created by Azure only after the first log entries arrive.
# ──────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

eval "$(azd env get-values)"

RG="${AZURE_RESOURCE_GROUP}"
LA_NAME=$(az monitor log-analytics workspace list -g "$RG" --query "[0].name" -o tsv)
LA_ID=$(az monitor log-analytics workspace show -g "$RG" --workspace-name "$LA_NAME" --query id -o tsv)
LOCATION="${AZURE_LOCATION}"

echo "=== Creating ACA Alert Rules ==="
echo "Resource Group: $RG"
echo "Log Analytics: $LA_NAME"
echo ""

# Check if tables exist
WORKSPACE_ID=$(az monitor log-analytics workspace show -g "$RG" --workspace-name "$LA_NAME" --query customerId -o tsv)
echo "Checking if Log Analytics tables exist..."

TABLE_CHECK=$(az monitor log-analytics query \
  --workspace "$WORKSPACE_ID" \
  --analytics-query "ContainerAppSystemLogs | take 1" \
  -o json 2>&1 || true)

if echo "$TABLE_CHECK" | grep -q "Failed to resolve"; then
  echo "ERROR: Log Analytics tables don't exist yet."
  echo "Wait a few minutes for the container apps to generate logs, then retry."
  exit 1
fi

echo "Tables exist. Creating alert rules..."

# Alert 1: Failed revisions
echo ""
echo "1/2 — Creating failed-revisions alert..."
az monitor scheduled-query create \
  --name "alert-aca-failed-revisions" \
  --resource-group "$RG" \
  --scopes "$LA_ID" \
  --condition "count 'ContainerAppSystemLogs | where Reason_s in (\"ProvisioningFailed\", \"Degraded\", \"ContainerCrashing\") | summarize Count = count() by RevisionName_s, Reason_s' > 0" \
  --description "Container App revision failed to provision or is in a degraded state" \
  --severity 1 \
  --evaluation-frequency 5m \
  --window-size 15m \
  --action-groups "" \
  2>/dev/null && echo "  Created." || echo "  Failed or already exists."

# Alert 2: Container restarts / errors
echo ""
echo "2/2 — Creating container-restarts alert..."
az monitor scheduled-query create \
  --name "alert-aca-container-restarts" \
  --resource-group "$RG" \
  --scopes "$LA_ID" \
  --condition "count 'ContainerAppConsoleLogs | where Log_s contains \"error\" or Log_s contains \"crash\" | summarize ErrorCount = count() by bin(TimeGenerated, 5m), ContainerAppName_s | where ErrorCount > 5' > 0" \
  --description "Container app replicas producing frequent errors — possible crash loop" \
  --severity 2 \
  --evaluation-frequency 5m \
  --window-size 15m \
  --action-groups "" \
  2>/dev/null && echo "  Created." || echo "  Failed or already exists."

echo ""
echo "=== Alert creation complete ==="
