# Deployment Scripts

Shell scripts for deploying and managing the SRE Agent PoC infrastructure.

## Main Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `deploy-loki.sh` | Deploy Loki log aggregator to Container Apps | `./deploy-loki.sh` |
| `deploy-mcp-servers.sh` | Deploy both Grafana and Jira MCP servers | `./deploy-mcp-servers.sh` |
| `grafana-mcp-deployment.sh` | Build custom Grafana MCP image with StreamableHTTP | `./grafana-mcp-deployment.sh` |
| `jira-deployment.sh` | Deploy Jira MCP server only | `./jira-deployment.sh` |

## SRE Agent & Reactive Alert Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `sre_agent_api.py` | CLI for SRE Agent HTTP Triggers API (list, create, delete, fire) | `python sre_agent_api.py list` |
| `setup_reactive_alert.py` | Set up Azure Monitor → Logic App → SRE Agent pipeline | `python setup_reactive_alert.py` |
| `test_reactive_flow.py` | End-to-end test: trip CB, verify 5xx, optionally fire trigger | `python test_reactive_flow.py` |

### Reactive alert quick start

```bash
# 1. Dry run to see what will be created
python scripts/setup_reactive_alert.py --dry-run

# 2. Create the full pipeline
python scripts/setup_reactive_alert.py

# 3. Test it
python scripts/test_reactive_flow.py --manual-fire

# 4. Reset demo state
python scripts/test_reactive_flow.py --reset-only
```

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
