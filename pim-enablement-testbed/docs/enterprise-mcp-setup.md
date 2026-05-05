# Microsoft MCP Server for Enterprise — Setup for the PIM Enablement Testbed

> One-time per-tenant provisioning + per-environment configuration for the
> Microsoft-hosted MCP server that the PIM Enablement agent uses.
>
> Source of truth: <https://learn.microsoft.com/en-us/graph/mcp-server/overview>
> Repo: <https://github.com/microsoft/EnterpriseMCP>

## What this is

The Microsoft MCP Server for Enterprise is a **Microsoft-hosted, remote
MCP server** at `https://mcp.svc.cloud.microsoft/enterprise` that
translates natural-language requests into Microsoft Graph API calls.
It exposes 3 tools:

| Tool | Purpose |
|---|---|
| `microsoft_graph_suggest_queries` | RAG over a curated catalog of Graph examples |
| `microsoft_graph_get` | Run read-only Graph calls under the user's privileges |
| `microsoft_graph_list_properties` | Schema lookup for Graph entities |

PIM is explicitly listed as an in-scope scenario for the public preview.
**Microsoft Foundry is a first-class client** (along with Copilot Studio,
ChatGPT, Claude, VS Code, GitHub Copilot CLI).

## Key facts to keep in mind

| Fact | Implication for us |
|---|---|
| **Delegated permissions only** (no app/MI auth) | Agent runs as a service-account user, not an MI |
| **Public cloud only** (sovereign clouds planned) | Fine for Zafin |
| **Read-only in current preview** (writes planned later) | Aligns with our compliance posture — agent must never write to PIM |
| 100 req/min/user throttle (on top of Graph limits) | Use `$select`/`$expand` to batch reads |
| Microsoft-hosted in same regions as Microsoft Graph | No infra to deploy on our side |
| `AppId = e8c77dc2-69b3-43f4-bc51-3213c9d915b4` | Filter Graph activity logs on this for audit |
| Entra ID P2 license required for PIM data | Confirm with Zafin |
| **`roleAssignmentScheduleRequests` endpoint not reachable** ([Graph API ref](https://learn.microsoft.com/en-us/graph/api/rbacapplication-list-roleassignmentschedulerequests?view=graph-rest-1.0&tabs=http#permissions)) | Pending PIM requests need our gap-filler `pim-mcp` (app-only auth via MI). See [`../mcp-servers/pim-mcp/README.md`](../mcp-servers/pim-mcp/README.md) |

## One-time tenant provisioning

> Required once per tenant. Needs a tenant admin with
> `Application.ReadWrite.All` and `DelegatedPermissionGrant.ReadWrite.All`.

### Step 1 — Provision the MCP Server service principal

Via [Graph Explorer](https://developer.microsoft.com/graph/graph-explorer)
or `az rest`:

```http
POST https://graph.microsoft.com/v1.0/servicePrincipals
Content-Type: application/json

{ "appId": "e8c77dc2-69b3-43f4-bc51-3213c9d915b4" }
```

This creates the MCP Server service principal in your tenant. Run once.

### Step 2 — Register a custom MCP Client app

In the Entra admin center → App registrations → New registration. Set
the redirect URI(s) appropriate to the client(s) you'll use:

| Client | Redirect URI |
|---|---|
| Microsoft Foundry connector | `https://<random>.<region>.azurecontainerapps.io/rest/oauth2-credential/callback` (Foundry generates this per connector) |
| Visual Studio Code / GH Copilot CLI | Use the built-in VS Code client app via `Grant-EntraBetaMCPServerPermission -ApplicationName VisualStudioCode` |
| Claude Desktop | `https://claude.ai/api/mcp/auth_callback` |

Record:

- **MCP Client App Id** (Application/Client ID) — used in agent config
- **Token URL**: `https://login.microsoftonline.com/organizations/oauth2/v2.0/token`
- **Auth URL**: `https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize`
- **Refresh URL**: same as Token URL
- **Token endpoint auth method**: `client_secret_post`
- **Scopes**: `api://e8c77dc2-69b3-43f4-bc51-3213c9d915b4/.default`

### Step 3 — Grant MCP scopes to the MCP Client app

Use PowerShell 7 + `Microsoft.Entra.Beta` ≥ 1.0.13:

```powershell
Install-Module Microsoft.Entra.Beta -Force -AllowClobber
Connect-Entra -Scopes 'Application.ReadWrite.All','DelegatedPermissionGrant.ReadWrite.All'

# For our PIM Enablement agent, the minimum useful scope set.
# IMPORTANT: scope names below are the ACTUAL published values discovered
# live in tenant MngEnvMCAP094150 on 2026-05-04 — NOT the names you might
# guess from the Graph docs. Role* scopes use `.Read.Directory`, NOT
# `.Read.All`. There is no `MCP.Directory.Read.All` scope.
Grant-EntraBetaMCPServerPermission `
    -ApplicationId "<MCP_Client_App_Id>" `
    -Scopes `
        "MCP.RoleManagement.Read.Directory", `
        "MCP.RoleEligibilitySchedule.Read.Directory", `
        "MCP.RoleAssignmentSchedule.Read.Directory", `
        "MCP.User.Read.All", `
        "MCP.GroupMember.Read.All", `
        "MCP.LicenseAssignment.Read.All", `
        "MCP.Organization.Read.All"
```

> **Why these names matter.** The MCP server publishes 41 scopes (May 2026).
> The Role-related ones use `.Read.Directory` to mirror the underlying Graph
> scope names exactly; user/group ones use `.Read.All`. Granting an unpublished
> name (e.g. `MCP.Directory.Read.All`) fails with
> *"Invalid scopes (not available on resource)"*. Always discover live before
> editing this list:
>
> ```powershell
> (Get-EntraBetaServicePrincipal -Property "PublishedPermissionScopes" `
>     -Filter "AppId eq 'e8c77dc2-69b3-43f4-bc51-3213c9d915b4'"
> ).PublishedPermissionScopes |
>     Where-Object { $_.IsEnabled -eq $true -and $_.AdditionalProperties["isPrivate"] -ne $true } |
>     Select-Object Value, AdminConsentDisplayName | Sort-Object Value
> ```

To revoke later:

```powershell
Revoke-EntraBetaMCPServerPermission -ApplicationId "<MCP_Client_App_Id>" -Scopes "<Scope1>","<Scope2>"
```

## Per-environment configuration

### Service-account user

Because auth is delegated-only, we need a **dedicated user** the agent
will sign in as for the scheduled-poll trigger.

Recommended posture:

- Naming: `svc-pim-enablement-agent@<tenant>`
- Licensing: minimum Entra ID P2 (PIM data access)
- Role: PIM-eligible for **read-only** roles only (`Reader`,
  `Monitoring Reader`, `Log Analytics Reader`). Do NOT grant approver
  rights.
- MFA: enforced via Conditional Access; use a **certificate-based**
  credential or a vaulted secret. No interactive password.
- Activity monitoring: alerts on any sign-in from outside the agent's
  Container App egress IPs.

Provisioning script: [`../scripts/provision-enterprise-mcp.ps1`](../scripts/provision-enterprise-mcp.ps1)
(scaffold).

### Foundry agent connector

In the Foundry workspace:

1. Add a new MCP connector pointing at
   `https://mcp.svc.cloud.microsoft/enterprise`.
2. Configure OAuth2 with the values from Step 2 above.
3. Use the redirect URI Foundry generates.
4. Sign in once as the service-account user to grant consent.
5. Attach the connector to the PIM Enablement agent.

Reference: <https://learn.microsoft.com/graph/mcp-server/use-enterprise-mcp-server-microsoft-foundry>

## Auditability

Every call made through the Enterprise MCP server is captured in
**Microsoft Graph activity logs**. Enable them in the tenant first
(<https://learn.microsoft.com/en-us/graph/microsoft-graph-activity-logs-overview>).

Sample Kusto query to retrieve all MCP-mediated calls in the last 30 days:

```kusto
MicrosoftGraphActivityLogs
| where TimeGenerated >= ago(30d)
| where AppId == "e8c77dc2-69b3-43f4-bc51-3213c9d915b4"
| project RequestId, TimeGenerated, UserId, RequestMethod, RequestUri, ResponseStatusCode
```

To filter to just the PIM Enablement service account, add:

```kusto
| where UserId == "<service-account-objectid>"
```

This satisfies F6 (audit trail) at the platform level. The Jira comment
is the per-recommendation supplement.

## Smoke test

Once provisioned, validate end-to-end with:

```bash
./scripts/verify-deployment.sh
```

The script confirms:

- The MCP Server service principal exists in the tenant
- The MCP Client app exists and has the expected scopes granted
- The service-account user can sign in and acquire a token for
  `api://e8c77dc2-69b3-43f4-bc51-3213c9d915b4/.default`

## Fallback / hybrid

The `roleAssignmentScheduleRequests` endpoint (the one that exposes
`status eq 'PendingApproval'`) is **not reachable** through Enterprise
MCP today — the Graph endpoint requires a `ReadWrite` delegated scope and
Enterprise MCP only mirrors `Read` scopes. We therefore deploy a tiny
gap-filler MCP server using app-only Graph auth via Managed Identity:

- Code: [`../mcp-servers/pim-mcp/`](../mcp-servers/pim-mcp/)
- Bicep: [`../infra/pim-mcp-aca.bicep`](../infra/pim-mcp-aca.bicep)
- Required Graph **app roles** on the agent MI: BOTH
  `RoleAssignmentSchedule.ReadWrite.Directory` (what Graph runtime
  actually demands — see [`UPSTREAM_BUGS.md`](UPSTREAM_BUGS.md) BUG-001)
  and `RoleAssignmentSchedule.Read.Directory` (documented least-privilege
  scope, kept so the grant becomes a no-op when Microsoft fixes the
  runtime). Compensating control: the server registers no write tool.
- Grant script: [`../scripts/grant-pim-mcp-app-role.ps1`](../scripts/grant-pim-mcp-app-role.ps1)
- End-to-end reproduction (assign eligibility → require approval →
  self-activate → verify): [`../scripts/REPRODUCE.md`](../scripts/REPRODUCE.md)

> **Troubleshooting — propagation lag.** After granting the Graph app
> roles to the MI, expect **5–60+ minutes** before the resource-side
> claim cache honors them. Symptoms during the lag: intermittent
> `403 PermissionScopeNotGranted` even though `az role assignment list`
> shows the grant. `az containerapp revision restart` forces a fresh
> IMDS token but does not shorten the Graph-side cache. Fully documented
> in [`UPSTREAM_BUGS.md`](UPSTREAM_BUGS.md) and `threat-model.md`
> Residual Risk #5.

If Microsoft eventually publishes `MCP.RoleAssignmentSchedule.ReadWrite.Directory`
or an equivalent scope on the Enterprise MCP server, retire the
gap-filler by setting `pimMcpImage=''` in `infra/main.bicep` and removing
the Foundry connector. Track:
<https://github.com/microsoft/EnterpriseMCP/issues>.
