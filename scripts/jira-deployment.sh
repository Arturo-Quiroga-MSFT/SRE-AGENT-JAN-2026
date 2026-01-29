cd /Users/arturoquiroga/GITHUB/SRE-AGENT-JAN-2026 && source .env.deployment

az containerapp create \
  --name ca-mcp-jira \
  --resource-group "$RG" \
  --environment "$CAE_NAME" \
  --image ghcr.io/sooperset/mcp-atlassian:latest \
  --target-port 9000 \
  --ingress external \
  --min-replicas 1 \
  --max-replicas 2 \
  --cpu 0.5 \
  --memory 1Gi \
  --env-vars \
    "JIRA_URL=$JIRA_URL" \
    "JIRA_USERNAME=$JIRA_EMAIL" \
    "JIRA_API_TOKEN=$JIRA_API_TOKEN" \
    "TRANSPORT=sse" \
    "PORT=9000" \
    "HOST=0.0.0.0" \
  --output none