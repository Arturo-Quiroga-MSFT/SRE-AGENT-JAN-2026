#!/bin/bash
###############################################################################
# Azure SRE Agent PoC - Loki Deployment & Configuration Script
# This script deploys Loki for log aggregation and configures apps to send logs
###############################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Azure SRE Agent - Loki Deployment Script               ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"
command -v az >/dev/null 2>&1 || { echo -e "${RED}Azure CLI is required but not installed. Aborting.${NC}" >&2; exit 1; }

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

# Validation
if [ -z "$RG" ] || [ -z "$CAE_NAME" ]; then
    echo -e "${RED}All fields are required. Exiting.${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Deploying Loki as Container App                         ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"

# Deploy Loki
az containerapp create \
  --name ca-loki \
  --resource-group "$RG" \
  --environment "$CAE_NAME" \
  --image grafana/loki:2.9.0 \
  --target-port 3100 \
  --ingress external \
  --min-replicas 1 \
  --max-replicas 1 \
  --cpu 0.5 \
  --memory 1Gi \
  --args "-config.file=/etc/loki/local-config.yaml" \
  --output none

# Get Loki URL
LOKI_URL=$(az containerapp show \
  --name ca-loki \
  --resource-group "$RG" \
  --query "properties.configuration.ingress.fqdn" \
  -o tsv)

echo -e "${GREEN}✓ Loki deployed${NC}"
echo -e "  URL: ${GREEN}https://$LOKI_URL${NC}\n"

# Test Loki endpoint
echo -e "${YELLOW}Testing Loki endpoint...${NC}"
sleep 5  # Give Loki a moment to start

RESPONSE=$(curl -s "https://$LOKI_URL/ready" --max-time 10 || echo "FAILED")

if echo "$RESPONSE" | grep -q "ready"; then
    echo -e "${GREEN}✓ Loki is ready${NC}\n"
else
    echo -e "${YELLOW}⚠ Warning: Loki may not be ready yet. Try testing again in 30 seconds.${NC}\n"
fi

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Configuring Application to Send Logs to Loki           ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"

# Find API container app
echo -e "${YELLOW}Looking for API container app...${NC}"
API_NAME=$(az containerapp list --resource-group "$RG" \
  --query "[?contains(name, 'api')].name" -o tsv | head -1)

if [ -z "$API_NAME" ]; then
    echo -e "${YELLOW}⚠ No API container app found. Skipping configuration.${NC}"
    echo -e "  ${YELLOW}You'll need to manually set LOKI_HOST env var on your app.${NC}\n"
else
    echo -e "${GREEN}✓ Found API: $API_NAME${NC}\n"
    
    echo -e "${YELLOW}Updating $API_NAME with LOKI_HOST environment variable...${NC}"
    az containerapp update \
      --name "$API_NAME" \
      --resource-group "$RG" \
      --set-env-vars "LOKI_HOST=https://$LOKI_URL" \
      --output none
    
    echo -e "${GREEN}✓ API configured to send logs to Loki${NC}\n"
fi

# Save Loki info to file
LOKI_INFO_FILE="loki-config.txt"
cat > "$LOKI_INFO_FILE" <<EOF
═══════════════════════════════════════════════════════════
   Loki Configuration Info
═══════════════════════════════════════════════════════════

Loki URL: https://$LOKI_URL

Query Endpoint: https://$LOKI_URL/loki/api/v1/query_range
Push Endpoint: https://$LOKI_URL/loki/api/v1/push

═══════════════════════════════════════════════════════════
Next steps:
1. Add Loki data source in Azure Managed Grafana:
   - Go to Grafana → Configuration → Data Sources
   - Add Loki
   - URL: https://$LOKI_URL
   - Click Save & Test

2. Test querying logs:
   curl -G "https://$LOKI_URL/loki/api/v1/query_range" \\
     --data-urlencode 'query={app="grocery-api"}'

3. View logs in Grafana Explore:
   - Query: {app="grocery-api"}
═══════════════════════════════════════════════════════════
EOF

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Deployment Complete!                                    ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Loki configuration saved to: ${GREEN}$LOKI_INFO_FILE${NC}"
echo ""
cat "$LOKI_INFO_FILE"
echo ""
