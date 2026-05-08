# PIM MCP Server — read-only Graph proxy (ACTIVE)

> **Status: ACTIVE as of May 8, 2026.** Image **0.4.1**. Streamable-HTTP at `/mcp`.
> Four tools: `list_pending_pim_requests`, `get_user`, `get_role_definition`, `health`.
> Uses **app-only** Graph auth via Managed Identity.
>
> **Scope expanded May 8, 2026** beyond the original 1-tool gap-filler. The SRE Agent's MCP connector wizard does not yet support delegated-OAuth, which blocks wiring Microsoft's Enterprise MCP server. We extended this server with a minimal user/role-resolver surface as a tactical workaround. Track the strategic fix (OAuth in the wizard) and contract this server back to its original 1-tool gap-filler scope when Enterprise MCP becomes wireable.

## Why this exists

The Microsoft-hosted [MCP Server for Enterprise](https://learn.microsoft.com/en-us/graph/mcp-server/overview)
covers ~90% of the PIM data we need (schedules, eligibilities, users,
groups), but the one endpoint that exposes pending PIM activation
requests — `/roleManagement/directory/roleAssignmentScheduleRequests` —
requires the **`RoleAssignmentSchedule.ReadWrite.Directory`** delegated
Graph permission. Microsoft Graph chose not to publish a delegated
read-only variant for the *Requests* collection ([Graph API reference](https://learn.microsoft.com/en-us/graph/api/rbacapplication-list-roleassignmentschedulerequests?view=graph-rest-1.0&tabs=http#permissions)),
and the Enterprise MCP server in current preview only mirrors `MCP.*.Read.*`
scopes. Net result: that endpoint is **structurally unreachable** through
Enterprise MCP today. Verified live in tenant `MngEnvMCAP094150` on
2026-05-04 with all 7 published `MCP.*` scopes granted and an active
Entra ID P2 license — endpoint still returns 403.

For **application** permissions, the Graph documentation states
`RoleAssignmentSchedule.Read.Directory` is sufficient for the same
endpoint. **In practice (verified live in `MngEnvMCAP094150` on
2026-05-05) the Graph runtime requires
`RoleAssignmentSchedule.ReadWrite.Directory`** even for the read-only
LIST call. See [`../../docs/UPSTREAM_BUGS.md`](../../docs/UPSTREAM_BUGS.md)
BUG-001. We grant **both** roles to the MI: `Read.Directory` to align
with the documented least-privilege scope (so the grant becomes a no-op
when Microsoft fixes the runtime) and `ReadWrite.Directory` because
that is what currently works. The compensating control is that this
server **registers no write tools** — the elevated token is latent only.
See [`../../docs/threat-model.md`](../../docs/threat-model.md) Residual
Risk #4.

This server uses a Managed Identity (app-only) to read pending requests.

## Compliance posture

- **Read-only by construction** — no write tool exists in this server.
  The agent cannot approve, deny, or modify a PIM request from here.
- **App-only auth** — pending-request reads happen as the app, not as a
  user. Document this distinction for the banking-compliance review.
- All Graph calls are captured in **Microsoft Graph activity logs**
  filterable by the MI's App ID.

## Tools

| Tool | Purpose |
|---|---|
| `list_pending_pim_requests(top=25)` | List PIM requests with `status eq 'PendingApproval'`. Returns ID, principal/role/scope, justification, ticket info, schedule. |
| `get_user(principal_id)` | Resolve an Entra ID object ID to displayName, UPN, mail, jobTitle, department, accountEnabled. |
| `get_role_definition(role_definition_id)` | Resolve a directory role definition GUID to displayName, description, isBuiltIn, resourceScopes. |
| `health()` | Liveness probe. |

## Required Graph application permissions

Grant to the agent's User-Assigned Managed Identity:

| Scope | Used by |
|---|---|
| `RoleAssignmentSchedule.ReadWrite.Directory` | `list_pending_pim_requests` — actually required by Graph runtime even for read (UPSTREAM_BUGS BUG-001). Latent only — server registers no write tools. |
| `RoleAssignmentSchedule.Read.Directory` | `list_pending_pim_requests` — documented least-privilege scope. |
| `User.Read.All` | `get_user` — added 2026-05-08. |
| `RoleManagement.Read.Directory` | `get_role_definition` — added 2026-05-08. |

Use the helper script (idempotent, grants both roles):

```powershell
pwsh ../../scripts/grant-pim-mcp-app-role.ps1 `
  -TenantId <tid> `
  -AgentMiPrincipalId <output from agent-mi.bicep>
```

> **Propagation lag.** After granting an app role to a Managed Identity,
> Graph's resource-side claim cache takes **5–60+ minutes** to honor it.
> If the first call returns `403 PermissionScopeNotGranted`, wait and
> retry; consider `az containerapp revision restart` to force a fresh
> IMDS token. See `threat-model.md` Residual Risk #5.

## Run locally

```bash
cd mcp-servers/pim-mcp
uv sync
AZURE_CLIENT_ID=<mi-client-id> uv run python server.py
```

## Build & push container

```bash
# from repo root
az acr build -r <acr-name> -t pim-mcp:0.4.1 mcp-servers/pim-mcp
```

Then set `pimMcpImage` parameter when running `azd up` /
`az deployment sub create`.

## Foundry SRE Agent connector wiring

| Field | Value |
|---|---|
| Connection type | **Streamable-HTTP** (NOT SSE — the wizard's path probes 404 against `/sse`) |
| URL | `https://<aca-fqdn>/mcp` |
| Authentication | Bearer token, value `not-required` (server does not validate; placeholder satisfies wizard) |

Note: explicit `path="/mcp"` (no trailing slash) in `server.py` is required to avoid Starlette Mount's slash-redirect that downgrades to plain HTTP behind ACA's HTTPS ingress.

## Retire this server when…

Microsoft publishes `MCP.RoleAssignmentSchedule.ReadWrite.Directory`
(or equivalent write scope) on the Enterprise MCP server. At that point
the Foundry agent can call `microsoft_graph_get` for pending requests
too, and `infra/main.bicep` can stop deploying `pim-mcp-aca`. Track:
<https://github.com/microsoft/EnterpriseMCP/issues>.
