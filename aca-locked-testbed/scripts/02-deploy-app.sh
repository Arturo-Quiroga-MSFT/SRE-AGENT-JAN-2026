#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# 02-deploy-app.sh — Build and deploy the grocery-api to ACA
#
# Builds the grocery-api image in ACR and updates the container
# app to use it. Uses az containerapp update (ARM operation)
# which works regardless of the internal-only VNet configuration.
# ──────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "=== Deploy grocery-api to locked-down ACA ==="

# Load azd environment values
eval "$(azd env get-values)"

RG="${AZURE_RESOURCE_GROUP}"
ACR_NAME="${ACR_NAME}"
API_APP="${ACA_API_APP_NAME}"
WEB_APP="${ACA_WEB_APP_NAME}"

# Source path for the grocery API
API_SRC="../grocery-sre-demo/src/api"
WEB_SRC="../grocery-sre-demo/src/web"

if [[ ! -d "$API_SRC" ]]; then
  echo "ERROR: grocery-api source not found at $API_SRC"
  echo "Make sure grocery-sre-demo is in the parent directory."
  exit 1
fi

echo ""
echo "1/4 — Building API image in ACR ($ACR_NAME)..."
az acr build \
  --registry "$ACR_NAME" \
  --image grocery-api:latest \
  --file "$API_SRC/Dockerfile" \
  "$API_SRC"

echo ""
echo "2/4 — Building Web image in ACR ($ACR_NAME)..."
az acr build \
  --registry "$ACR_NAME" \
  --image grocery-web:latest \
  --file "$WEB_SRC/Dockerfile" \
  "$WEB_SRC"

echo ""
echo "3/4 — Updating API container app ($API_APP)..."
az containerapp update \
  --name "$API_APP" \
  --resource-group "$RG" \
  --image "${ACR_LOGIN_SERVER}/grocery-api:latest"

echo ""
echo "4/4 — Updating Web container app ($WEB_APP)..."
az containerapp update \
  --name "$WEB_APP" \
  --resource-group "$RG" \
  --image "${ACR_LOGIN_SERVER}/grocery-web:latest"

echo ""
echo "=== Deployment complete ==="
echo ""
echo "Verifying revision status..."
az containerapp revision list --name "$API_APP" -g "$RG" \
  --query "[].{name:name, active:properties.active, replicas:properties.replicas, health:properties.healthState}" \
  -o table

echo ""
echo "Note: The apps are internal-only. They are NOT reachable from the internet."
echo "      Management operations (restart, logs, revision list) work through ARM."
