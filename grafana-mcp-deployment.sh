cd /Users/arturoquiroga/GITHUB/SRE-AGENT-JAN-2026 && source .env.deployment

IMAGE_TAG="mcp-grafana-streamable:latest"
ACR_LOGIN_SERVER="$ACR_NAME.azurecr.io"
FULL_IMAGE="$ACR_LOGIN_SERVER/$IMAGE_TAG"

echo "🔨 Building custom Grafana MCP image (streamable-http)..."
az acr build \
  --registry "$ACR_NAME" \
  --image "$IMAGE_TAG" \
  --file Dockerfile.grafana-mcp-streamable \
  .

echo "🚀 Deploying Grafana MCP to Container Apps..."
az containerapp create \
  --name ca-mcp-grafana \
  --resource-group "$RG" \
  --environment "$CAE_NAME" \
  --image "$FULL_IMAGE" \
  --target-port 8000 \
  --ingress external \
  --min-replicas 1 \
  --max-replicas 2 \
  --cpu 0.5 \
  --memory 1Gi \
  --env-vars \
    "GRAFANA_URL=$AMG_URL" \
    "GRAFANA_SERVICE_ACCOUNT_TOKEN=$GRAFANA_TOKEN" \
  --output none && echo "✅ Grafana MCP deployed (streamable-http)"

sleep 30 && az containerapp logs show --name ca-mcp-grafana --resource-group "$RG" --tail 20 --follow false