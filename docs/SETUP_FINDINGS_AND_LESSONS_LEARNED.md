# Azure SRE Agent PoC - Setup Findings & Lessons Learned

**Date:** January 28, 2026  
**Author:** Arturo Quiroga  
**Status:** PoC Complete ✅

---

## Executive Summary

This document captures all findings, troubleshooting steps, and lessons learned during the setup of the Azure SRE Agent Proof of Concept. The PoC successfully integrated two MCP (Model Context Protocol) servers with Azure SRE Agent to create an autonomous diagnostic workflow.

### How This PoC Relates to grocery-sre-demo

This PoC builds upon the **[grocery-sre-demo](https://github.com/deepthic/grocery-sre-demo)** sample application shared by Deepthi Chelupati. The relationship:

| Component | Source | Purpose |
|-----------|--------|---------|
| **Grocery API** | `grocery-sre-demo/src/api` | Simulates a real app with rate limiting issues |
| **Web Frontend** | `grocery-sre-demo/src/web` | UI to trigger demo scenarios |
| **Loki** | Deployed separately | Log aggregation for the Grocery API |
| **Azure Managed Grafana** | Auto-provisioned by SRE Agent | Visualization + Loki data source |
| **MCP Servers** | Deployed based on grocery-sre-demo README | Enable AI agent to query logs & create tickets |
| **Knowledge File** | `grocery-sre-demo/knowledge/loki-queries.md` | Pre-built LogQL patterns for the agent |
| **Azure SRE Agent** | Azure Portal | Orchestrates the autonomous diagnostic workflow |

The grocery-sre-demo provides the **demo scenario** (supplier rate limiting), and we deployed the **supporting infrastructure** (MCP servers, SRE Agent) to make it work end-to-end.

### Final Architecture - Complete E2E Flow

```
                                    ┌─────────────────────────────────────┐
                                    │      Azure SRE Agent (aq-main)      │
                                    │                                     │
                                    │  ┌───────────────────────────────┐  │
                                    │  │   DiagnosticExpert Subagent   │  │
                                    │  │          (96 tools)           │  │
                                    │  │   + loki-queries.md knowledge │  │
                                    │  └──────────┬──────────┬─────────┘  │
                                    │             │          │            │
                                    │      ┌──────┴───┐  ┌───┴──────┐     │
                                    │      │grafana-  │  │ jira-mcp │     │
                                    │      │   mcp    │  │connector │     │
                                    │      └────┬─────┘  └────┬─────┘     │
                                    └───────────┼─────────────┼───────── ─┘
                                                │             │
                    ┌───────────────────────────┼─────────────┼───────────────────────────┐
                    │                           ▼             ▼                           │
                    │  ┌─────────────────────────────┐ ┌─────────────────────────────┐    │
                    │  │  Grafana MCP Server         │ │   Jira MCP Server           │    │
                    │  │  (ca-mcp-grafana)           │ │   (ca-mcp-jira)             │    │
                    │  │  StreamableHTTP transport   │ │   HTTP transport            │    │
                    │  │  Custom image in ACR        │ │   sooperset/mcp-atlassian   │    │
                    │  └──────────────┬──────────────┘ └──────────────┬──────────────┘    │
                    │                 │                               │                   │
                    │                 ▼                               ▼                   │
                    │  ┌─────────────────────────────┐ ┌─────────────────────────────┐    │
                    │  │   Azure Managed Grafana     │ │   Jira Cloud                │    │
                    │  │   (amg-ps64h2ydsavgc)       │ │   aq-r2d2.atlassian.net     │    │
                    │  │   + Loki data source        │ │                             │    │
                    │  └──────────────┬──────────────┘ └─────────────────────────────┘    │
                    │                 │                                                   │
                    │                 ▼                                                   │
                    │  ┌─────────────────────────────┐                                    │
                    │  │   Loki (ca-loki)            │◀──── Logs pushed via HTTP          │
                    │  │   Log aggregation           │                                    │
                    │  └─────────────────────────────┘                                    │
                    │                 ▲                                                   │
                    │                 │                                                   │
                    │  ┌──────────────┴──────────────┐                                    │
                    │  │   Grocery API               │ ◀─── FROM: grocery-sre-demo        │
                    │  │   (ca-api-ps64h2ydsavgc)    │      Demo app with rate limiting   │
                    │  │   Simulates supplier 429s   │                                    │
                    │  └──────────────┬──────────────┘                                    │
                    │                 ▲                                                   │
                    │                 │                                                   │
                    │  ┌──────────────┴──────────────┐                                    │
                    │  │   Web Frontend              │ ◀─── FROM: grocery-sre-demo        │
                    │  │   (ca-web-ps64h2ydsavgc)    │      "Trigger Rate Limit" button   │
                    │  └─────────────────────────────┘                                    │
                    │                                                                     │
                    │            Azure Container Apps Environment (cae-ps64h2ydsavgc)     │
                    └─────────────────────────────────────────────────────────────────────┘
```

### What Came From Where

| Deployed Container App | Source | Deployed Via |
|------------------------|--------|--------------|
| `ca-api-ps64h2ydsavgc` | `grocery-sre-demo/src/api` | `azd up` |
| `ca-web-ps64h2ydsavgc` | `grocery-sre-demo/src/web` | `azd up` |
| `ca-loki` | `grafana/loki:2.9.0` | Manual `az containerapp create` |
| `ca-mcp-grafana` | Custom image (see our fix) | Script + ACR build |
| `ca-mcp-jira` | `ghcr.io/sooperset/mcp-atlassian` | Script |

### Demo Scenario Flow

1. **User** clicks "Trigger Rate Limit" in **Web Frontend**
2. **Grocery API** makes 15 rapid calls to simulated supplier
3. After 5 calls, supplier returns **429 Too Many Requests**
4. Errors logged to **Loki** with `errorCode: SUPPLIER_RATE_LIMIT_429`
5. **SRE Agent** receives incident → hands off to **DiagnosticExpert**
6. **DiagnosticExpert** queries **Grafana MCP** → gets error logs from Loki
7. Agent analyzes patterns using **loki-queries.md** knowledge
8. Agent creates **Jira ticket** via **Jira MCP** with RCA

---

## Phase 1: Azure Resource Deployment

### Resources Created

| Resource | Name | Type | Region |
|----------|------|------|--------|
| Resource Group | rg-aqsre | Microsoft.Resources/resourceGroups | eastus2 |
| Container Apps Environment | cae-ps64h2ydsavgc | Microsoft.App/managedEnvironments | eastus2 |
| Container Registry | crps64h2ydsavgc | Microsoft.ContainerRegistry/registries | eastus2 |
| Managed Grafana | amg-ps64h2ydsavgc | Microsoft.Dashboard/grafana | eastus2 |
| SRE Agent | aq-main | Microsoft.SreAgent/agents | eastus2 |

### Deployment Method

Used Azure SRE Agent provisioning which auto-created:
- Container Apps Environment
- Azure Container Registry
- Azure Managed Grafana with Loki data source

### Lessons Learned - Azure Resources

1. **Auto-provisioning**: Azure SRE Agent can provision its own supporting infrastructure
2. **Naming convention**: Resources get random suffix (e.g., `ps64h2ydsavgc`) for uniqueness
3. **Grafana service account**: Create non-expiring service account token for MCP server authentication

---

## Phase 2: MCP Servers - Initial Deployment Attempts

### Challenge: STDIO vs HTTP Transport

Most MCP server Docker images are designed for **Claude Desktop** which uses STDIO transport. Azure SRE Agent requires **HTTP-based transport** (SSE or Streamable-HTTP).

#### Failed Attempts

| Image | Issue |
|-------|-------|
| `mcp-server/jira` | STDIO only, no HTTP support |
| `ariesclark/atlassian-mcp` | STDIO only |
| Various community images | Lack HTTP transport configuration |

#### Successful Solution - Jira MCP

**Image:** `ghcr.io/sooperset/mcp-atlassian:latest`  
**Framework:** FastMCP 2.14.1  
**Key Feature:** Supports HTTP transport via environment variable

```bash
# Deployment configuration
TRANSPORT=http
PORT=9000

# Container creates /mcp endpoint automatically
```

**Documentation:** https://personal-1d37018d.mintlify.app/docs/http-transport

### Lessons Learned - MCP Server Selection

1. **Always verify transport support** before selecting an MCP server image
2. **FastMCP framework** provides reliable HTTP/SSE support
3. **Environment variables** are more reliable than command-line args in Container Apps
4. **Community images** require careful documentation review

---

## Phase 3: Grafana MCP - The SSE vs Streamable-HTTP Problem

### Critical Discovery

**Azure SRE Agent connectors require Streamable-HTTP transport, NOT SSE!**

This was the single biggest troubleshooting challenge in the entire PoC.

### Symptom

When adding Grafana MCP as a connector in Azure SRE Agent:
```
Error: 405 Method Not Allowed
```

The connector validation was failing despite the MCP server responding correctly to curl requests.

### Root Cause Analysis

| Transport Mode | How It Works | Azure SRE Agent Support |
|----------------|--------------|-------------------------|
| **SSE** | Server-Sent Events, unidirectional streaming | ❌ NOT SUPPORTED |
| **Streamable-HTTP** | Bidirectional HTTP with streaming response | ✅ REQUIRED |

The official Grafana MCP image defaults to SSE mode:
```
Starting Grafana MCP server using SSE transport
```

Azure SRE Agent sends HTTP POST requests to the `/mcp` endpoint, but SSE mode expects GET requests with `Accept: text/event-stream` header.

### Failed Solution Attempts

#### Attempt 1: Command-line args in Container Apps
```bash
az containerapp create --args "-t" "streamable-http" ...
```
**Result:** Args not passed correctly to ENTRYPOINT

#### Attempt 2: Using --command override
```bash
az containerapp create --command "/app/mcp-grafana -t streamable-http" ...
```
**Result:** Command parsing issues

#### Attempt 3: Environment variables
```bash
az containerapp create --env-vars "TRANSPORT=streamable-http" ...
```
**Result:** Grafana MCP doesn't support transport configuration via env vars

### Successful Solution: Custom Docker Image

Created a custom Docker image that forces Streamable-HTTP transport via ENTRYPOINT.

#### Step 1: Create Dockerfile

**File:** `Dockerfile.grafana-mcp-streamable`

```dockerfile
FROM grafana/mcp-grafana:latest
ENTRYPOINT ["/app/mcp-grafana","-t","streamable-http","--address","0.0.0.0:8000","--endpoint-path","/mcp"]
```

**Key Discovery:** The binary is located at `/app/mcp-grafana`, not in system PATH.

Found via:
```bash
docker run --rm --entrypoint /bin/sh grafana/mcp-grafana:latest -c "ls -la /app"
```

#### Step 2: Build in Azure Container Registry

```bash
az acr build \
  --registry crps64h2ydsavgc \
  --image grafana-mcp-streamable:latest \
  --file Dockerfile.grafana-mcp-streamable \
  .
```

#### Step 3: Deploy Custom Image

```bash
az containerapp update \
  --name ca-mcp-grafana \
  --resource-group rg-aqsre \
  --image crps64h2ydsavgc.azurecr.io/grafana-mcp-streamable:latest
```

#### Step 4: Configure ACR Authentication

Container Apps needs registry credentials:
```bash
az containerapp registry set \
  --name ca-mcp-grafana \
  --resource-group rg-aqsre \
  --server crps64h2ydsavgc.azurecr.io \
  --identity system
```

#### Verification

```bash
az containerapp logs show --name ca-mcp-grafana --resource-group rg-aqsre --tail 20
```

**Expected output:**
```
level=INFO msg="Starting Grafana MCP server using StreamableHTTP transport" version=(devel) address=0.0.0.0:8000 endpointPath=/mcp
```

### Lessons Learned - Transport Modes

1. **SSE ≠ Streamable-HTTP**: These are different protocols despite both being HTTP-based
2. **Azure SRE Agent only supports Streamable-HTTP** for MCP connectors
3. **Check container logs** to verify actual transport mode being used
4. **Custom Docker images** may be necessary when official images don't support required transport
5. **ENTRYPOINT override** is more reliable than command args in Container Apps
6. **Binary paths** in containers may not be in PATH - use absolute paths

---

## Phase 4: Azure SRE Agent Configuration

### Creating the SRE Agent

1. Navigate to Azure Portal → Create Resource → "Azure SRE Agent"
2. Configure basic settings:
   - **Name:** aq-main
   - **Region:** eastus2
   - **Managed Resource Group:** Auto-created

### Adding MCP Connectors

**Settings → Connectors → + Add connector**

#### Grafana MCP Connector (after custom image fix)

```
Name: grafana-mcp
Connection type: Streamable-HTTP
URL: https://ca-mcp-grafana.icymeadow-96da5d2b.eastus2.azurecontainerapps.io/mcp
Authentication: None (token embedded in container env vars)
Status: ✅ Connected
```

#### Jira MCP Connector

```
Name: jira-mcp
Connection type: HTTP
URL: https://ca-mcp-jira.icymeadow-96da5d2b.eastus2.azurecontainerapps.io/mcp
Authentication: None (credentials embedded in container env vars)
Status: ✅ Connected
```

### Creating the DiagnosticExpert Subagent

**Builder → Subagent Builder → + Add subagent**

#### Configuration

| Field | Value |
|-------|-------|
| Name | DiagnosticExpert |
| Instructions | (see below) |
| Handoff Instructions | (see below) |
| Tools | 96 tools from both MCP connectors |

#### Instructions

```
You are a diagnostic expert that investigates incidents using Grafana logs and creates Jira tickets for tracking.

WORKFLOW:
1. When given an incident or alert, use grafana-mcp to query Loki logs for relevant error patterns
2. Analyze the logs to identify root cause indicators
3. Summarize findings with timestamps, error counts, and affected services
4. Use jira-mcp to create a ticket with the diagnosis details

LOG QUERY PATTERNS:
- For errors: {job="your-app"} |= "error" | json
- For specific service: {service_name="<service>"} | json
- Time-based: Use the last 1 hour unless specified otherwise

JIRA TICKET FORMAT:
- Project: Use the project key provided by the user
- Summary: "[Incident] <brief description>"
- Description: Include timeline, error samples, affected components, and recommended actions
- Priority: Based on error severity and impact

Always explain your reasoning and provide actionable recommendations.
```

#### Handoff Instructions

```
Hand off to DiagnosticExpert when the user needs to:
- Investigate an incident or alert
- Query Grafana/Loki logs for troubleshooting
- Create a Jira ticket for incident tracking
- Diagnose application errors or performance issues
```

### Lessons Learned - Azure SRE Agent

1. **Two-tier architecture**: Connectors provide tools, Subagents use the tools
2. **Tool selection**: Can select individual tools or entire connector tool sets
3. **Test Playground**: Essential for validating subagent behavior before production use
4. **Knowledge files**: Can upload .md files with domain knowledge (e.g., LogQL patterns)

---

## Final Configuration Reference

### MCP Server Endpoints

| Server | Endpoint | Transport | Status |
|--------|----------|-----------|--------|
| Grafana MCP | `https://ca-mcp-grafana.icymeadow-96da5d2b.eastus2.azurecontainerapps.io/mcp` | Streamable-HTTP | ✅ |
| Jira MCP | `https://ca-mcp-jira.icymeadow-96da5d2b.eastus2.azurecontainerapps.io/mcp` | HTTP | ✅ |

### Container Images

| Server | Image | Notes |
|--------|-------|-------|
| Grafana MCP | `crps64h2ydsavgc.azurecr.io/grafana-mcp-streamable:latest` | Custom build |
| Jira MCP | `ghcr.io/sooperset/mcp-atlassian:latest` | Community image |

### Environment Variables

**Grafana MCP:**
```bash
GRAFANA_URL=https://amg-ps64h2ydsavgc-dsc6hka9f7d7e9aw.eus2.grafana.azure.com
GRAFANA_SERVICE_ACCOUNT_TOKEN=glsa_SkH1KcoKzOHFfMc8hJRGqZ8Ay36bE7ao_f5fadede
```

**Jira MCP:**
```bash
JIRA_URL=https://aq-r2d2.atlassian.net
JIRA_USERNAME=arturoqu@microsoft.com
JIRA_API_TOKEN=(see .env.deployment)
TRANSPORT=http
PORT=9000
```

---

## Files Created During Setup

| File | Purpose |
|------|---------|
| `Dockerfile.grafana-mcp-streamable` | Custom image for Streamable-HTTP transport |
| `grafana-mcp-deployment.sh` | Deployment script for custom Grafana MCP |
| `.env.deployment` | Environment variables for all deployments |
| `mcp-endpoints.txt` | Quick reference for MCP endpoints |

---

## Troubleshooting Guide

### Connector Shows "405 Method Not Allowed"
- **Cause:** MCP server is in SSE mode, not Streamable-HTTP
- **Solution:** Build custom image with `-t streamable-http` flag

### Container App Can't Pull Custom Image
- **Cause:** Missing ACR authentication
- **Solution:** `az containerapp registry set --identity system`

### MCP Server Not Responding
- **Check:** Container logs: `az containerapp logs show --name <name> --resource-group <rg> --follow`
- **Check:** Container is running: `az containerapp show --name <name> --resource-group <rg>`
- **Check:** Ingress enabled: Must have external ingress on port 8000 or 9000

### Subagent Can't Access Tools
- **Check:** Connector status in Settings → Connectors
- **Check:** Tools selected in subagent configuration
- **Try:** Refresh connectors, recreate subagent

---

## Key Takeaways for Future Deployments

1. **Always use Streamable-HTTP** for Azure SRE Agent MCP connectors
2. **Test transport mode locally** before deploying to Azure:
   ```bash
   docker run --rm -p 8000:8000 grafana/mcp-grafana:latest -t streamable-http
   ```
3. **Build custom images in ACR** when transport mode can't be configured via env vars
4. **Verify with logs** that the correct transport mode is active
5. **Use FastMCP-based images** when possible for reliable HTTP transport support
6. **Embed credentials in container env vars** rather than configuring auth in connector

---

## Timeline

| Date | Milestone |
|------|-----------|
| Jan 28, 2026 AM | Azure resources provisioned, initial MCP deployment attempts |
| Jan 28, 2026 PM | Discovered SSE vs Streamable-HTTP issue |
| Jan 28, 2026 PM | Built custom Grafana MCP image |
| Jan 28, 2026 PM | Both connectors connected, DiagnosticExpert subagent created |

**Total Setup Time:** ~4 hours (including troubleshooting)  
**Expected Time (with this guide):** ~1 hour

---

## References

- [Azure SRE Agent Documentation](https://learn.microsoft.com/azure/sre-agent)
- [MCP Protocol Specification](https://modelcontextprotocol.io)
- [Grafana MCP Server](https://github.com/grafana/mcp-grafana)
- [sooperset/mcp-atlassian](https://github.com/sooperset/mcp-atlassian)
- [FastMCP HTTP Transport](https://personal-1d37018d.mintlify.app/docs/http-transport)

---

## Addendum — May 8, 2026: pim-mcp wiring + Enterprise MCP gap

Wiring the custom `pim-mcp` (PIM Enablement testbed) into the SRE Agent surfaced four findings worth adding to the institutional knowledge:

### 1. The SSE vs Streamable-HTTP rule applies to FastMCP servers too

`pim-mcp` was originally built with FastMCP's `transport="sse"`, which exposes only `/sse`. The SRE Agent connector wizard probes `/mcp` and 404s. Same root cause as the grafana-mcp finding above (Phase 3) — but worth re-stating because **FastMCP does not auto-serve a Streamable-HTTP fallback**. You must explicitly write:

```python
mcp.run(transport="streamable-http", host="0.0.0.0", port=8000, path="/mcp")
```

The explicit `path="/mcp"` (no trailing slash) avoids a Starlette Mount slash-redirect that downgrades to plain HTTP behind ACA's HTTPS ingress. Without it, the wizard's smoke probe gets 307 → `http://...` → broken redirect chain.

### 2. The 80-tool agent cap is connector-agnostic

The wizard rejected adding `pim-mcp`'s 2 tools with `80/80 tools selected, 2 available` and disabled checkboxes. The cap is **per-agent across all connectors**. Trim one connector's tool selection (we trimmed grafana-mcp) to free slots before adding new ones.

### 3. Microsoft Enterprise MCP cannot be wired through the wizard today

The SRE Agent MCP wizard auth dropdown offers only:
- Bearer token (static — no refresh)
- Custom headers (same problem)
- Managed identity

Microsoft's first-party Enterprise MCP server (`https://mcp.svc.cloud.microsoft/enterprise`) is **delegated-OAuth-only by design**. None of the three options can authenticate against it. Net effect: the SRE Agent currently cannot consume Microsoft's own MCP server, even though Foundry Agent Builder can.

**Strategic ask** (raised with Deepthi, SRE Agent PM): add OAuth 2.0 Authorization Code (delegated) as a 4th wizard auth option, with smaller fallbacks (custom-header refresh hook, MI federated token exchange to delegated user token).

**Tactical workaround** in this PoC: extended `pim-mcp` itself with `get_user` and `get_role_definition` tools so the agent can resolve Graph IDs without Enterprise MCP. Granted `User.Read.All` and `RoleManagement.Read.Directory` to the pim-mcp Managed Identity. Bumped image to 0.4.1.

### 4. `unifiedRoleDefinition.isPrivileged` is beta-only

A `$select=isPrivileged` against `/v1.0/roleManagement/directory/roleDefinitions/{id}` returns Graph 400. The property exists on the `beta` endpoint only. Stay v1.0-compatible in `$select` strings or split the query.

### Net result

End-to-end PIM scenario validated through the SRE Agent on May 8, 2026:
- Agent identifies pending PIM activation request via custom MCP tool.
- Resolves principal/role IDs via the same custom MCP tool's added Graph reads.
- Reasons about the policy gate citing in-repo validation rules (R001-R008).
- Produces approver-pastable triage paragraph with computed expiration math.

See `pim-enablement-testbed/test-results-May-5-2026.md` for the full run log.
