#!/usr/bin/env bash
# Local stdio launcher for the Jira MCP server (mirrors the ACA deployment).
# Sources .env.deployment for JIRA_URL / JIRA_EMAIL / JIRA_API_TOKEN, then
# runs the same ghcr.io/sooperset/mcp-atlassian image in stdio mode.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/.env.deployment"

exec docker run -i --rm \
  -e "JIRA_URL=${JIRA_URL}" \
  -e "JIRA_USERNAME=${JIRA_EMAIL}" \
  -e "JIRA_API_TOKEN=${JIRA_API_TOKEN}" \
  ghcr.io/sooperset/mcp-atlassian:latest \
  --transport stdio
