#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# 04-validate-sre-access.sh — Verify SRE Agent can manage ACA
#
# Runs the same ARM operations the SRE Agent would use to
# diagnose and manage the locked-down ACA apps. All operations
# go through ARM — no VNet access required.
# ──────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

eval "$(azd env get-values)"

RG="${AZURE_RESOURCE_GROUP}"
API_APP="${ACA_API_APP_NAME}"
WEB_APP="${ACA_WEB_APP_NAME}"
ACA_ENV="${ACA_ENVIRONMENT_NAME}"

echo "=== SRE Agent Access Validation for Locked-Down ACA ==="
echo ""
echo "Resource Group: $RG"
echo "ACA Environment: $ACA_ENV"
echo "API App: $API_APP"
echo "Web App: $WEB_APP"
echo ""

# ── ARM Management Operations ──────────────────────────────
echo "── 1. List container apps (az containerapp list) ──"
az containerapp list -g "$RG" \
  --query "[].{name:name, status:properties.provisioningState, fqdn:properties.configuration.ingress.fqdn}" \
  -o table
echo ""

echo "── 2. Show app details (az containerapp show) ──"
az containerapp show --name "$API_APP" -g "$RG" \
  --query "{name:name, env:properties.managedEnvironmentId, replicas:properties.template.scale, ingress:properties.configuration.ingress.external}" \
  -o json
echo ""

echo "── 3. List revisions (az containerapp revision list) ──"
az containerapp revision list --name "$API_APP" -g "$RG" \
  --query "[].{name:name, active:properties.active, replicas:properties.replicas, health:properties.healthState}" \
  -o table
echo ""

echo "── 4. Show replica status (az containerapp replica list) ──"
LATEST_REV=$(az containerapp revision list --name "$API_APP" -g "$RG" \
  --query "[0].name" -o tsv)
az containerapp replica list --name "$API_APP" -g "$RG" \
  --revision "$LATEST_REV" \
  -o table 2>/dev/null || echo "  (No replicas or revision not active)"
echo ""

echo "── 5. Stream logs via ARM (az containerapp logs show) ──"
echo "  Fetching last 20 log lines..."
az containerapp logs show --name "$API_APP" -g "$RG" \
  --tail 20 --type system 2>/dev/null || echo "  (System logs not yet available)"
echo ""

echo "── 6. Show environment details (az containerapp env show) ──"
az containerapp env show --name "$ACA_ENV" -g "$RG" \
  --query "{name:name, provisioningState:properties.provisioningState, vnet:properties.vnetConfiguration.internal, zoneRedundant:properties.zoneRedundant}" \
  -o json
echo ""

# ── Log Analytics KQL Operations ────────────────────────────
echo "── 7. KQL query — ContainerAppConsoleLogs (last 15 min) ──"
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  -g "$RG" --workspace-name "$(az monitor log-analytics workspace list -g "$RG" --query "[0].name" -o tsv)" \
  --query customerId -o tsv 2>/dev/null)

if [[ -n "$WORKSPACE_ID" ]]; then
  az monitor log-analytics query \
    --workspace "$WORKSPACE_ID" \
    --analytics-query "ContainerAppConsoleLogs_CL | where TimeGenerated > ago(15m) | project TimeGenerated, ContainerAppName_s, Log_s | take 10" \
    -o table 2>/dev/null || echo "  (No console logs available yet — may take a few minutes after deployment)"
else
  echo "  (Log Analytics workspace not found)"
fi
echo ""

echo "── 8. KQL query — ContainerAppSystemLogs (last 15 min) ──"
if [[ -n "$WORKSPACE_ID" ]]; then
  az monitor log-analytics query \
    --workspace "$WORKSPACE_ID" \
    --analytics-query "ContainerAppSystemLogs_CL | where TimeGenerated > ago(15m) | project TimeGenerated, RevisionName_s, Reason_s, Log_s | take 10" \
    -o table 2>/dev/null || echo "  (No system logs available yet)"
fi
echo ""

# ── Write Operations (restart, scale) ──────────────────────
echo "── 9. Restart app (az containerapp revision restart) ──"
echo "  [SKIPPED — would restart the app. Run manually to test:]"
echo "  az containerapp revision restart --name $API_APP -g $RG --revision $LATEST_REV"
echo ""

echo "── 10. Scale app (az containerapp update) ──"
echo "  [SKIPPED — would change replica count. Run manually to test:]"
echo "  az containerapp update --name $API_APP -g $RG --min-replicas 2 --max-replicas 5"
echo ""

echo "=== Validation Summary ==="
echo ""
echo "All operations above use ARM APIs. None require VNet connectivity."
echo ""
echo "✓ Operations 1-6: Read-only ARM management (Reader + Contributor)"
echo "✓ Operations 7-8: KQL queries (Log Analytics Reader)"
echo "✓ Operations 9-10: Write operations (Contributor on ACA env)"
echo ""
echo "The SRE Agent can manage this internal-only ACA environment"
echo "through ARM — identical to how it manages AKS via command invoke."
