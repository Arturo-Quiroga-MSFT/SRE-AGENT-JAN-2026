# PIM MCP Server — gap-filler (ACTIVE)

> **Status: ACTIVE as of May 4, 2026** (revived after live testing).
> Single tool: `list_pending_pim_requests`.
> Uses **app-only** Graph auth via Managed Identity.

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
| `list_pending_pim_requests(top=25)` | List PIM requests with `status eq 'PendingApproval'`, expanded with principal + role definition |
| `health()` | Liveness probe |

Everything else (resolve user, list group members, check assignments,
read eligibilities, count licenses…) is done via the Microsoft
**Enterprise MCP server**'s `microsoft_graph_get` tool — not here.

## Required Graph application permissions

Grant to the agent's User-Assigned Managed Identity (object/principal ID):

| Scope | Why |
|---|---|
| `RoleAssignmentSchedule.ReadWrite.Directory` | **Actually required by Graph runtime** for LIST `roleAssignmentScheduleRequests` (see UPSTREAM_BUGS.md BUG-001). Latent only — server registers no write tools. |
| `RoleAssignmentSchedule.Read.Directory` | Documented least-privilege scope. Granted so the assignment becomes a no-op when Microsoft fixes the runtime. |

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
az acr build -r <acr-name> -t pim-mcp:0.2.0 mcp-servers/pim-mcp
```

Then set `pimMcpImage` parameter when running `azd up` /
`az deployment sub create`.

## Retire this server when…

Microsoft publishes `MCP.RoleAssignmentSchedule.ReadWrite.Directory`
(or equivalent write scope) on the Enterprise MCP server. At that point
the Foundry agent can call `microsoft_graph_get` for pending requests
too, and `infra/main.bicep` can stop deploying `pim-mcp-aca`. Track:
<https://github.com/microsoft/EnterpriseMCP/issues>.
