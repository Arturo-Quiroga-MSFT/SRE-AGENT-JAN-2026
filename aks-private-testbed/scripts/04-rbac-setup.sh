#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# 04-rbac-setup.sh — Grant SRE Agent Managed Identity access to the test bed
#
# Assigns four roles to the SRE Agent's Managed Identity:
#   1. AKS Contributor         — ARM-level ops (scale, upgrade, node pools)
#   2. AKS Cluster User        — az aks command invoke (kubectl ops)
#   3. Log Analytics Reader     — KQL / Container Insights queries
#   4. Reader (resource group)  — az aks show, az monitor, az resource list
#
# Usage:
#   cd aks-private-testbed
#   export SRE_AGENT_MI="<object-id-of-sre-agent-managed-identity>"
#   ./scripts/04-rbac-setup.sh
#
# Where to find the SRE Agent Managed Identity Object ID:
#   Azure Portal → AI Foundry → Your SRE Agent → Identity → Object (principal) ID
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTBED_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

log()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()   { echo -e "\033[1;32m[OK]\033[0m    $*"; }
fail() { echo -e "\033[1;31m[FAIL]\033[0m  $*"; exit 1; }

command -v az &>/dev/null || fail "Azure CLI not found."

if [[ -z "${SRE_AGENT_MI:-}" ]]; then
  fail "SRE_AGENT_MI is not set.\n\nExport it first:\n  export SRE_AGENT_MI=\"<object-id>\""
fi

cd "${TESTBED_DIR}"

log "Reading azd outputs..."
RG=$(azd env get-values       | grep ^AZURE_RESOURCE_GROUP | cut -d= -f2 | tr -d '"')
AKS_ID=$(azd env get-values   | grep ^AKS_CLUSTER_ID       | cut -d= -f2 | tr -d '"')
LOG_WS_RID=$(azd env get-values | grep ^LOG_ANALYTICS_RESOURCE_ID | cut -d= -f2 | tr -d '"')
SUB_ID=$(az account show --query id -o tsv)

[[ -z "${RG}" ]]    && fail "AZURE_RESOURCE_GROUP not found. Run 01-provision.sh first."
[[ -z "${AKS_ID}" ]] && fail "AKS_CLUSTER_ID not found. Run 01-provision.sh first."

RG_SCOPE="/subscriptions/${SUB_ID}/resourceGroups/${RG}"

log "Assigning roles to SRE Agent MI: ${SRE_AGENT_MI}"

log "1/4 — AKS Contributor (ARM-level management)..."
az role assignment create \
  --assignee "${SRE_AGENT_MI}" \
  --role "Azure Kubernetes Service Contributor Role" \
  --scope "${AKS_ID}"

log "2/4 — AKS Cluster User (az aks command invoke / kubectl)..."
az role assignment create \
  --assignee "${SRE_AGENT_MI}" \
  --role "Azure Kubernetes Service Cluster User Role" \
  --scope "${AKS_ID}"

log "3/4 — Log Analytics Reader (KQL / Container Insights)..."
az role assignment create \
  --assignee "${SRE_AGENT_MI}" \
  --role "Log Analytics Reader" \
  --scope "${LOG_WS_RID}"

log "4/4 — Reader on resource group (az aks show, az monitor, az resource list)..."
az role assignment create \
  --assignee "${SRE_AGENT_MI}" \
  --role "Reader" \
  --scope "${RG_SCOPE}"

ok "All role assignments created."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SRE Agent test prompts (use in AI Foundry SRE Agent chat)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  ARM-level (no kubectl, no VNet access needed):"
echo "  → Show me the status of AKS cluster ${AKS_ID##*/} in resource group ${RG}"
echo "  → List all node pools and their current replica counts"
echo "  → What Azure Monitor alerts are active on the AKS cluster?"
echo ""
echo "  Log Analytics / Container Insights:"
echo "  → Query Log Analytics for grocery namespace pods that restarted more"
echo "    than 3 times in the last hour"
echo "  → Show ContainerLog errors from the grocery-api pod in the last 30 minutes"
echo ""
echo "  In-cluster via az aks command invoke:"
echo "  → Using az aks command invoke on cluster ${AKS_ID##*/},"
echo "    run: kubectl get pods -n grocery -o wide"
echo ""
echo "  Trigger incident:"
echo "  → ./scripts/05-trigger-incident.sh"
echo ""
