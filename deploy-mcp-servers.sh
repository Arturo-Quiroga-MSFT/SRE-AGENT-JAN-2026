#!/bin/bash
###############################################################################
# Azure SRE Agent PoC - MCP Servers Deployment Script
# This script deploys Grafana and Jira MCP servers to Azure Container Apps
###############################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Azure SRE Agent - MCP Servers Deployment Script        ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"
command -v az >/dev/null 2>&1 || { echo -e "${RED}Azure CLI is required but not installed. Aborting.${NC}" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo -e "${RED}jq is required but not installed. Aborting.${NC}" >&2; exit 1; }

# Verify Azure login
if ! az account show >/dev/null 2>&1; then
    echo -e "${RED}Not logged into Azure. Running 'az login'...${NC}"
    az login
fi

echo -e "${GREEN}✓ Prerequisites OK${NC}\n"

# Prompt for required variables
echo -e "${YELLOW}Enter deployment details:${NC}"
read -p "Resource Group name (e.g., rg-sre-poc-partner): " RG
read -p "Container Apps Environment name (e.g., cae-xxxxx): " CAE_NAME
read -p "Azure Managed Grafana URL (e.g., https://amg-xxxxx.grafana.azure.com): " AMG_URL
read -sp "Grafana Service Account Token (starts with glsa_): " GRAFANA_TOKEN
echo ""

echo ""
echo -e "${YELLOW}Enter Jira credentials:${NC}"
read -p "Jira URL (e.g., https://yourorg.atlassian.net): " JIRA_URL
read -p "Jira email: " JIRA_EMAIL
read -sp "Jira API token: " JIRA_TOKEN
echo ""

# Validation
if [ -z "$RG" ] || [ -z "$CAE_NAME" ] || [ -z "$AMG_URL" ] || [ -z "$GRAFANA_TOKEN" ]; then
    echo -e "${RED}All fields are required. Exiting.${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Deploying Grafana MCP Server                            ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"

# Deploy Grafana MCP Server
az containerapp create \
  --name ca-mcp-grafana \
  --resource-group "$RG" \
  --environment "$CAE_NAME" \
  --image ghcr.io/grafana/mcp-grafana:latest \
  --target-port 8000 \
  --ingress external \
  --min-replicas 1 \
  --max-replicas 2 \
  --cpu 0.25 \
  --memory 0.5Gi \
  --env-vars \
    "GRAFANA_URL=$AMG_URL" \
    "GRAFANA_SERVICE_ACCOUNT_TOKEN=$GRAFANA_TOKEN" \
  --command "/usr/local/bin/mcp-server-grafana" \
  --args "-transport" "streamable-http" "-address" "0.0.0.0:8000" \
  --output none

# Get Grafana MCP URL
MCP_GRAFANA_URL=$(az containerapp show \
  --name ca-mcp-grafana \
  --resource-group "$RG" \
  --query "properties.configuration.ingress.fqdn" \
  -o tsv)

echo -e "${GREEN}✓ Grafana MCP Server deployed${NC}"
echo -e "  Endpoint: ${GREEN}https://$MCP_GRAFANA_URL/mcp${NC}\n"

# Test Grafana MCP endpoint
echo -e "${YELLOW}Testing Grafana MCP endpoint...${NC}"
RESPONSE=$(curl -s -X POST "https://$MCP_GRAFANA_URL/mcp" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}' \
  --max-time 10 || echo "FAILED")

if echo "$RESPONSE" | grep -q "jsonrpc"; then
    echo -e "${GREEN}✓ Grafana MCP endpoint is responding${NC}\n"
else
    echo -e "${YELLOW}⚠ Warning: Grafana MCP endpoint may not be ready yet. Try testing again in 30 seconds.${NC}\n"
fi

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Deploying Jira MCP Server                               ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"

# Deploy Jira MCP Server
az containerapp create \
  --name ca-mcp-jira \
  --resource-group "$RG" \
  --environment "$CAE_NAME" \
  --image ghcr.io/sooperset/mcp-atlassian:latest \
  --target-port 8000 \
  --ingress external \
  --min-replicas 1 \
  --max-replicas 2 \
  --cpu 0.25 \
  --memory 0.5Gi \
  --env-vars \
    "JIRA_URL=$JIRA_URL" \
    "JIRA_USERNAME=$JIRA_EMAIL" \
    "JIRA_API_TOKEN=$JIRA_TOKEN" \
    "TRANSPORT=streamable-http" \
    "HOST=0.0.0.0" \
    "PORT=8000" \
  --output none

# Get Jira MCP URL
MCP_JIRA_URL=$(az containerapp show \
  --name ca-mcp-jira \
  --resource-group "$RG" \
  --query "properties.configuration.ingress.fqdn" \
  -o tsv)

echo -e "${GREEN}✓ Jira MCP Server deployed${NC}"
echo -e "  Endpoint: ${GREEN}https://$MCP_JIRA_URL/mcp${NC}\n"

# Test Jira MCP endpoint
echo -e "${YELLOW}Testing Jira MCP endpoint...${NC}"
RESPONSE=$(curl -s -X POST "https://$MCP_JIRA_URL/mcp" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}' \
  --max-time 10 || echo "FAILED")

if echo "$RESPONSE" | grep -q "jsonrpc"; then
    echo -e "${GREEN}✓ Jira MCP endpoint is responding${NC}\n"
else
    echo -e "${YELLOW}⚠ Warning: Jira MCP endpoint may not be ready yet. Try testing again in 30 seconds.${NC}\n"
fi

# Save endpoints to file
ENDPOINTS_FILE="mcp-endpoints.txt"
cat > "$ENDPOINTS_FILE" <<EOF
═══════════════════════════════════════════════════════════
   MCP Server Endpoints - Save this for SRE Agent setup
═══════════════════════════════════════════════════════════

Grafana MCP Server:
  URL: https://$MCP_GRAFANA_URL/mcp
  Transport: Streamable HTTP or SSE
  
Jira MCP Server:
  URL: https://$MCP_JIRA_URL/mcp
  Transport: Streamable HTTP or SSE

═══════════════════════════════════════════════════════════
Next steps:
1. Go to Azure SRE Agent portal
2. Create a sub-agent
3. Add these MCP servers as tools
4. Upload the knowledge file (loki-queries.md)
═══════════════════════════════════════════════════════════
EOF

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Deployment Complete!                                    ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "MCP endpoints saved to: ${GREEN}$ENDPOINTS_FILE${NC}"
echo ""
cat "$ENDPOINTS_FILE"
echo ""
echo -e "${YELLOW}Tip:${NC} If endpoints don't respond immediately, wait 30-60 seconds for containers to start."
echo ""
