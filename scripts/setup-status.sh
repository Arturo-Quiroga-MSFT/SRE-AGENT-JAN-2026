#!/bin/bash
###############################################################################
# Azure SRE Agent PoC - Quick Setup Helper
# This script helps you proceed through the deployment phases
###############################################################################

# Load environment variables
source /Users/arturoquiroga/GITHUB/SRE-AGENT-JAN-2026/.env.deployment

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   Azure SRE Agent PoC - Deployment Status                ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Phase 1: Verify Base Infrastructure
echo "✅ PHASE 1: Base Infrastructure - COMPLETE"
echo "   Resource Group: $RG"
echo "   Environment: $CAE_NAME"
echo "   Location: $LOCATION"
echo ""

# Check container apps
echo "📦 Container Apps Status:"
az containerapp list --resource-group $RG \
  --query "[].{Name:name, Status:properties.runningStatus, URL:properties.configuration.ingress.fqdn}" \
  -o table 2>/dev/null
echo ""

# Check Grafana
echo "📊 Azure Managed Grafana:"
echo "   URL: $AMG_URL"
AMG_NAME="amg-ps64h2ydsavgc"
echo "   Name: $AMG_NAME"
echo "   💡 TIP: If you get 'No Role Assigned', run this to grant access:"
echo "      az role assignment create --assignee \$(az ad signed-in-user show --query id -o tsv) --role 'Grafana Admin' --scope \"/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.Dashboard/grafana/$AMG_NAME\""
echo ""

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   NEXT STEPS                                              ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "⏱️  Phase 2: Deploy Loki (10 minutes)"
echo "   Run: ./deploy-loki.sh"
echo ""

echo "⏱️  Phase 3: Configure Grafana (15 minutes)"
echo "   1. Open Grafana: $AMG_URL"
echo "   2. Add Loki data source"
echo "   3. Create service account 'mcp-server'"
echo "   4. Generate and save token"
echo ""

echo "⏱️  Phase 4: Deploy MCP Servers (15 minutes)"
echo "   Prerequisites:"
echo "   - Grafana service account token"
echo "   - Jira URL and API token"
echo "   Run: ./deploy-mcp-servers.sh"
echo ""

echo "⏱️  Phase 5: Create SRE Agent (20 minutes)"
echo "   Portal: https://aka.ms/sreagent/portal"
echo ""

echo "⏱️  Phase 6: Test End-to-End (15 minutes)"
echo "   Trigger demo: curl -X POST https://ca-api-ps64h2ydsavgc.icymeadow-96da5d2b.eastus2.azurecontainerapps.io/api/demo/trigger-rate-limit"
echo ""

echo "📚 Documentation:"
echo "   - Quick Start: README.md"
echo "   - Complete Guide: PARTNER_POC_GUIDE.md"
echo "   - Time Tracker: DEPLOYMENT_TIME_TRACKER.md"
echo ""

# Test API health
echo "🔍 Testing API Health..."
if curl -s https://ca-api-ps64h2ydsavgc.icymeadow-96da5d2b.eastus2.azurecontainerapps.io/health > /dev/null 2>&1; then
    echo "   ✅ API is healthy and responding"
else
    echo "   ⚠️  API not responding yet (may still be starting)"
fi
echo ""

echo "💡 TIP: Use 'source .env.deployment' to reload environment variables in any terminal"
echo ""
