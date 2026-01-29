#!/bin/bash
# Test Grafana MCP locally with Docker to verify streamable-http transport works

set -e

source .env.deployment

echo "🧪 Testing Grafana MCP locally with Docker..."
echo ""
echo "📋 Config:"
echo "  GRAFANA_URL: $AMG_URL"
echo "  Token: ${GRAFANA_TOKEN:0:20}..."
echo ""

# Pull the image
docker pull grafana/mcp-grafana:latest

# Run with streamable-http transport (exactly as shown in docs)
echo "🚀 Starting container with streamable-http transport..."
docker run --rm -d --name test-grafana-mcp \
  -p 8000:8000 \
  -e GRAFANA_URL="$AMG_URL" \
  -e GRAFANA_SERVICE_ACCOUNT_TOKEN="$GRAFANA_TOKEN" \
  grafana/mcp-grafana \
  -t streamable-http

# Wait for startup
echo "⏳ Waiting 10 seconds for container to start..."
sleep 10

# Check logs
echo ""
echo "📋 Container logs:"
docker logs test-grafana-mcp 2>&1 | head -20

# Test the endpoint
echo ""
echo "🔍 Testing /mcp endpoint..."
curl -s -X POST "http://localhost:8000/mcp" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | jq '.' || echo "Endpoint test result above"

echo ""
echo "✅ Container is running. Check logs above for transport mode."
echo ""
echo "To stop: docker stop test-grafana-mcp"
