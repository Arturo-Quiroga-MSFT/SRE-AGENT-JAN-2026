#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# 01-provision.sh — Provision the locked-down ACA testbed
#
# Usage:
#   cd aca-locked-testbed
#   ./scripts/01-provision.sh
#
# Prerequisites:
#   - az CLI logged in
#   - azd CLI installed
#   - SRE_AGENT_PRINCIPAL_ID env var set (optional, can add later)
# ──────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "=== ACA Locked-Down Testbed — Provision ==="

# Check if azd environment is initialized
if ! azd env list 2>/dev/null | grep -q .; then
  echo "No azd environment found. Initializing..."
  azd init --no-prompt
fi

# Set SRE Agent principal ID if available
if [[ -n "${SRE_AGENT_PRINCIPAL_ID:-}" ]]; then
  echo "Setting SRE Agent principal ID: ${SRE_AGENT_PRINCIPAL_ID}"
  azd env set SRE_AGENT_PRINCIPAL_ID "$SRE_AGENT_PRINCIPAL_ID"
else
  echo "⚠ SRE_AGENT_PRINCIPAL_ID not set. SRE Agent roles will not be assigned."
  echo "  Set it later with: azd env set SRE_AGENT_PRINCIPAL_ID <principal-id>"
  azd env set SRE_AGENT_PRINCIPAL_ID ""
fi

echo ""
echo "Provisioning infrastructure..."
azd provision

echo ""
echo "=== Provisioning complete ==="
echo ""
echo "Outputs:"
azd env get-values | grep -E "^(ACA_|ACR_|LOG_|VNET_|AZURE_)"
echo ""
echo "Next steps:"
echo "  1. Build and push the grocery-api image: ./scripts/02-deploy-app.sh"
echo "  2. Trigger a test incident: ./scripts/03-trigger-incident.sh"
echo "  3. Point SRE Agent at the resource group"
