#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# 03-trigger-incident.sh — Trigger a test incident on ACA
#
# Deploys a broken revision to simulate a crash loop, then
# verifies the SRE Agent can detect and diagnose it through ARM.
#
# Usage:
#   ./scripts/03-trigger-incident.sh          # Deploy broken revision
#   ./scripts/03-trigger-incident.sh --fix    # Roll back to healthy
# ──────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

eval "$(azd env get-values)"

RG="${AZURE_RESOURCE_GROUP}"
API_APP="${ACA_API_APP_NAME}"

if [[ "${1:-}" == "--fix" ]]; then
  echo "=== Rolling back to healthy revision ==="
  
  # Get the latest healthy revision
  HEALTHY_REV=$(az containerapp revision list --name "$API_APP" -g "$RG" \
    --query "[?properties.healthState=='Healthy'].name | [0]" -o tsv)
  
  if [[ -z "$HEALTHY_REV" ]]; then
    echo "No healthy revision found. Redeploying from ACR..."
    az containerapp update \
      --name "$API_APP" \
      --resource-group "$RG" \
      --image "${ACR_LOGIN_SERVER}/grocery-api:latest"
  else
    echo "Activating healthy revision: $HEALTHY_REV"
    az containerapp ingress traffic set \
      --name "$API_APP" \
      --resource-group "$RG" \
      --revision-weight "$HEALTHY_REV=100"
  fi
  
  echo "=== Rollback complete ==="
  exit 0
fi

echo "=== Triggering test incident on ACA ==="
echo ""
echo "Deploying a broken revision (bad image tag) to simulate crash loop..."

# Create a new revision with a bad image — this will fail to pull
# and cause the revision to enter a ProvisioningFailed state.
az containerapp update \
  --name "$API_APP" \
  --resource-group "$RG" \
  --image "${ACR_LOGIN_SERVER}/grocery-api:broken-tag-does-not-exist" \
  --no-wait

echo ""
echo "Broken revision deployed. Waiting 30 seconds for failure to propagate..."
sleep 30

echo ""
echo "=== Current revision status ==="
az containerapp revision list --name "$API_APP" -g "$RG" \
  --query "[].{name:name, active:properties.active, replicas:properties.replicas, health:properties.healthState, created:properties.createdTime}" \
  -o table

echo ""
echo "=== SRE Agent test commands ==="
echo "Now point the SRE Agent at resource group '$RG' and ask it to:"
echo "  - 'What container apps are running and what is their health status?'"
echo "  - 'Show me the latest revision status for the API app'"
echo "  - 'Check the system logs for any provisioning failures'"
echo "  - 'What went wrong with the latest deployment?'"
echo ""
echo "To fix: ./scripts/03-trigger-incident.sh --fix"
