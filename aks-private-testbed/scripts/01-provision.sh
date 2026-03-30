#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# 01-provision.sh — Provision Azure infrastructure via azd
#
# Creates: VNet, Private AKS cluster, ACR, Log Analytics, alert rules
# Time: ~10-14 minutes (AKS dominates)
#
# Usage:
#   cd aks-private-testbed
#   ./scripts/01-provision.sh
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTBED_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

log()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()   { echo -e "\033[1;32m[OK]\033[0m    $*"; }
fail() { echo -e "\033[1;31m[FAIL]\033[0m  $*"; exit 1; }

log "Checking prerequisites..."
command -v az  &>/dev/null || fail "Azure CLI not found. Install: https://aka.ms/install-azure-cli"
command -v azd &>/dev/null || fail "azd not found. Install: https://aka.ms/azd"

cd "${TESTBED_DIR}"

log "Provisioning Azure infrastructure (VNet, private AKS, ACR, Log Analytics)..."
log "This typically takes 10-14 minutes."
azd provision

ok "Infrastructure provisioned successfully."
log "Run './scripts/02-build-push.sh' next."
