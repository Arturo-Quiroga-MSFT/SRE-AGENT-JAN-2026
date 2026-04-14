#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# 01-provision.sh — Provision the locked-down AKS testbed via azd
#
# Usage:
#   cd aks-locked-testbed
#   azd auth login
#   azd init -e sre-locked
#   azd env set AZURE_LOCATION westus2
#   ./scripts/01-provision.sh
# ──────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."

log()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()   { echo -e "\033[1;32m[OK]\033[0m    $*"; }
fail() { echo -e "\033[1;31m[FAIL]\033[0m  $*"; exit 1; }

command -v azd &>/dev/null || fail "azd CLI not found. Install: https://aka.ms/azd"

log "Provisioning AKS locked-down testbed..."
azd provision

log "Reading outputs..."
RG=$(azd env get-values | grep ^AZURE_RESOURCE_GROUP | cut -d= -f2 | tr -d '"')
AKS_NAME=$(azd env get-values | grep ^AKS_CLUSTER_NAME | cut -d= -f2 | tr -d '"')
ACR_SERVER=$(azd env get-values | grep ^ACR_LOGIN_SERVER | cut -d= -f2 | tr -d '"')

ok "Provisioned successfully!"
echo ""
log "Cluster:  ${AKS_NAME}"
log "RG:       ${RG}"
log "ACR:      ${ACR_SERVER}"
echo ""
log "Next steps:"
log "  1. Add your IP to authorized ranges:"
log "     MY_IP=\$(curl -s ifconfig.me)"
log "     az aks update -g ${RG} -n ${AKS_NAME} --api-server-authorized-ip-ranges \"\${MY_IP}/32\""
log ""
log "  2. Add SRE Agent role assignments:"
log "     ./scripts/02-assign-sre-agent.sh <sre-agent-principal-id>"
log ""
log "  3. Deploy the grocery-api workload:"
log "     ./scripts/03-deploy-workload.sh"
