#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# 05-trigger-incident.sh — Deploy CrashLoopBackOff workload to fire alert
#
# Deploys grocery-api-crash.yaml (a busybox pod that exits immediately).
# The pod-restart alert fires after ~5 minutes once Container Insights
# reports >3 restarts.
#
# Usage:
#   cd aks-private-testbed
#   ./scripts/05-trigger-incident.sh          # deploy crasher
#   ./scripts/05-trigger-incident.sh cleanup  # remove crasher
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTBED_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CRASH_MANIFEST="${TESTBED_DIR}/k8s/grocery-api-crash.yaml"
CRASH_MANIFEST_TMP="/tmp/grocery-api-crash.yaml"

log()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()   { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
fail() { echo -e "\033[1;31m[FAIL]\033[0m  $*"; exit 1; }

command -v az &>/dev/null || fail "Azure CLI not found."

cd "${TESTBED_DIR}"

log "Reading azd outputs..."
RG=$(azd env get-values       | grep ^AZURE_RESOURCE_GROUP | cut -d= -f2 | tr -d '"')
AKS_NAME=$(azd env get-values | grep ^AKS_CLUSTER_NAME     | cut -d= -f2 | tr -d '"')

[[ -z "${RG}" ]]       && fail "AZURE_RESOURCE_GROUP not found. Run 01-provision.sh first."
[[ -z "${AKS_NAME}" ]] && fail "AKS_CLUSTER_NAME not found. Run 01-provision.sh first."

# Copy to /tmp with a fixed name so az aks command invoke mounts it predictably
cp "${CRASH_MANIFEST}" "${CRASH_MANIFEST_TMP}"

ACTION="${1:-deploy}"

if [[ "${ACTION}" == "cleanup" ]]; then
  log "Removing CrashLoopBackOff workload from cluster..."
  az aks command invoke \
    --resource-group "${RG}" \
    --name "${AKS_NAME}" \
    --command "kubectl delete -f grocery-api-crash.yaml --ignore-not-found" \
    --file "${CRASH_MANIFEST_TMP}" \
    --output json | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['logs'])"
  ok "Crasher removed."
else
  log "Deploying CrashLoopBackOff workload to grocery namespace..."
  az aks command invoke \
    --resource-group "${RG}" \
    --name "${AKS_NAME}" \
    --command "kubectl apply -f grocery-api-crash.yaml" \
    --file "${CRASH_MANIFEST_TMP}" \
    --output json | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['logs'])"

  ok "Crasher deployed."
  echo ""
  echo "  The pod will restart every ~5 seconds (exits with code 1)."
  echo "  The 'alert-pod-restarts' Log Analytics alert fires after ~5 minutes."
  echo ""
  echo "  Watch restart count:"
  echo "  az aks command invoke --resource-group ${RG} --name ${AKS_NAME} \\"
  echo "    --command 'kubectl get pods -n grocery -w'"
  echo ""
  echo "  When done:"
  echo "  ./scripts/05-trigger-incident.sh cleanup"
fi

rm -f "${CRASH_MANIFEST_TMP}"
