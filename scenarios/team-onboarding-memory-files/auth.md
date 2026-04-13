## Auth & Identity

### SRE Agent Identity

| Identity | Client ID | Purpose |
|---|---|---|
| System-assigned MI | `4209922a-22c3-4923-a360-f970eebe2034` | Agent's own identity |
| User-assigned MI | `5ef3d54d-b401-496d-ba2f-a6652872a084` | Resource access (code execution, Azure ops) |

**ARM Resource ID:** `/subscriptions/7a28b21e-0d3e-4435-a686-d92889d4ee96/resourcegroups/rg-aqsre/providers/microsoft.app/agents/aq-main`

### RBAC Roles (AKS Testbed)

| Role | Scope | Purpose |
|---|---|---|
| AKS Contributor | AKS cluster | ARM-level management (scale, upgrade) |
| Reader | Resource Group | Read resource metadata |
| Log Analytics Reader | LA Workspace | KQL queries on Container Insights |
| AKS Cluster User | AKS cluster | kubectl via `az aks command invoke` |

### Grafana MCP Authentication

- **Method:** Grafana Service Account Token (non-expiring)
- **Token:** `glsa_SkH1KcoKzOHFfMc8hJRGqZ8Ay36bE7ao_f5fadede`
- **Embedded in:** `ca-mcp-grafana` container env vars
- **Grafana URL:** `https://amg-ps64h2ydsavgc-dsc6hka9f7d7e9aw.eus2.grafana.azure.com`
- **No auth configured on MCP connector** — token is baked into the container

### Jira MCP Authentication

- **Method:** Jira API Token (Atlassian Cloud)
- **Jira URL:** `https://aq-r2d2.atlassian.net`
- **Username:** `arturoqu@microsoft.com`
- **Token:** Stored in `.env.deployment` (check container env vars if expired)
- **Known issue:** Token expires/becomes invalid periodically — causes `jira_create_issue` failures. Needs manual rotation.

### Container Apps → ACR

- **Method:** System-assigned managed identity on Container Apps
- **Config:** `az containerapp registry set --identity system`

### Application-Level Auth

- **Grocery API:** No auth — demo endpoints are public
- **Health endpoint:** `/health` — anonymous
- **Loki push:** No auth — HTTP push from API to Loki container

### Key Gotcha

When the SRE Agent gets a 403 Forbidden error accessing Azure resources, use the agent's managed identity client IDs above to create the appropriate role assignment:
```bash
az role assignment create --assignee <client-id> --role "<role-name>" --scope "<resource-id>"
```
