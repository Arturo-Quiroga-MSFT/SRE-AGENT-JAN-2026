#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# 02-build-push.sh — Build grocery-api image and push to ACR
#
# Reads ACR name from azd env outputs (no manual env var needed).
# AKS nodes pull the image over the outbound LB — no private endpoint required.
#
# Usage:
#   cd aks-private-testbed
#   ./scripts/02-build-push.sh
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTBED_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${TESTBED_DIR}/.." && pwd)"
API_DIR="${REPO_ROOT}/grocery-sre-demo/src/api"

log()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()   { echo -e "\033[1;32m[OK]\033[0m    $*"; }
fail() { echo -e "\033[1;31m[FAIL]\033[0m  $*"; exit 1; }

command -v az     &>/dev/null || fail "Azure CLI not found."
command -v docker &>/dev/null || fail "Docker not found."

cd "${TESTBED_DIR}"

log "Reading azd outputs..."
ACR_SERVER=$(azd env get-values | grep ^ACR_LOGIN_SERVER | cut -d= -f2 | tr -d '"')
ACR_NAME=$(azd env get-values   | grep ^ACR_NAME         | cut -d= -f2 | tr -d '"')

[[ -z "${ACR_SERVER}" ]] && fail "ACR_LOGIN_SERVER not found in azd env. Run 01-provision.sh first."

IMAGE_TAG="${ACR_SERVER}/grocery-api:latest"

log "Logging in to ACR: ${ACR_NAME}"
az acr login --name "${ACR_NAME}"

log "Building grocery-api image (linux/amd64) → ${IMAGE_TAG}"
docker build \
  --platform linux/amd64 \
  -t "${IMAGE_TAG}" \
  "${API_DIR}"

log "Pushing image..."
docker push "${IMAGE_TAG}"

ok "Image pushed: ${IMAGE_TAG}"
log "Run './scripts/03-deploy-workload.sh' next."
