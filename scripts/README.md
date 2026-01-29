# Deployment Scripts

Shell scripts for deploying and managing the SRE Agent PoC infrastructure.

## Main Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `deploy-loki.sh` | Deploy Loki log aggregator to Container Apps | `./deploy-loki.sh` |
| `deploy-mcp-servers.sh` | Deploy both Grafana and Jira MCP servers | `./deploy-mcp-servers.sh` |
| `grafana-mcp-deployment.sh` | Build custom Grafana MCP image with StreamableHTTP | `./grafana-mcp-deployment.sh` |
| `jira-deployment.sh` | Deploy Jira MCP server only | `./jira-deployment.sh` |

## Utility Scripts

| Script | Purpose |
|--------|---------|
| `setup-status.sh` | Check status of all deployed resources |
| `test-grafana-mcp-local.sh` | Test Grafana MCP server locally before deploying |

## Prerequisites

All scripts require:
- Azure CLI (`az`)
- Logged in to Azure (`az login`)
- Environment variables in `../.env.deployment`

## Usage

```bash
# From repository root
cd scripts
./deploy-mcp-servers.sh

# Or from anywhere
./scripts/deploy-mcp-servers.sh
```
