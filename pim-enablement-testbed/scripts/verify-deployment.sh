#!/usr/bin/env bash
# Smoke-test the deployed PIM Enablement testbed.
#
# May 4 2026: Updated for the Microsoft MCP Server for Enterprise pivot.
# Checks now focus on tenant provisioning + MI presence, not a Container App.

set -euo pipefail

RG_NAME="${RG_NAME:-rg-pim-enablement-testbed}"
PREFIX="${PREFIX:-pimtest}"
ENTERPRISE_MCP_APPID="${ENTERPRISE_MCP_APPID:-e8c77dc2-69b3-43f4-bc51-3213c9d915b4}"
SVC_ACCOUNT_UPN="${SVC_ACCOUNT_UPN:-svc-pim-enablement-agent@example.com}"

echo "==> Checking resource group: $RG_NAME"
az group show -n "$RG_NAME" --query name -o tsv

echo "==> Checking managed identity (Jira/Teams paths): mi-${PREFIX}-agent"
az identity show -g "$RG_NAME" -n "mi-${PREFIX}-agent" --query clientId -o tsv

echo "==> Checking Microsoft MCP Server for Enterprise SP exists in tenant"
az ad sp show --id "$ENTERPRISE_MCP_APPID" --query "{appId:appId, displayName:displayName}" -o table \
    || { echo "ERROR: Enterprise MCP Server SP not provisioned in this tenant. See docs/enterprise-mcp-setup.md."; exit 1; }

echo "==> Checking service-account user exists: $SVC_ACCOUNT_UPN"
az ad user show --id "$SVC_ACCOUNT_UPN" --query "{upn:userPrincipalName, id:id}" -o table \
    || { echo "WARN: service account not found. Run scripts/provision-enterprise-mcp.ps1."; }

echo "==> Reachability of the Enterprise MCP endpoint"
# The MCP endpoint requires OAuth; we only check DNS + TLS handshake.
curl -fsSI --max-time 10 "https://mcp.svc.cloud.microsoft/enterprise" -o /dev/null \
    && echo "    OK (TLS handshake to mcp.svc.cloud.microsoft succeeded)" \
    || echo "    WARN: could not reach mcp.svc.cloud.microsoft (auth challenge expected — check egress)"

echo ""
echo "Smoke test complete."
echo "For full validation, sign into the Foundry connector as $SVC_ACCOUNT_UPN"
echo "and trigger a synthetic PIM request via scripts/trigger-pim-request.sh."
