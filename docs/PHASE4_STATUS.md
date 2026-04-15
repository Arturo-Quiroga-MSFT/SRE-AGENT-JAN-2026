# Phase 4 Status - MCP Servers Deployment

## ✅ Grafana MCP Server - WORKING
- **Image**: `mcp/grafana:latest`
- **URL**: https://ca-mcp-grafana.icymeadow-96da5d2b.eastus2.azurecontainerapps.io
- **SSE Endpoint**: https://ca-mcp-grafana.icymeadow-96da5d2b.eastus2.azurecontainerapps.io/sse
- **Status**: ✅ Responding correctly with SSE protocol
- **Configuration**:
  - GRAFANA_URL: Azure Managed Grafana URL  
  - GRAFANA_SERVICE_ACCOUNT_TOKEN: Service account token (non-expiring)

## ✅ Jira MCP Server - WORKING

**UPDATE (Jan 28, 2026)**: Successfully deployed after discovering proper image with HTTP/SSE support!

- **Image**: `ghcr.io/sooperset/mcp-atlassian:latest`
- **Framework**: FastMCP 2.14.1
- **URL**: https://ca-mcp-jira.icymeadow-96da5d2b.eastus2.azurecontainerapps.io
- **SSE Endpoint**: https://ca-mcp-jira.icymeadow-96da5d2b.eastus2.azurecontainerapps.io/sse
- **Status**: ✅ Responding correctly with SSE protocol
- **Configuration**:
  - JIRA_URL: https://aq-r2d2.atlassian.net
  - JIRA_USERNAME: arturoqu@microsoft.com
  - JIRA_API_TOKEN: (configured)
  - TRANSPORT: sse
  - PORT: 9000

### Solution Found
After 6 deployment attempts, discovered [sooperset/mcp-atlassian](https://github.com/sooperset/mcp-atlassian) which explicitly supports HTTP/SSE transports via environment variable configuration. Documentation at https://personal-1d37018d.mintlify.app/docs/http-transport confirmed the proper setup.

## Next Steps
1. Review Azure SRE Agent capabilities (check /tools or similar)
2. If Jira tools exist, configure them with credentials
3. If not, we'll implement direct Jira API calls or build a custom wrapper

## Current Working Configuration
```bash
# Grafana MCP (Working)
GRAFANA_MCP_URL=https://ca-mcp-grafana.icymeadow-96da5d2b.eastus2.azurecontainerapps.io/sse
GRAFANA_TOKEN=glsa_SkH1KcoKzOHFfMc8hJRGqZ8Ay36bE7ao_f5fadede

# Jira Credentials (Ready for whatever approach we choose)
JIRA_URL=https://aq-r2d2.atlassian.net
JIRA_EMAIL=arturoqu@microsoft.com
JIRA_API_TOKEN=<put token here>
```

## Summary
✅ **Phase 4 Complete** - Both MCP servers deployed and responding

- ✅ **Grafana MCP**: Deployed and validated via SSE endpoint
- ✅ **Jira MCP**: Deployed and validated via SSE endpoint (FastMCP 2.14.1)
- 🎯 **Status**: Infrastructure ready for Azure SRE Agent integration
- 📝 **Next**: Proceed to Phase 5 - Create SRE Agent and test end-to-end workflow

## Lessons Learned
1. Azure Container Apps `--args` flag has quirky parsing - avoid complex command strings, use environment variables instead
2. Many MCP server Docker images default to STDIO mode (designed for Claude Desktop), not HTTP/SSE
3. Community MCP images require careful documentation review - look for explicit HTTP/SSE transport support
4. Environment variable configuration is more reliable than command-line arguments for Container Apps
5. FastMCP framework (used by sooperset/mcp-atlassian) provides excellent HTTP/SSE support with simple TRANSPORT env var
6. Container startup takes 30-60 seconds - wait before testing endpoints to avoid false negatives
