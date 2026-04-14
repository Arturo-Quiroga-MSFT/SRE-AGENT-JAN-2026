#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# 02-assign-sre-agent.sh — Assign the 4 Zafin-pattern roles to
# the SRE Agent managed identity.
#
# Roles (from partner-context/Zafin-AKSDetails/SRE_MI_Roles.json):
#   1. Reader (built-in) → resource group scope
#   2. AKS ReadOnly Command Invoke (custom) → AKS scope
#   3. Log Analytics Reader (built-in) → workspace scope
#   4. Azure Kubernetes Service RBAC Reader (built-in) → AKS scope
#
# Usage:
#   cd aks-locked-testbed
#   ./scripts/02-assign-sre-agent.sh <sre-agent-principal-id>
#
# For our agent (aq-main): f54ae888-64d7-451d-a03d-66060918c1a8
# ──────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."

log()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()   { echo -e "\033[1;32m[OK]\033[0m    $*"; }
fail() { echo -e "\033[1;31m[FAIL]\033[0m  $*"; exit 1; }

SRE_PRINCIPAL_ID="${1:-}"
[[ -z "${SRE_PRINCIPAL_ID}" ]] && fail "Usage: $0 <sre-agent-principal-id>"

log "Reading azd outputs..."
RG=$(azd env get-values | grep ^AZURE_RESOURCE_GROUP | cut -d= -f2 | tr -d '"')
AKS_NAME=$(azd env get-values | grep ^AKS_CLUSTER_NAME | cut -d= -f2 | tr -d '"')
CUSTOM_ROLE_ID=$(azd env get-values | grep ^SRE_AGENT_CUSTOM_ROLE_ID | cut -d= -f2 | tr -d '"')
LAW_ID=$(azd env get-values | grep ^LOG_ANALYTICS_RESOURCE_ID | cut -d= -f2 | tr -d '"')

AKS_ID=$(az aks show -g "${RG}" -n "${AKS_NAME}" --query id -o tsv)
RG_ID=$(az group show -n "${RG}" --query id -o tsv)

log "Assigning 4 roles to SRE Agent principal: ${SRE_PRINCIPAL_ID}"

log "1/4 Reader on resource group..."
az role assignment create \
  --assignee-object-id "${SRE_PRINCIPAL_ID}" \
  --assignee-principal-type ServicePrincipal \
  --role "Reader" \
  --scope "${RG_ID}" \
  --output none 2>/dev/null && ok "Reader assigned" || log "Already assigned or error"

log "2/4 AKS ReadOnly Command Invoke (custom) on AKS cluster..."
az role assignment create \
  --assignee-object-id "${SRE_PRINCIPAL_ID}" \
  --assignee-principal-type ServicePrincipal \
  --role "${CUSTOM_ROLE_ID}" \
  --scope "${AKS_ID}" \
  --output none 2>/dev/null && ok "Custom role assigned" || log "Already assigned or error"

log "3/4 Log Analytics Reader on workspace..."
az role assignment create \
  --assignee-object-id "${SRE_PRINCIPAL_ID}" \
  --assignee-principal-type ServicePrincipal \
  --role "Log Analytics Reader" \
  --scope "${LAW_ID}" \
  --output none 2>/dev/null && ok "Log Analytics Reader assigned" || log "Already assigned or error"

log "4/4 Azure Kubernetes Service RBAC Reader on AKS cluster..."
az role assignment create \
  --assignee-object-id "${SRE_PRINCIPAL_ID}" \
  --assignee-principal-type ServicePrincipal \
  --role "7f6c6a51-bcf8-42ba-9220-52d62157d7db" \
  --scope "${AKS_ID}" \
  --output none 2>/dev/null && ok "AKS RBAC Reader assigned" || log "Already assigned or error"

echo ""
ok "SRE Agent role assignments complete."
log "Verify with: az role assignment list --assignee ${SRE_PRINCIPAL_ID} --all -o table"
