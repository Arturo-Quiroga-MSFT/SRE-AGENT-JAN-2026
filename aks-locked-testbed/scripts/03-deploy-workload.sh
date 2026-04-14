#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# 03-deploy-workload.sh — Deploy grocery-api to the locked-down AKS cluster
#
# Uses `az aks command invoke` to apply K8s manifests (works even
# when the API server has authorized IP restrictions).
#
# Usage:
#   cd aks-locked-testbed
#   ./scripts/03-deploy-workload.sh
# ──────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTBED_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# Reuse the same K8s manifests from aks-private-testbed
K8S_DIR="$(cd "${TESTBED_DIR}/../aks-private-testbed/k8s" && pwd)"
MANIFEST_OUT="/tmp/grocery-api.yaml"

log()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()   { echo -e "\033[1;32m[OK]\033[0m    $*"; }
fail() { echo -e "\033[1;31m[FAIL]\033[0m  $*"; exit 1; }

command -v az &>/dev/null || fail "Azure CLI not found."

cd "${TESTBED_DIR}"

log "Reading azd outputs..."
RG=$(azd env get-values       | grep ^AZURE_RESOURCE_GROUP | cut -d= -f2 | tr -d '"')
AKS_NAME=$(azd env get-values | grep ^AKS_CLUSTER_NAME     | cut -d= -f2 | tr -d '"')
ACR_SERVER=$(azd env get-values | grep ^ACR_LOGIN_SERVER   | cut -d= -f2 | tr -d '"')

[[ -z "${RG}" ]]         && fail "AZURE_RESOURCE_GROUP not found. Run 01-provision.sh first."
[[ -z "${AKS_NAME}" ]]   && fail "AKS_CLUSTER_NAME not found."
[[ -z "${ACR_SERVER}" ]] && fail "ACR_LOGIN_SERVER not found."

log "Resource group : ${RG}"
log "AKS cluster    : ${AKS_NAME}"
log "ACR            : ${ACR_SERVER}"

# Build image via ACR Tasks (server-side, avoids local Docker)
log "Building grocery-api image via ACR Tasks..."
az acr build \
  --registry "$(echo ${ACR_SERVER} | cut -d. -f1)" \
  --image grocery-api:latest \
  --file "${TESTBED_DIR}/../grocery-sre-demo/src/api/Dockerfile" \
  "${TESTBED_DIR}/../grocery-sre-demo/src/api" \
  --output none

ok "Image built and pushed to ${ACR_SERVER}/grocery-api:latest"

# Substitute placeholder with real ACR login server
log "Rendering manifest with ACR image reference..."
sed "s|ACR_LOGIN_SERVER|${ACR_SERVER}|g" \
  "${K8S_DIR}/grocery-api.yaml" > "${MANIFEST_OUT}"

log "Applying manifest via az aks command invoke..."
az aks command invoke \
  --resource-group "${RG}" \
  --name "${AKS_NAME}" \
  --command "kubectl apply -f grocery-api.yaml" \
  --file "${MANIFEST_OUT}" \
  -o yaml 2>/dev/null

log "Waiting 20 seconds for pods to schedule..."
sleep 20

log "Pod status:"
az aks command invoke \
  --resource-group "${RG}" \
  --name "${AKS_NAME}" \
  --command "kubectl get pods -n grocery -o wide" \
  -o yaml 2>/dev/null

rm -f "${MANIFEST_OUT}"

ok "grocery-api deployed successfully."
