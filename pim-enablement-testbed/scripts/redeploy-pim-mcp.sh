#!/usr/bin/env bash
# redeploy-pim-mcp.sh
#
# Build, push, and roll the `pim-mcp` Container App. One-shot for shipping a
# new pim-mcp version (e.g. 0.10.0 ARM tools — Wave C).
#
# Steps:
#   1. Discover ACR / ACA / MI / RG (overridable via env vars).
#   2. Read version from mcp-servers/pim-mcp/pyproject.toml.
#   3. `az acr build` → image `pim-mcp:<version>` (multi-arch friendly via ACR).
#   4. `az containerapp update --image ...` to roll a new revision.
#   5. `az containerapp revision restart` to flush the in-process Graph token
#      cache (pim-mcp 0.6.1+ caches by (client_id, resource); restarting
#      ensures any newly-granted appRoles take effect immediately).
#   6. (Optional, for Wave C) Grant the pim-mcp MI `Reader` on the testbed RG
#      so arm_get_request_status / arm_get_request_approver / arm_get_role_definition
#      can read PIM-on-Azure-resources data. Idempotent.
#   7. Health-check the /mcp endpoint and print the SRE-Agent re-registration hint.
#
# Required:
#   az login --tenant <tenant>  (CLI must have Contributor on the testbed RG).
#
# Optional env vars (defaults in DEFAULTS section):
#   ACR_NAME           - Azure Container Registry name (no .azurecr.io suffix).
#                        Auto-discovered if unset.
#   RG_NAME            - Resource group hosting the ACA. Default: rg-pim-enablement-testbed.
#   ACA_NAME           - Container App name. Default: ca-pimtest-pimmcp.
#   PIM_MCP_MI_NAME    - Managed Identity attached to the ACA. Default: mi-pimtest-agent.
#   ARM_PIM_RG         - RG to grant Reader on for ARM PIM tools. Default: rg-pim-testbed.
#                        Set to "" to skip step 6.
#   IMAGE_TAG          - Override the version tag. Default: read from pyproject.toml.
#   SKIP_BUILD         - 1 to skip step 3 (when image already pushed).
#   SKIP_ROLL          - 1 to skip steps 4-5.
#   SKIP_RBAC          - 1 to skip step 6.

set -euo pipefail

# ---- Resolve repo paths -----------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTBED_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PIM_MCP_DIR="${TESTBED_DIR}/mcp-servers/pim-mcp"
PYPROJECT="${PIM_MCP_DIR}/pyproject.toml"

# ---- DEFAULTS ---------------------------------------------------------------
RG_NAME="${RG_NAME:-rg-pim-enablement-testbed}"
ACA_NAME="${ACA_NAME:-ca-pimtest-pimmcp}"
PIM_MCP_MI_NAME="${PIM_MCP_MI_NAME:-mi-pimtest-agent}"
ARM_PIM_RG="${ARM_PIM_RG:-rg-pim-testbed}"

# ---- Helpers ----------------------------------------------------------------
info()  { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33m[warn]\033[0m %s\n" "$*" >&2; }
fatal() { printf "\033[1;31m[FATAL]\033[0m %s\n" "$*" >&2; exit 1; }

require_az_login() {
  local sub
  sub=$(az account show --query name -o tsv 2>/dev/null) || fatal "az not logged in. Run: az login"
  info "Azure CLI: subscription = ${sub}"
}

# ---- Step 0: prerequisites --------------------------------------------------
require_az_login
[[ -f "${PYPROJECT}" ]] || fatal "Cannot find ${PYPROJECT}"

# ---- Step 1: discover ACR if not provided -----------------------------------
if [[ -z "${ACR_NAME:-}" ]]; then
  info "Discovering ACR in ${RG_NAME}..."
  ACR_NAME=$(az acr list -g "${RG_NAME}" --query "[0].name" -o tsv 2>/dev/null || true)
  if [[ -z "${ACR_NAME}" ]]; then
    info "  no ACR in ${RG_NAME}; checking the ACA's current image..."
    current_image=$(az containerapp show -g "${RG_NAME}" -n "${ACA_NAME}" \
      --query "properties.template.containers[0].image" -o tsv 2>/dev/null || true)
    if [[ "${current_image}" =~ ^([^.]+)\.azurecr\.io/ ]]; then
      ACR_NAME="${BASH_REMATCH[1]}"
      info "  inferred ACR=${ACR_NAME} from current ACA image (${current_image})"
    else
      fatal "Could not auto-discover ACR. Set ACR_NAME explicitly."
    fi
  fi
fi
info "ACR: ${ACR_NAME}"

# ---- Step 2: read version ---------------------------------------------------
IMAGE_TAG="${IMAGE_TAG:-$(grep -E '^version\s*=' "${PYPROJECT}" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')}"
[[ -n "${IMAGE_TAG}" ]] || fatal "Could not parse version from ${PYPROJECT}"
IMAGE_REF="${ACR_NAME}.azurecr.io/pim-mcp:${IMAGE_TAG}"
info "Image: ${IMAGE_REF}"

# ---- Step 3: build + push via ACR Tasks (ARM64-friendly, no local docker) ---
if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  info "Building image with az acr build (this runs in ACR — no local docker needed)..."
  az acr build \
    -r "${ACR_NAME}" \
    -t "pim-mcp:${IMAGE_TAG}" \
    -t "pim-mcp:latest" \
    --file "${PIM_MCP_DIR}/Dockerfile" \
    "${PIM_MCP_DIR}"
else
  info "SKIP_BUILD=1 — skipping ACR build (assuming ${IMAGE_REF} already pushed)."
fi

# ---- Step 4-5: roll the Container App ---------------------------------------
if [[ "${SKIP_ROLL:-0}" != "1" ]]; then
  info "Updating Container App ${ACA_NAME} → ${IMAGE_REF}..."
  az containerapp update \
    -g "${RG_NAME}" \
    -n "${ACA_NAME}" \
    --image "${IMAGE_REF}" \
    --output none

  info "Restarting latest revision (flushes pim-mcp's in-process token cache)..."
  latest_rev=$(az containerapp revision list \
    -g "${RG_NAME}" \
    -n "${ACA_NAME}" \
    --query "sort_by([?properties.active], &properties.createdTime)[-1].name" -o tsv)
  if [[ -n "${latest_rev}" ]]; then
    az containerapp revision restart \
      -g "${RG_NAME}" \
      -n "${ACA_NAME}" \
      --revision "${latest_rev}" \
      --output none
    info "  restarted revision: ${latest_rev}"
  else
    warn "Could not resolve latest revision; skipping explicit restart (the update above already rolled a new revision)."
  fi
else
  info "SKIP_ROLL=1 — skipping ACA roll."
fi

# ---- Step 6: grant Reader on testbed RG so ARM tools work (Wave C 0.10.0) ---
if [[ "${SKIP_RBAC:-0}" != "1" && -n "${ARM_PIM_RG}" ]]; then
  info "Resolving pim-mcp MI principalId (${PIM_MCP_MI_NAME} in ${RG_NAME})..."
  mi_principal=$(az identity show -g "${RG_NAME}" -n "${PIM_MCP_MI_NAME}" \
    --query principalId -o tsv 2>/dev/null || true)
  if [[ -z "${mi_principal}" ]]; then
    warn "Could not resolve MI ${PIM_MCP_MI_NAME}. Skipping ARM RBAC grant. Set PIM_MCP_MI_NAME or grant Reader manually."
  else
    info "Granting Reader on /subscriptions/<sub>/resourceGroups/${ARM_PIM_RG} to ${mi_principal}..."
    sub_id=$(az account show --query id -o tsv)
    arm_scope="/subscriptions/${sub_id}/resourceGroups/${ARM_PIM_RG}"
    # Idempotent: az role assignment create is a no-op when assignment exists.
    az role assignment create \
      --assignee-object-id "${mi_principal}" \
      --assignee-principal-type ServicePrincipal \
      --role "Reader" \
      --scope "${arm_scope}" \
      --output none 2>&1 | grep -v "already exists" || true
    info "  grant complete (idempotent)."
  fi
else
  info "SKIP_RBAC=1 or ARM_PIM_RG empty — skipping ARM Reader grant."
fi

# ---- Step 7: health check + next-steps hint ---------------------------------
fqdn=$(az containerapp show -g "${RG_NAME}" -n "${ACA_NAME}" \
  --query "properties.configuration.ingress.fqdn" -o tsv 2>/dev/null || true)
if [[ -n "${fqdn}" ]]; then
  endpoint="https://${fqdn}/mcp"
  info "MCP endpoint: ${endpoint}"
  info "TLS reachability check..."
  if curl -fsSI --max-time 10 "${endpoint}" -o /dev/null 2>&1; then
    info "  ✓ TLS handshake OK"
  else
    warn "  TLS check returned non-2xx (the /mcp endpoint requires session init — this is normal). Proceeding."
  fi
else
  warn "Could not resolve ACA FQDN."
fi

cat <<EOF

\033[1;32m✓ pim-mcp ${IMAGE_TAG} is live.\033[0m

Next steps to surface the new tools to the SRE Agent:

  1. SRE Agent UI → MCP Servers → pim-mcp → Re-register / Refresh tools.
     (Foundry caches the tool list; a refresh picks up the three new
     ARM tools added in 0.10.0: arm_get_request_status,
     arm_get_request_approver, arm_get_role_definition.)

  2. Re-fire the trigger to confirm:

        REQUEST_ID=<id> SCOPE=/subscriptions/<sub>/resourceGroups/${ARM_PIM_RG} \\
        DURATION_HOURS=1 TICKET_NUMBER=<ticket> \\
        ./pim-enablement-testbed/scripts/fire-sre-agent-trigger.sh

  3. Verify in the new chat that the agent calls arm_get_request_status
     instead of get_request_status when scope starts with /subscriptions/.

EOF
