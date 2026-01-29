# Azure SRE Agent PoC

> **Attribution:** Based on [grocery-sre-demo](https://github.com/dm-chelupati/grocery-sre-demo) by **Deepthi Chelupati** (Microsoft).

An end-to-end Proof of Concept demonstrating Azure SRE Agent integration with Grafana/Loki and Jira using MCP (Model Context Protocol).

---

## 🚀 Quick Start

1. **Deploy base infrastructure** → `cd grocery-sre-demo && azd up`
2. **Deploy MCP servers** → `./scripts/deploy-mcp-servers.sh`
3. **Configure SRE Agent** → Follow [SETUP_FINDINGS_AND_LESSONS_LEARNED.md](docs/SETUP_FINDINGS_AND_LESSONS_LEARNED.md)

---

## 📁 Repository Structure

```
SRE-AGENT-JAN-2026/
│
├── README.md                              # This file
├── .env.deployment                        # Environment variables (credentials)
├── Dockerfile.grafana-mcp-streamable      # Custom image for Grafana MCP (key fix!)
│
├── docs/                                  # 📚 Documentation
│   ├── SETUP_FINDINGS_AND_LESSONS_LEARNED.md  ⭐ START HERE - Complete setup guide
│   ├── PARTNER_POC_GUIDE.md               # Step-by-step implementation guide
│   ├── DEPLOYMENT_CHECKLIST.md            # Interactive deployment checklist
│   ├── DEPLOYMENT_TIME_TRACKER.md         # Track time & agent performance
│   ├── PHASE4_STATUS.md                   # MCP servers deployment status
│   ├── PHASE5_ACTUAL_SETUP_GUIDE.md       # Azure SRE Agent portal workflow
│   ├── PROJECT_SUMMARY.md                 # Project overview
│   ├── BUG_REPORT_FOR_UPSTREAM.md         # Issues found for upstream repos
│   ├── mcp-endpoints.txt                  # MCP server URLs (quick reference)
│   ├── loki-config.txt                    # Loki configuration
│   └── LINKS_OF_INTEREST.txt              # Useful external links
│
├── scripts/                               # 🔧 Deployment Scripts
│   ├── deploy-loki.sh                     # Deploy Loki to Container Apps
│   ├── deploy-mcp-servers.sh              # Deploy Grafana & Jira MCP servers
│   ├── grafana-mcp-deployment.sh          # Custom Grafana MCP image build
│   ├── jira-deployment.sh                 # Jira MCP deployment
│   ├── setup-status.sh                    # Check deployment status
│   └── test-grafana-mcp-local.sh          # Test MCP server locally
│
├── partner-context/                       # 🏢 Partner-Specific Docs
│   └── ZAFIN_CONTEXT.md                   # Zafin requirements & constraints
│
├── grocery-sre-demo/                      # 🛒 Demo Application (submodule)
│   ├── src/api/                           # Node.js API with rate limiting
│   ├── src/web/                           # Web frontend
│   ├── knowledge/loki-queries.md          # LogQL patterns for SRE Agent
│   └── infra/                             # Bicep templates
│
├── scenarios/                             # 📋 Test Scenarios
│   ├── rate-limit-incident.md             # Rate limiting scenario
│   └── service-degradation.md             # Performance degradation scenario
│
└── docs_from_Deepthi Chelupati/           # 📄 Reference Materials
    └── Blog8.docx                         # Original blog post
```

---

## 📖 Documentation Guide

| If you want to... | Read this |
|-------------------|-----------|
| **Understand the full setup & lessons learned** | [SETUP_FINDINGS_AND_LESSONS_LEARNED.md](docs/SETUP_FINDINGS_AND_LESSONS_LEARNED.md) ⭐ |
| **Deploy from scratch** | [PARTNER_POC_GUIDE.md](docs/PARTNER_POC_GUIDE.md) |
| **Track deployment progress** | [DEPLOYMENT_CHECKLIST.md](docs/DEPLOYMENT_CHECKLIST.md) |
| **Understand the Grafana MCP fix** | [Dockerfile.grafana-mcp-streamable](Dockerfile.grafana-mcp-streamable) |
| **Get MCP server URLs** | [mcp-endpoints.txt](docs/mcp-endpoints.txt) |

---

## ⚠️ Key Lesson Learned

**Azure SRE Agent requires Streamable-HTTP transport, NOT SSE!**

Most MCP server images default to SSE mode. We had to build a custom Grafana MCP image:

```dockerfile
FROM grafana/mcp-grafana:latest
ENTRYPOINT ["/app/mcp-grafana","-t","streamable-http","--address","0.0.0.0:8000","--endpoint-path","/mcp"]
```

See [SETUP_FINDINGS_AND_LESSONS_LEARNED.md](docs/SETUP_FINDINGS_AND_LESSONS_LEARNED.md) for the full troubleshooting story.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Azure SRE Agent (aq-main)                       │
│                                                                     │
│                 ┌───────────────────────────────────┐               │
│                 │   DiagnosticExpert Subagent       │               │
│                 │   (96 tools + knowledge file)     │               │
│                 └─────────────┬─────────────────────┘               │
│                               │                                     │
│              ┌────────────────┼────────────────┐                    │
│              ▼                                 ▼                    │
│       grafana-mcp                        jira-mcp                   │
│       (Connector)                       (Connector)                 │
└──────────┬────────────────────────────────────┬─────────────────────┘
           │                                    │
           ▼                                    ▼
┌─────────────────────┐              ┌─────────────────────┐
│  Grafana MCP Server │              │   Jira MCP Server   │
│  (StreamableHTTP)   │              │   (HTTP transport)  │
│  Custom Docker image│              │   sooperset/mcp-    │
└──────────┬──────────┘              │   atlassian         │
           │                         └──────────┬──────────┘
           ▼                                    │
┌─────────────────────┐                         ▼
│  Azure Managed      │              ┌─────────────────────┐
│  Grafana + Loki     │              │  Jira Cloud         │
└──────────┬──────────┘              │  aq-r2d2.atlassian  │
           │                         └─────────────────────┘
           ▼
┌─────────────────────┐
│  Grocery API        │  ◀── Demo app that generates 429 errors
│  (Container App)    │
└─────────────────────┘
```

---

## 🧪 Test the Demo

```bash
# Trigger rate limit scenario
curl -X POST "https://ca-api-ps64h2ydsavgc.icymeadow-96da5d2b.eastus2.azurecontainerapps.io/api/demo/trigger-rate-limit"

# Then ask the SRE Agent:
# "Investigate rate limit errors in the grocery API"
```

---

## 📞 Resources

- **[Azure SRE Agent Docs](https://learn.microsoft.com/azure/sre-agent)**
- **[MCP Protocol Specification](https://modelcontextprotocol.io)**
- **[Grafana MCP Server](https://github.com/grafana/mcp-grafana)**
- **[sooperset/mcp-atlassian](https://github.com/sooperset/mcp-atlassian)** (Jira MCP)

---

**Version:** 2.0  
**Last Updated:** January 29, 2026  
**Author:** Arturo Quiroga
