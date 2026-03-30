#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# 06-scenarios.sh — Deploy / cleanup incident simulation scenarios A-D
#
# Each scenario targets the private AKS cluster via az aks command invoke.
# Manifests live in k8s/scenario-{a,b,c,d}-*.yaml
#
# Usage:
#   cd aks-private-testbed
#   ./scripts/06-scenarios.sh deploy  a          # deploy scenario A only
#   ./scripts/06-scenarios.sh deploy  b          # deploy scenario B only
#   ./scripts/06-scenarios.sh deploy  all        # deploy all four
#   ./scripts/06-scenarios.sh cleanup a          # remove scenario A
#   ./scripts/06-scenarios.sh cleanup all        # remove all four
#   ./scripts/06-scenarios.sh status             # show live pod/cronjob list
#
# Scenario summary:
#   A - OOMKill simulator      (64 Mi limit, Python allocates past it)
#   B - Flaky HTTP service     (30% HTTP 500, + load generator client)
#   C - CPU spike              (1.8 vCPU burn loop, fires Node CPU alert)
#   D - Failing CronJob        (every 5 min, fails on odd minutes)
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTBED_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
K8S_DIR="${TESTBED_DIR}/k8s"
TMP_DIR="/tmp/sre-scenarios"

log()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()   { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
fail() { echo -e "\033[1;31m[FAIL]\033[0m  $*"; exit 1; }
sep()  { echo "------------------------------------------------------------------------"; }

# ── Scenario metadata (bash 3.2 compatible — no associative arrays) ───────────
scenario_file() {
  case "$1" in
    a) echo "scenario-a-oomkill.yaml" ;;
    b) echo "scenario-b-flaky-service.yaml" ;;
    c) echo "scenario-c-cpu-spike.yaml" ;;
    d) echo "scenario-d-failing-cronjob.yaml" ;;
    *) fail "Unknown scenario '$1'. Valid: a b c d all" ;;
  esac
}

scenario_desc() {
  case "$1" in
    a) echo "OOMKill simulator     - Python exceeds 64 Mi limit repeatedly" ;;
    b) echo "Flaky HTTP service    - 30% HTTP 500 + load generator" ;;
    c) echo "CPU spike             - 1.8 vCPU burn loop (fires Node CPU alert)" ;;
    d) echo "Failing CronJob       - every 5 min, fails ~50% of runs" ;;
  esac
}

scenario_prompt() {
  case "$1" in
    a) echo "A pod in the grocery namespace is getting OOMKilled repeatedly. Investigate memory usage, identify the container limit, and recommend a fix." ;;
    b) echo "The flaky-service in the grocery namespace is generating errors. Inspect container logs, calculate the error rate, and recommend remediation." ;;
    c) echo "The Node CPU alert fired on the AKS cluster. Investigate which workload is responsible, show resource usage trends, and recommend action." ;;
    d) echo "There are failed jobs in the grocery namespace. Investigate the failure pattern from logs and events, and recommend whether this is transient or systemic." ;;
  esac
}

# ── Read azd environment ──────────────────────────────────────────────────────
command -v az &>/dev/null || fail "Azure CLI not found."
cd "${TESTBED_DIR}"

log "Reading azd outputs..."
RG=$(azd env get-values       | grep ^AZURE_RESOURCE_GROUP | cut -d= -f2 | tr -d '"')
AKS_NAME=$(azd env get-values | grep ^AKS_CLUSTER_NAME     | cut -d= -f2 | tr -d '"')

[[ -z "${RG}" ]]       && fail "AZURE_RESOURCE_GROUP not found. Run 01-provision.sh first."
[[ -z "${AKS_NAME}" ]] && fail "AKS_CLUSTER_NAME not found. Run 01-provision.sh first."

mkdir -p "${TMP_DIR}"

# ── Helper: invoke kubectl against private cluster ────────────────────────────
invoke() {
  local cmd="$1"
  local file="$2"
  az aks command invoke \
    --resource-group "${RG}" \
    --name "${AKS_NAME}" \
    --command "${cmd}" \
    --file "${file}" \
    --output json | python3 -c "
import sys, json
r = json.load(sys.stdin)
print(r.get('logs', ''))
code = r.get('exitCode', 0)
if code != 0:
    sys.exit(code)
"
}

invoke_nofile() {
  local cmd="$1"
  az aks command invoke \
    --resource-group "${RG}" \
    --name "${AKS_NAME}" \
    --command "${cmd}" \
    --output json | python3 -c "
import sys, json
r = json.load(sys.stdin)
print(r.get('logs', ''))
"
}

# ── deploy one scenario ───────────────────────────────────────────────────────
deploy_scenario() {
  local key="$1"
  local file
  file="$(scenario_file "$key")"
  local src="${K8S_DIR}/${file}"
  local tmp="${TMP_DIR}/${file}"

  [[ ! -f "$src" ]] && fail "Manifest not found: ${src}"
  cp "${src}" "${tmp}"

  sep
  log "Deploying scenario ${key}: $(scenario_desc "$key")"
  invoke "kubectl apply -f ${file}" "${tmp}"
  ok "Scenario ${key} deployed."
  echo ""
  echo "  SRE Agent prompt:"
  echo "  $(scenario_prompt "$key")"
  echo ""
}

# ── cleanup one scenario ──────────────────────────────────────────────────────
cleanup_scenario() {
  local key="$1"
  local file
  file="$(scenario_file "$key")"
  local src="${K8S_DIR}/${file}"
  local tmp="${TMP_DIR}/${file}"

  if [[ ! -f "$src" ]]; then
    warn "Manifest not found: ${src} -- skipping"
    return 0
  fi
  cp "${src}" "${tmp}"

  sep
  log "Removing scenario ${key}: $(scenario_desc "$key")"
  invoke "kubectl delete -f ${file} --ignore-not-found" "${tmp}"

  # CronJob scenario: also purge leftover completed/failed job pods
  if [[ "$key" == "d" ]]; then
    invoke_nofile "kubectl delete jobs -n grocery -l scenario=failing-cronjob --ignore-not-found"
  fi

  ok "Scenario ${key} removed."
}

# ── status ────────────────────────────────────────────────────────────────────
show_status() {
  sep
  log "Live pod list in grocery namespace:"
  invoke_nofile "kubectl get pods -n grocery -o wide"
  sep
  log "CronJobs:"
  invoke_nofile "kubectl get cronjobs -n grocery"
  sep
  log "Recent jobs:"
  invoke_nofile "kubectl get jobs -n grocery"
}

# ── Parse arguments ───────────────────────────────────────────────────────────
ACTION="${1:-}"
TARGET="${2:-}"

if [[ -z "$ACTION" ]]; then
  echo "Usage: $0 deploy|cleanup|status  [a|b|c|d|all]"
  exit 1
fi

if [[ "$ACTION" == "status" ]]; then
  show_status
  exit 0
fi

if [[ -z "$TARGET" ]]; then
  echo "Usage: $0 ${ACTION} [a|b|c|d|all]"
  exit 1
fi

KEYS=()
if [[ "$TARGET" == "all" ]]; then
  KEYS=(a b c d)
else
  KEYS=("$TARGET")
fi

for k in "${KEYS[@]}"; do
  [[ -z "${SCENARIO_FILE[$k]+_}" ]] && fail "Unknown scenario '${k}'. Valid: a b c d all"
  if [[ "$ACTION" == "deploy" ]]; then
    deploy_scenario "$k"
  elif [[ "$ACTION" == "cleanup" ]]; then
    cleanup_scenario "$k"
  else
    fail "Unknown action '${ACTION}'. Valid: deploy cleanup status"
  fi
done

sep
ok "Done."
