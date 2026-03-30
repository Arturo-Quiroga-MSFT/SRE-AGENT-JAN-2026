#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# 03-deploy-workload.sh — Deploy grocery-api to the private AKS cluster
#
# Uses `az aks command invoke` to apply K8s manifests without VPN or Bastion.
# The ACR_LOGIN_SERVER placeholder in grocery-api.yaml is replaced at runtime
# and written to /tmp/grocery-api.yaml so the mount path is predictable.
#
# Usage:
#   cd aks-private-testbed
#   ./scripts/03-deploy-workload.sh
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTBED_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
K8S_DIR="${TESTBED_DIR}/k8s"
MANIFEST_OUT="/tmp/grocery-api.yaml"   # fixed name → mounts as /mnt/grocery-api.yaml

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
[[ -z "${AKS_NAME}" ]]   && fail "AKS_CLUSTER_NAME not found. Run 01-provision.sh first."
[[ -z "${ACR_SERVER}" ]] && fail "ACR_LOGIN_SERVER not found. Run 01-provision.sh first."

log "Resource group : ${RG}"
log "AKS cluster    : ${AKS_NAME}"
log "ACR            : ${ACR_SERVER}"

# Substitute placeholder with real ACR login server
log "Rendering manifest with ACR image reference..."
sed "s|ACR_LOGIN_SERVER|${ACR_SERVER}|g" \
  "${K8S_DIR}/grocery-api.yaml" > "${MANIFEST_OUT}"

log "Applying manifest (namespace, deployment, service, HPA)..."
az aks command invoke \
  --resource-group "${RG}" \
  --name "${AKS_NAME}" \
  --command "kubectl apply -f grocery-api.yaml" \
  --file "${MANIFEST_OUT}" \
  --output json | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['logs']); sys.exit(r['exitCode'])"

log "Waiting 20 seconds for pods to schedule..."
sleep 20

log "Pod status:"
az aks command invoke \
  --resource-group "${RG}" \
  --name "${AKS_NAME}" \
  --command "kubectl get pods -n grocery -o wide" \
  --output json | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['logs'])"

rm -f "${MANIFEST_OUT}"

ok "grocery-api deployed successfully."
log "Run './scripts/04-rbac-setup.sh' to configure SRE Agent access."
