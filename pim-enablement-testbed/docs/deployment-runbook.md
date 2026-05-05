# PIM Enablement — Deployment Runbook

> Step-by-step setup. Assumes prerequisites in
> [`../README.md`](../README.md#prerequisites) are met.
>
> **May 4 2026 (post live-test):** runbook revised for the **hybrid** model.
> ~90% of PIM reads use the Microsoft-hosted MCP Server for Enterprise
> (delegated). The `roleAssignmentScheduleRequests` endpoint is unreachable
> via Enterprise MCP today, so we also deploy a single-tool custom MCP
> (`pim-mcp`) using app-only Graph auth via Managed Identity. See
> [`enterprise-mcp-setup.md`](enterprise-mcp-setup.md) and
> [`../mcp-servers/pim-mcp/README.md`](../mcp-servers/pim-mcp/README.md).

## 0. Variables

```bash
export AZURE_SUBSCRIPTION_ID="<your-test-sub>"
export AZURE_LOCATION="eastus2"
export RG_NAME="rg-pim-enablement-testbed"
export PREFIX="pimtest"
export TENANT_ID="<your-test-tenant-id>"
export SVC_ACCOUNT_UPN="svc-pim-enablement-agent@<tenant>"
export ACR_NAME="<your-acr>"                  # for the gap-filler pim-mcp image
export PIM_MCP_IMAGE="$ACR_NAME.azurecr.io/pim-mcp:0.2.0"
```

## 1. Provision the Microsoft MCP Server for Enterprise (one-time per tenant)

Follow [`enterprise-mcp-setup.md`](enterprise-mcp-setup.md):

1. `POST /servicePrincipals` to provision the MCP Server in the tenant.
2. Register a custom MCP Client app (record the App Id).
3. `Grant-EntraBetaMCPServerPermission` for the read-only `MCP.*` scopes.
4. Provision the service-account user (`$SVC_ACCOUNT_UPN`).
5. Make the service account PIM-eligible for read-only roles only.

```powershell
pwsh ./scripts/provision-enterprise-mcp.ps1 `
    -TenantId $TENANT_ID `
    -McpClientAppName "PIM Enablement Agent (test)" `
    -ServiceAccountUpn $SVC_ACCOUNT_UPN
```

## 2. Provision Azure infra

First, build and push the gap-filler `pim-mcp` image:

```bash
az acr build -r "$ACR_NAME" -t "pim-mcp:0.2.0" mcp-servers/pim-mcp
```

Then deploy:

```bash
az login --tenant "$TENANT_ID"
az account set --subscription "$AZURE_SUBSCRIPTION_ID"

az deployment sub create \
  --location "$AZURE_LOCATION" \
  --template-file infra/main.bicep \
  --parameters \
      location="$AZURE_LOCATION" \
      rgName="$RG_NAME" \
      prefix="$PREFIX" \
      pimMcpImage="$PIM_MCP_IMAGE"
```

Expected outputs:

- Resource group, Log Analytics, Container Apps environment
- Agent Managed Identity (used for Jira/Teams paths AND the `pim-mcp`
  Container App's Graph calls)
- `pim-mcp` Container App with public ingress (output: `pimMcpEndpoint`)

> Skip the gap-filler by omitting `pimMcpImage`. The infra still deploys but
> the agent will lack pending-request visibility — only useful if you
> intentionally want a Foundry-only smoke test.

### 2a. Grant the agent MI the Graph app roles for `pim-mcp`

```powershell
# AGENT_MI_PRINCIPAL_ID is the agentMiPrincipalId Bicep output from step 2.
pwsh ./scripts/grant-pim-mcp-app-role.ps1 `
    -TenantId $TENANT_ID `
    -AgentMiPrincipalId $AGENT_MI_PRINCIPAL_ID
```

This grants **both** `RoleAssignmentSchedule.ReadWrite.Directory` (what
the Graph runtime actually requires — see
[`UPSTREAM_BUGS.md`](UPSTREAM_BUGS.md) BUG-001) **and**
`RoleAssignmentSchedule.Read.Directory` (the documented least-privilege
scope, kept so the grant becomes a no-op when Microsoft fixes the
runtime). The compensating control: the `pim-mcp` server registers no
write tools — the elevated token is latent only. Required for `pim-mcp`
to call `/roleManagement/directory/roleAssignmentScheduleRequests`.

> **Propagation lag (operational).** After this grant the resource-side
> claim cache can take **5–60+ minutes** to honor the new role. If step 5
> smoke test returns `403 PermissionScopeNotGranted`, wait and retry —
> `az containerapp revision restart -n ca-${PREFIX}-pimmcp -g $RG_NAME`
> forces a fresh IMDS token but does NOT shorten the Graph-side cache.

## 3. Seed test users + groups + PIM-eligible assignments

```bash
pwsh ./scripts/seed-test-users.ps1 -TenantId $TENANT_ID
```

Capture the resulting user object IDs and group object IDs — paste them
into `agent/validation-rules.yaml`.

## 4. Wire the Foundry SRE Agent

1. Create a new agent in the Foundry workspace.
2. Paste `agent/knowledge.md` into the Knowledge section.
3. Add MCP connectors:
   - **Enterprise MCP Server** — `https://mcp.svc.cloud.microsoft/enterprise`
     - OAuth2 client = the MCP Client App registered in Step 1
     - Scope = `api://e8c77dc2-69b3-43f4-bc51-3213c9d915b4/.default`
     - Sign in as `$SVC_ACCOUNT_UPN` to grant initial consent
     - Used for: schedules, eligibilities, users, groups, licenses, org info
   - **PIM MCP (gap-filler)** — `pimMcpEndpoint` Bicep output (e.g.
     `https://ca-pimtest-pimmcp.<region>.azurecontainerapps.io`)
     - Transport: SSE (FastMCP default)
     - Auth: anonymous from Foundry's perspective; the `pim-mcp` Container App
       authenticates to Graph using its own MI. Restrict ingress to the
       Foundry connector subnet/IP range.
     - Used for: `list_pending_pim_requests` (the trigger)
   - **Jira MCP** — existing endpoint from Jan PoC
   - **Teams Webhook** — Logic App / Azure Function poster wrapping the
     Incoming Webhook URL
4. Configure scheduled trigger: every 60s, calling `pim-mcp → list_pending_pim_requests`.

Reference for the Foundry connector setup:
<https://learn.microsoft.com/graph/mcp-server/use-enterprise-mcp-server-microsoft-foundry>

## 5. Verify

```bash
./scripts/verify-deployment.sh
./scripts/trigger-pim-request.sh
```

Watch the approver Teams channel for the Adaptive Card.

Confirm Graph activity logs are flowing for **both** auth paths:

```kusto
// Enterprise MCP (delegated, as the service-account user)
MicrosoftGraphActivityLogs
| where TimeGenerated >= ago(1h)
| where AppId == "e8c77dc2-69b3-43f4-bc51-3213c9d915b4"
| project TimeGenerated, UserId, RequestMethod, RequestUri, ResponseStatusCode
| order by TimeGenerated desc

// pim-mcp gap-filler (app-only, as the agent MI)
// Replace <agent-mi-app-id> with the MI's appId (Bicep output: agentMiClientId).
MicrosoftGraphActivityLogs
| where TimeGenerated >= ago(1h)
| where AppId == "<agent-mi-app-id>"
| where RequestUri contains "roleAssignmentScheduleRequests"
| project TimeGenerated, RequestMethod, RequestUri, ResponseStatusCode
| order by TimeGenerated desc
```

## 6. Tear down

```bash
az group delete -n "$RG_NAME" --yes --no-wait
```

> Notes on cleanup:
>
> - PIM eligibility assignments live at the directory scope and are not
>   deleted with the RG. Clean those up separately via PowerShell.
> - The MCP Server service principal in the tenant is shared infra — do
>   NOT delete it unless you're sure no other workload uses it.
> - The custom MCP Client app and the service-account user can be
>   deleted via Entra admin center.
> - The agent MI's Graph app-role assignments
>   (`RoleAssignmentSchedule.ReadWrite.Directory` +
>   `RoleAssignmentSchedule.Read.Directory`) are auto-cleaned when the MI
>   is deleted (which happens with the RG). Verify in Entra → Enterprise
>   applications → Microsoft Graph → Permissions if you need to be sure.
