"""PIM MCP tool implementations — read-only by construction.

Exposes thirteen tools across two API surfaces (no write tools, ever):

**Graph (directory-scope PIM — Entra roles like Global Admin):**

- ``list_pending_pim_requests`` — the trigger surface (PendingApproval only)
- ``list_pim_request_history`` — historical requests filtered by status / requester /
  time window (status + principal_id added 0.8.0; window_hours added 0.9.0)
- ``get_request_status`` — final disposition of a specific request by ID
- ``get_request_approver`` — audit trail: who approved/denied, when, with what justification
- ``list_active_role_assignments`` — currently-active assignments for a principal
- ``list_eligible_role_assignments`` — PIM-eligible assignments (added 0.7.0)
- ``get_user`` — resolve principalId to displayName/UPN/etc.
- ``get_user_group_memberships`` — transitive group memberships for a principal
  (added 0.9.0; closes validation rule R004)
- ``get_role_definition`` — resolve directory roleDefinitionId to displayName/etc.
- ``health`` — liveness probe

**ARM (Azure-RBAC PIM — Reader/Contributor/Owner at sub/RG/resource scope, added 0.10.0):**

- ``arm_get_request_status(scope, request_id)`` — ARM twin of ``get_request_status``,
  also parses ``durationHours`` from ``scheduleInfo.expiration.duration`` so the agent
  can evaluate R007 without payload fallback
- ``arm_get_request_approver(scope, request_id)`` — reads the governing
  ``roleManagementPolicyAssignment`` and returns the ``Approval_EndUser_Assignment``
  rule's primaryApprovers / approvalMode / stages
- ``arm_get_role_definition(scope, role_definition_id)`` — ARM twin of
  ``get_role_definition`` for Azure RBAC roles (Reader = ``acdd72a7-...``)

Routing: pick by scope. If `directoryScopeId` starts with ``/subscriptions/`` or
``/providers/Microsoft.Management/managementGroups/``, use the ARM tools.
Otherwise (``/``, ``/administrativeUnits/...``), use the Graph tools.

All responses that include a ``directoryScopeId`` are decorated server-side with
a human-readable ``directoryScopeLabel`` field (added 0.9.0). The label is
derived purely from the scope string — no extra Graph call. Unrecognised
patterns leave the label ``None``.

Auth: app-only via Managed Identity (``DefaultAzureCredential``). Per-resource
token cache (Graph and ARM tokens cached separately so they do not evict).

The primary Graph endpoint (``/v1.0/roleManagement/directory/roleAssignmentScheduleRequests``)
requires either:
- delegated ``RoleAssignmentSchedule.ReadWrite.Directory`` (not available
  through Microsoft's Enterprise MCP preview), or
- application ``RoleAssignmentSchedule.Read.Directory`` (this server uses this).

``get_request_approver`` calls the **beta** approvals endpoint
(``/beta/roleManagement/directory/roleAssignmentApprovals/{id}/steps``); it is the
only tool here that touches Graph beta. It requires the ``PrivilegedAccess.Read.AzureAD``
application permission.

The ARM tools require the MI to hold ``Reader`` (or stronger) on every scope it
will be asked about. No new Graph appRoles needed.

See https://learn.microsoft.com/en-us/graph/api/rbacapplication-list-roleassignmentschedulerequests
and https://learn.microsoft.com/en-us/azure/role-based-access-control/pim-resource-roles-rest-api
"""

from __future__ import annotations

import logging
import os
import re
from datetime import datetime, timedelta, timezone
from typing import Any

import httpx
from azure.identity import DefaultAzureCredential
from fastmcp import FastMCP

log = logging.getLogger("pim-mcp.tools")

GRAPH_BASE_URL = os.getenv("GRAPH_BASE_URL", "https://graph.microsoft.com/v1.0")
GRAPH_BETA_BASE_URL = os.getenv("GRAPH_BETA_BASE_URL", "https://graph.microsoft.com/beta")
GRAPH_SCOPE = "https://graph.microsoft.com/.default"
GRAPH_RESOURCE = "https://graph.microsoft.com"

# Azure Resource Manager (Wave C 0.10.0): symmetric coverage for PIM-on-Azure-resources.
# Graph endpoints only see directory-scope PIM (Entra roles like Global Admin).
# ARM endpoints see Azure-RBAC PIM (Reader/Contributor/Owner at sub/RG/resource scope).
ARM_BASE_URL = os.getenv("ARM_BASE_URL", "https://management.azure.com")
ARM_RESOURCE = "https://management.azure.com"
ARM_SCOPE = "https://management.azure.com/.default"
ARM_PIM_API_VERSION = "2020-10-01"
ARM_AUTHZ_API_VERSION = "2022-04-01"  # for roleDefinitions GET

PIM_REQUESTS_PATH = "/roleManagement/directory/roleAssignmentScheduleRequests"
PIM_INSTANCES_PATH = "/roleManagement/directory/roleAssignmentScheduleInstances"
PIM_ELIGIBLE_INSTANCES_PATH = "/roleManagement/directory/roleEligibilityScheduleInstances"
PIM_APPROVALS_PATH_BETA = "/roleManagement/directory/roleAssignmentApprovals"
USERS_PATH = "/users"
ROLE_DEFINITIONS_PATH = "/roleManagement/directory/roleDefinitions"

GROUP_MEMBERSHIP_DEFAULT_SELECT = "id,displayName,description,groupTypes,securityEnabled,mailEnabled,mailNickname"

USER_DEFAULT_SELECT = "id,displayName,userPrincipalName,mail,jobTitle,department,accountEnabled"
# Note: ``isPrivileged`` exists in beta but not v1.0 of unifiedRoleDefinition;
# stay v1.0-compatible so the $select doesn't 400.
ROLE_DEFINITION_DEFAULT_SELECT = "id,displayName,description,isBuiltIn,resourceScopes"

REQUEST_STATUS_SELECT = ",".join(
    [
        "id",
        "status",
        "action",
        "principalId",
        "roleDefinitionId",
        "directoryScopeId",
        "justification",
        "createdDateTime",
        "completedDateTime",
        "approvalId",
        "ticketInfo",
        "scheduleInfo",
    ]
)

INSTANCE_DEFAULT_SELECT = ",".join(
    [
        "id",
        "principalId",
        "roleDefinitionId",
        "directoryScopeId",
        "assignmentType",
        "memberType",
        "startDateTime",
        "endDateTime",
        "roleAssignmentOriginId",
        "roleAssignmentScheduleId",
    ]
)

# Eligibility instances have a slightly different shape than assignment
# instances: no `assignmentType` or `roleAssignmentOriginId`; the schedule
# back-pointer is `roleEligibilityScheduleId` instead.
ELIGIBLE_INSTANCE_DEFAULT_SELECT = ",".join(
    [
        "id",
        "principalId",
        "roleDefinitionId",
        "directoryScopeId",
        "appScopeId",
        "memberType",
        "startDateTime",
        "endDateTime",
        "roleEligibilityScheduleId",
    ]
)

# Default $select keeps the response small and predictable for the agent.
DEFAULT_SELECT = ",".join(
    [
        "id",
        "status",
        "action",
        "principalId",
        "roleDefinitionId",
        "directoryScopeId",
        "justification",
        "createdDateTime",
        "scheduleInfo",
        "ticketInfo",
    ]
)
DEFAULT_EXPAND = "principal($select=id,displayName,userPrincipalName),roleDefinition($select=id,displayName)"

_credential: DefaultAzureCredential | None = None
# Per-resource token cache. Keyed by resource URL so Graph and ARM tokens
# (different audiences) do not evict each other.
_token_cache: dict[str, dict[str, Any]] = {}


def _get_credential() -> DefaultAzureCredential:
    global _credential
    if _credential is None:
        _credential = DefaultAzureCredential()
    return _credential


async def _get_token(resource: str, scope: str) -> str:
    """Acquire an access token for ``resource`` (Graph or ARM), preferring
    direct IDENTITY_ENDPOINT calls with ``bypass_cache=true`` on Container Apps.

    Token caches are per-resource so Graph and ARM tokens do not evict each
    other (different audiences, different appRole grants).

    Container Apps IMDS sidecar caches tokens by (client_id, resource) for
    the full 24h lifetime and refuses to refresh until near expiry. This
    breaks newly-granted appRole permissions. We bypass that cache by:
      1. Hitting IDENTITY_ENDPOINT with ``bypass_cache=true`` to force a
         fresh token reflecting current appRole grants.
      2. Caching in-process for ~50 minutes to avoid IMDS on every call.
      3. Falling back to ``DefaultAzureCredential`` for local dev where
         IDENTITY_ENDPOINT is not set.
    """
    import time

    now = time.time()
    cached = _token_cache.get(resource)
    if cached and cached["exp"] - now > 60:
        return cached["token"]

    identity_endpoint = os.getenv("IDENTITY_ENDPOINT")
    identity_header = os.getenv("IDENTITY_HEADER")
    client_id = os.getenv("AZURE_CLIENT_ID")

    if identity_endpoint and identity_header and client_id:
        params = {
            "api-version": "2019-08-01",
            "resource": resource,
            "client_id": client_id,
            "bypass_cache": "true",
        }
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(
                identity_endpoint,
                params=params,
                headers={"X-IDENTITY-HEADER": identity_header},
            )
            resp.raise_for_status()
            data = resp.json()
            token = data["access_token"]
            exp = float(data.get("expires_on") or now + 3000)
            _token_cache[resource] = {"token": token, "exp": exp}
            return token

    token = _get_credential().get_token(scope).token
    _token_cache[resource] = {"token": token, "exp": now + 3000}
    return token


async def _get_graph_token() -> str:
    """Back-compat wrapper for the original Graph-only helper."""
    return await _get_token(GRAPH_RESOURCE, GRAPH_SCOPE)


async def _get_arm_token() -> str:
    """Acquire an Azure Resource Manager token (Wave C ARM tools)."""
    return await _get_token(ARM_RESOURCE, ARM_SCOPE)


async def _graph_get(path: str, params: dict[str, str] | None = None, *, beta: bool = False) -> dict[str, Any]:
    """Authenticated GET against Microsoft Graph (app-only via MI).

    Args:
        path: Graph path beginning with ``/`` (e.g. ``/users/{id}``).
        params: Optional query string params.
        beta: When True, hits the ``/beta`` endpoint instead of v1.0.
            Used only by ``get_request_approver`` (the approvals collection
            is beta-only).
    """
    token = await _get_graph_token()
    base = GRAPH_BETA_BASE_URL if beta else GRAPH_BASE_URL
    url = f"{base}{path}"
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.get(url, headers=headers, params=params)
        if resp.status_code >= 400:
            # Surface Graph's error body so MCP clients see the real cause
            # (e.g. PermissionScopeNotGranted, AadPremiumLicenseRequired).
            body = resp.text
            log.error("Graph %s -> %d: %s", url, resp.status_code, body)
            raise httpx.HTTPStatusError(
                f"Graph {resp.status_code} for {path}: {body}",
                request=resp.request,
                response=resp,
            )
        return resp.json()


async def _arm_get(path: str, api_version: str = ARM_PIM_API_VERSION) -> dict[str, Any]:
    """Authenticated GET against Azure Resource Manager (app-only via MI).

    Wave C 0.10.0 — companion to ``_graph_get`` for the three ARM tools that
    cover Azure-RBAC PIM (subscription/RG/resource scope). The MI must hold
    at minimum ``Reader`` on every scope it will be asked about; for the PIM
    request collection it specifically needs ``Microsoft.Authorization/
    roleAssignmentScheduleRequests/read`` (covered by Reader).

    Args:
        path: ARM path beginning with ``/`` (e.g. ``/subscriptions/{id}/...``).
        api_version: ARM api-version. Defaults to the PIM-on-Azure-resources
            version (``2020-10-01``). Use ``ARM_AUTHZ_API_VERSION`` for
            roleDefinitions reads.
    """
    token = await _get_arm_token()
    url = f"{ARM_BASE_URL}{path}"
    params = {"api-version": api_version}
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.get(url, headers=headers, params=params)
        if resp.status_code >= 400:
            body = resp.text
            log.error("ARM %s -> %d: %s", url, resp.status_code, body)
            raise httpx.HTTPStatusError(
                f"ARM {resp.status_code} for {path}: {body}",
                request=resp.request,
                response=resp,
            )
        return resp.json()


def _normalize_arm_scope(scope: str) -> str:
    """Normalize an ARM scope string for path concatenation.

    Accepts either a leading-slash form (``/subscriptions/...``) or a no-slash
    form (``subscriptions/...``). Returns the canonical leading-slash form
    with no trailing slash.
    """
    if not scope or not isinstance(scope, str):
        raise ValueError("scope must be a non-empty string (ARM resource path)")
    s = scope.strip()
    if not s.startswith("/"):
        s = "/" + s
    if len(s) > 1 and s.endswith("/"):
        s = s.rstrip("/")
    return s


# ---------------------------------------------------------------------------
# Scope label helper (0.9.0)
# ---------------------------------------------------------------------------
# PIM `directoryScopeId` values are opaque to humans (e.g. ``/`` means
# tenant-wide). We attach a ``directoryScopeLabel`` next to every scope-bearing
# row so the agent and any downstream UI can show readable text without an
# extra Graph round-trip. Pattern-matching only \u2014 no Graph calls.

_AU_RE = re.compile(r"^/administrativeUnits/(?P<id>[0-9a-fA-F-]{36})$")
_SUB_RE = re.compile(r"^/subscriptions/(?P<sub>[0-9a-fA-F-]{36})$")
_RG_RE = re.compile(
    r"^/subscriptions/(?P<sub>[0-9a-fA-F-]{36})/resourceGroups/(?P<rg>[^/]+)$",
    re.IGNORECASE,
)


def _resolve_directory_scope_label(scope_id: str | None) -> str | None:
    """Translate a PIM ``directoryScopeId`` into a human-readable label.

    Returns ``None`` for unrecognised scope strings so callers can decide
    whether to omit the label or echo the raw ID.
    """
    if not scope_id:
        return None
    if scope_id == "/":
        return "Entire directory (tenant-wide)"
    if scope_id.startswith("/roleManagement/directory"):
        return "Directory role management"
    m = _AU_RE.match(scope_id)
    if m:
        return f"Administrative Unit ({m.group('id')})"
    m = _RG_RE.match(scope_id)
    if m:
        return f"Resource Group '{m.group('rg')}' in subscription {m.group('sub')}"
    m = _SUB_RE.match(scope_id)
    if m:
        return f"Subscription {m.group('sub')}"
    return None


def _decorate_scope(row: dict[str, Any]) -> dict[str, Any]:
    """Add ``directoryScopeLabel`` to a row that carries ``directoryScopeId``.

    Mutates and returns the same dict for convenience. No-op when the field
    is absent or already labelled.
    """
    if not isinstance(row, dict):
        return row
    if "directoryScopeId" in row and "directoryScopeLabel" not in row:
        row["directoryScopeLabel"] = _resolve_directory_scope_label(row.get("directoryScopeId"))
    return row


def _decorate_scope_list(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    for r in rows:
        _decorate_scope(r)
    return rows


def register_tools(mcp: FastMCP) -> None:
    """Register the PIM read tools with the MCP server."""

    @mcp.tool()
    async def list_pending_pim_requests(top: int = 25) -> dict[str, Any]:
        """List PIM role-assignment requests in ``PendingApproval`` state.

        This is the trigger endpoint for the SRE Agent: it returns the
        requests an approver has not yet acted on. Read-only.

        Args:
            top: Max number of requests to return (1-100). Defaults to 25.

        Returns:
            JSON object with a ``value`` array of pending request objects.
            Each object includes the principal, role definition, scope,
            justification, ticket info, and schedule.
        """
        top = max(1, min(int(top), 100))
        # Graph rejects $filter, $orderby, AND $expand on this collection
        # (verified live 2026-05-05 — see ../../../docs/UPSTREAM_BUGS.md BUG-002).
        # Fetch raw page with only $select and $top, then filter client-side.
        # Principal/roleDefinition are returned as IDs; the agent can resolve
        # them via Enterprise MCP if needed.
        params = {
            "$select": DEFAULT_SELECT,
            "$top": str(min(top * 4, 100)),
        }
        log.info("list_pending_pim_requests top=%d", top)
        raw = await _graph_get(PIM_REQUESTS_PATH, params)
        all_items = raw.get("value", [])
        pending = [r for r in all_items if r.get("status") == "PendingApproval"][:top]
        _decorate_scope_list(pending)
        return {
            "value": pending,
            "@odata.context": raw.get("@odata.context"),
            "fetchedCount": len(all_items),
            "pendingCount": len(pending),
            "hint": (
                "This tool only returns PendingApproval requests. To check the "
                "final disposition of a request that is no longer pending, call "
                "get_request_status(request_id). To find out who approved/denied "
                "a request and read their justification, call "
                "get_request_approver(request_id). To see currently-active role "
                "assignments for a user, call list_active_role_assignments(principal_id)."
            ),
        }

    @mcp.tool()
    async def health() -> dict[str, str]:
        """Liveness probe."""
        return {"status": "ok"}

    @mcp.tool()
    async def get_user(principal_id: str) -> dict[str, Any]:
        """Resolve a directory principal (user) by object ID.

        Use this to translate a ``principalId`` (e.g. from
        ``list_pending_pim_requests``) into a human-readable identity:
        displayName, userPrincipalName, mail, jobTitle, department, and
        whether the account is enabled.

        Read-only. Requires ``User.Read.All`` application permission on the
        server's managed identity.

        Args:
            principal_id: Entra ID object ID (GUID) of the user.

        Returns:
            JSON object with the selected user properties, or a Graph error
            payload (e.g. 404 if not a user / not found).
        """
        if not principal_id or not isinstance(principal_id, str):
            raise ValueError("principal_id must be a non-empty string (Entra object ID)")
        log.info("get_user principal_id=%s", principal_id)
        return await _graph_get(
            f"{USERS_PATH}/{principal_id}",
            params={"$select": USER_DEFAULT_SELECT},
        )

    @mcp.tool()
    async def get_user_group_memberships(
        principal_id: str,
        top: int = 100,
    ) -> dict[str, Any]:
        """List the transitive group memberships of a directory principal.

        Calls ``GET /users/{id}/transitiveMemberOf`` to return every group
        the user belongs to directly *or* through nested group membership.
        Use this to evaluate validation rule **R004** (group-membership
        gating) for PIM activation requests — e.g., to confirm the
        requester is in an approved on-call rotation group before
        recommending APPROVE.

        Returned rows are filtered server-side to ``#microsoft.graph.group``
        only (the same call can return ``directoryRole`` rows for users
        who hold tenant roles directly; those are excluded here so the
        agent doesn't conflate group membership with role assignment).

        Read-only. Requires ``GroupMember.Read.All`` application
        permission on the server's managed identity (added 0.9.0).

        Args:
            principal_id: Entra ID object ID (GUID) of the user.
            top: Max rows to return (1-200). Defaults to 100.

        Returns:
            JSON object with:
              - ``value``: array of group objects, each with ``id``,
                ``displayName``, ``description``, ``groupTypes``,
                ``securityEnabled``, ``mailEnabled``, ``mailNickname``.
              - ``count``: number of rows returned.
              - ``principalId``: echo of the input.
        """
        if not principal_id or not isinstance(principal_id, str):
            raise ValueError("principal_id must be a non-empty string (Entra object ID)")
        top = max(1, min(int(top), 200))
        log.info("get_user_group_memberships principal_id=%s top=%d", principal_id, top)
        raw = await _graph_get(
            f"{USERS_PATH}/{principal_id}/transitiveMemberOf",
            params={
                "$select": GROUP_MEMBERSHIP_DEFAULT_SELECT,
                "$top": str(top),
            },
        )
        items = raw.get("value", [])
        # Keep groups only — drop any directoryRole rows so callers can
        # treat the response as "groups the user belongs to".
        groups = [r for r in items if r.get("@odata.type") == "#microsoft.graph.group"]
        return {
            "value": groups,
            "@odata.context": raw.get("@odata.context"),
            "count": len(groups),
            "principalId": principal_id,
        }

    @mcp.tool()
    async def get_role_definition(role_definition_id: str) -> dict[str, Any]:
        """Resolve a directory role definition by ID.

        Use this to translate a ``roleDefinitionId`` (e.g. from
        ``list_pending_pim_requests``) into a human-readable role:
        displayName, description, isBuiltIn, resourceScopes. (Note: the
        ``isPrivileged`` property exists only on the Graph beta endpoint;
        this tool stays on v1.0 and does not surface it.)

        Read-only. Requires ``RoleManagement.Read.Directory`` application
        permission on the server's managed identity.

        Args:
            role_definition_id: GUID of the directory role definition.

        Returns:
            JSON object with the selected role definition properties.
        """
        if not role_definition_id or not isinstance(role_definition_id, str):
            raise ValueError("role_definition_id must be a non-empty string (GUID)")
        log.info("get_role_definition id=%s", role_definition_id)
        return await _graph_get(
            f"{ROLE_DEFINITIONS_PATH}/{role_definition_id}",
            params={"$select": ROLE_DEFINITION_DEFAULT_SELECT},
        )

    @mcp.tool()
    async def get_request_status(request_id: str) -> dict[str, Any]:
        """Get the current state and final disposition of a single PIM request.

        Use this when ``list_pending_pim_requests`` no longer returns a request
        you previously saw — to determine whether it was approved, denied,
        cancelled, expired, or failed. Closes the disposition gap that
        ``list_pending_pim_requests`` (PendingApproval-only) leaves behind.

        Common ``status`` values returned by Graph for this collection:
        ``PendingApproval``, ``Granted``, ``Provisioned``, ``Denied``,
        ``Failed``, ``Canceled``, ``Revoked``.

        Read-only. Same Graph permission as ``list_pending_pim_requests``
        (``RoleAssignmentSchedule.Read.Directory`` application).

        Args:
            request_id: GUID of the role assignment schedule request.

        Returns:
            JSON object with id, status, action, principalId, roleDefinitionId,
            directoryScopeId, justification, createdDateTime, completedDateTime,
            approvalId, ticketInfo, and scheduleInfo.
        """
        if not request_id or not isinstance(request_id, str):
            raise ValueError("request_id must be a non-empty string (GUID)")
        log.info("get_request_status request_id=%s", request_id)
        result = await _graph_get(
            f"{PIM_REQUESTS_PATH}/{request_id}",
            params={"$select": REQUEST_STATUS_SELECT},
        )
        return _decorate_scope(result)

    @mcp.tool()
    async def list_active_role_assignments(
        principal_id: str,
        top: int = 25,
    ) -> dict[str, Any]:
        """List currently-active directory role assignments for a principal.

        Returns rows from ``roleAssignmentScheduleInstances`` — these are the
        assignments that are *currently in effect*, including those activated
        from PIM eligibilities. Use this to confirm post-approval that a
        requester actually has the role active, or to audit who currently
        holds privileged access.

        Read-only. Requires ``RoleAssignmentSchedule.Read.Directory``
        application permission on the server's managed identity.

        Args:
            principal_id: Entra ID object ID (GUID) of the principal.
            top: Max rows to return (1-100). Defaults to 25.

        Returns:
            JSON object with a ``value`` array of active assignment instances.
            Each row includes assignmentType (Eligible/Assigned), memberType,
            startDateTime, endDateTime (null for permanent), and the schedule
            and origin IDs.
        """
        if not principal_id or not isinstance(principal_id, str):
            raise ValueError("principal_id must be a non-empty string (Entra object ID)")
        top = max(1, min(int(top), 100))
        # Graph supports $filter on principalId for this collection.
        params = {
            "$filter": f"principalId eq '{principal_id}'",
            "$select": INSTANCE_DEFAULT_SELECT,
            "$top": str(top),
        }
        log.info("list_active_role_assignments principal_id=%s top=%d", principal_id, top)
        raw = await _graph_get(PIM_INSTANCES_PATH, params)
        items = raw.get("value", [])
        _decorate_scope_list(items)
        return {
            "value": items,
            "@odata.context": raw.get("@odata.context"),
            "count": len(items),
        }

    @mcp.tool()
    async def list_eligible_role_assignments(
        principal_id: str | None = None,
        top: int = 50,
    ) -> dict[str, Any]:
        """List PIM-eligible directory role assignments.

        Returns rows from ``roleEligibilityScheduleInstances`` — these are the
        eligibilities that *could be activated* via PIM (i.e., who has the
        right to activate which role, not who currently holds it). Use this
        to answer "who is eligible for role X?" or "what roles can user Y
        activate?". For currently-active assignments, use
        ``list_active_role_assignments`` instead.

        Read-only. Requires either ``RoleEligibilitySchedule.Read.Directory``
        or ``RoleManagement.Read.Directory`` application permission on the
        server's managed identity. The latter is already granted (used by
        ``get_role_definition``), so no new app-role assignment is strictly
        required to enable this tool.

        Why this tool exists: Microsoft's Enterprise MCP CAN serve this
        endpoint with delegated auth, but the Azure SRE Agent's MCP wizard
        cannot wire up Enterprise MCP today (delegated-OAuth gap, testbed
        roadblock #3). This tool is the agent-side workaround until that
        wizard limitation is lifted.

        Args:
            principal_id: Optional Entra ID object ID (GUID). When provided,
                filters to eligibilities for that principal. When omitted,
                returns all eligibilities tenant-wide (capped by ``top``).
            top: Max rows to return (1-100). Defaults to 50.

        Returns:
            JSON object with a ``value`` array of eligibility instances.
            Each row includes principalId, roleDefinitionId, directoryScopeId,
            memberType (Direct/Group/Inherited), startDateTime, endDateTime
            (null for permanent eligibilities), and roleEligibilityScheduleId.
            Pair with ``get_user`` and ``get_role_definition`` for human-
            readable output.
        """
        top = max(1, min(int(top), 100))
        params: dict[str, str] = {
            "$select": ELIGIBLE_INSTANCE_DEFAULT_SELECT,
            "$top": str(top),
        }
        if principal_id:
            if not isinstance(principal_id, str):
                raise ValueError("principal_id must be a string (Entra object ID) when provided")
            params["$filter"] = f"principalId eq '{principal_id}'"
        log.info(
            "list_eligible_role_assignments principal_id=%s top=%d",
            principal_id or "<all>",
            top,
        )
        raw = await _graph_get(PIM_ELIGIBLE_INSTANCES_PATH, params)
        items = raw.get("value", [])
        _decorate_scope_list(items)
        return {
            "value": items,
            "@odata.context": raw.get("@odata.context"),
            "count": len(items),
        }

    @mcp.tool()
    async def list_pim_request_history(
        status: str | None = None,
        principal_id: str | None = None,
        window_hours: int | None = None,
        top: int = 25,
    ) -> dict[str, Any]:
        """List historical PIM role-assignment requests (any status except pending).

        Closes the "browse all requests" gap left by
        ``list_pending_pim_requests``, which only returns rows in
        ``PendingApproval``. This tool returns *non-pending* rows from the
        same Graph collection — i.e., the disposition history (Provisioned,
        Denied, Cancelled, Expired, etc.).

        For the final state of a *specific* request whose ID you already
        know, use ``get_request_status`` instead — it's a direct GET and
        avoids fetching the whole collection.

        Read-only. Same Graph permission as ``list_pending_pim_requests``
        (``RoleAssignmentSchedule.ReadWrite.Directory`` per UPSTREAM_BUGS
        BUG-001), so no new app-role grant is required.

        BUG-002 caveat: Graph rejects ``$filter``, ``$orderby``, and
        ``$expand`` on this collection. We fetch the raw page with only
        ``$select`` and ``$top``, then filter / sort client-side. This
        means the ``top`` cap is approximate — we over-fetch (up to 100,
        Graph's max) and trim after filtering.

        Args:
            status: Optional case-insensitive status filter. Examples:
                ``"Provisioned"`` (approved + activated), ``"Denied"``,
                ``"Cancelled"``, ``"Expired"``, ``"Failed"``,
                ``"Revoked"``. When omitted, returns all non-pending
                statuses. PendingApproval rows are always excluded — use
                ``list_pending_pim_requests`` for those.
            principal_id: Optional Entra Object ID (GUID) to filter by
                requester. When omitted, returns rows for all principals.
            window_hours: Optional time window. When provided, only rows
                with ``createdDateTime`` within the last N hours are
                returned. Useful for activation-frequency checks (rule
                R008) and "last 24h" audit views. Must be 1..720 (30 days).
            top: Max rows to return after client-side filtering (1-100).
                Defaults to 25.

        Returns:
            JSON object with a ``value`` array sorted by
            ``createdDateTime`` desc (most recent first). Each row
            includes id, status, action, principalId, roleDefinitionId,
            directoryScopeId, ``directoryScopeLabel`` (0.9.0 — human
            readable scope), justification, createdDateTime,
            scheduleInfo, ticketInfo. Diagnostics fields:
            ``fetchedCount`` (raw page size from Graph),
            ``matchedCount`` (rows that passed the filter),
            ``returnedCount`` (rows after ``top`` trim).
        """
        top = max(1, min(int(top), 100))
        cutoff: datetime | None = None
        if window_hours is not None:
            window_hours_int = int(window_hours)
            if window_hours_int < 1 or window_hours_int > 720:
                raise ValueError("window_hours must be between 1 and 720 (30 days)")
            cutoff = datetime.now(timezone.utc) - timedelta(hours=window_hours_int)
        # Over-fetch the maximum page Graph allows (100), then filter
        # client-side. BUG-002: $filter/$orderby/$expand all rejected.
        params = {
            "$select": DEFAULT_SELECT,
            "$top": "100",
        }
        log.info(
            "list_pim_request_history status=%s principal_id=%s window_hours=%s top=%d",
            status or "<any-non-pending>",
            principal_id or "<all>",
            window_hours if window_hours is not None else "<all>",
            top,
        )
        raw = await _graph_get(PIM_REQUESTS_PATH, params)
        all_items = raw.get("value", [])

        status_lc = status.lower() if status else None
        if status_lc == "pendingapproval":
            raise ValueError(
                "PendingApproval is not supported here — use list_pending_pim_requests instead"
            )

        def _matches(row: dict[str, Any]) -> bool:
            row_status = (row.get("status") or "").lower()
            if row_status == "pendingapproval":
                return False
            if status_lc and row_status != status_lc:
                return False
            if principal_id and row.get("principalId") != principal_id:
                return False
            if cutoff is not None:
                created = row.get("createdDateTime")
                if not created:
                    return False
                try:
                    # Graph returns ISO-8601 with trailing Z; parse as UTC.
                    parsed = datetime.fromisoformat(created.replace("Z", "+00:00"))
                except ValueError:
                    return False
                if parsed < cutoff:
                    return False
            return True

        matched = [r for r in all_items if _matches(r)]
        # Sort newest-first by createdDateTime (string ISO-8601 sorts correctly).
        matched.sort(key=lambda r: r.get("createdDateTime") or "", reverse=True)
        trimmed = matched[:top]
        _decorate_scope_list(trimmed)
        return {
            "value": trimmed,
            "@odata.context": raw.get("@odata.context"),
            "fetchedCount": len(all_items),
            "matchedCount": len(matched),
            "returnedCount": len(trimmed),
            "windowHours": window_hours,
            "hint": (
                "Historical requests only (PendingApproval excluded). For "
                "a specific known request ID, prefer get_request_status. "
                "For approver identity / justification on a disposed "
                "request, call get_request_approver(request_id)."
            ),
        }

    @mcp.tool()
    async def get_request_approver(request_id: str) -> dict[str, Any]:
        """Get the audit trail for a PIM request: who approved/denied, when, why.

        Two-step lookup performed server-side in one tool call:
        1. GET the request to find its ``approvalId``.
        2. GET the approval's ``steps`` collection (beta endpoint) to read each
           reviewer's identity, decision, timestamp, and justification.

        Use this for compliance / audit questions like "who approved request X?"
        or "what justification did the approver provide?". Most tenants have a
        single approval step; multi-stage approval policies return multiple.

        Read-only. Beta endpoint. Requires the ``PrivilegedAccess.Read.AzureAD``
        application permission on the server's managed identity (in addition to
        ``RoleAssignmentSchedule.Read.Directory`` for the request lookup).

        Args:
            request_id: GUID of the role assignment schedule request.

        Returns:
            JSON object with:
              - ``requestId``: echo of the input
              - ``approvalId``: the approval record ID (often equal to requestId)
              - ``requestStatus``: current request status (Provisioned/Denied/...)
              - ``steps``: array of approval step objects, each with
                ``id``, ``status`` (NotStarted/InProgress/Completed),
                ``reviewResult`` (Approve/Deny/NotReviewed), ``reviewedDateTime``,
                ``justification``, and ``reviewedBy`` (id, displayName, userPrincipalName).
        """
        if not request_id or not isinstance(request_id, str):
            raise ValueError("request_id must be a non-empty string (GUID)")
        log.info("get_request_approver request_id=%s", request_id)

        # Step 1: get the request to find approvalId + status (v1.0).
        request = await _graph_get(
            f"{PIM_REQUESTS_PATH}/{request_id}",
            params={"$select": "id,status,approvalId"},
        )
        approval_id = request.get("approvalId")
        if not approval_id:
            return {
                "requestId": request_id,
                "approvalId": None,
                "requestStatus": request.get("status"),
                "steps": [],
                "note": "Request has no approvalId — it was likely auto-approved (no approver in policy) or self-activated without approval gate.",
            }

        # Step 2: get the approval steps (beta).
        approval = await _graph_get(
            f"{PIM_APPROVALS_PATH_BETA}/{approval_id}/steps",
            beta=True,
        )
        return {
            "requestId": request_id,
            "approvalId": approval_id,
            "requestStatus": request.get("status"),
            "steps": approval.get("value", []),
            "@odata.context": approval.get("@odata.context"),
        }

    # ---------------------------------------------------------------------
    # Wave C 0.10.0 — ARM (Azure-RBAC PIM) tools
    # ---------------------------------------------------------------------
    # The three tools below are the ARM-scoped twins of get_request_status,
    # get_request_approver, and get_role_definition. They cover PIM activations
    # at subscription / resource-group / resource scope (Reader, Contributor,
    # Owner, etc.) — which the Graph endpoints above do NOT see (Graph only
    # serves directory-scoped PIM for Entra roles like Global Admin).
    #
    # The MI must hold ``Reader`` (or stronger) on the scope being read.
    # No new Graph appRoles required.

    @mcp.tool()
    async def arm_get_request_status(scope: str, request_id: str) -> dict[str, Any]:
        """Get the current state of a PIM-on-Azure-resources activation request.

        ARM-scoped twin of ``get_request_status``. Use when the request lives
        at subscription/RG/resource scope (Azure RBAC roles like Reader,
        Contributor, Owner) rather than tenant directory scope. The Graph
        version returns 404 for these requests because the resource graph
        and directory graph are separate API surfaces.

        Returns enough detail for the agent to evaluate validation rules
        without falling back to the trigger payload — specifically
        ``properties.scheduleInfo.expiration.duration`` (R007) and
        ``properties.justification`` (audit trail).

        Read-only. Requires the MI to hold ``Reader`` (or stronger) on
        ``scope``. No new appRole grants needed.

        Args:
            scope: Full ARM scope path of the request, e.g.
                ``/subscriptions/{sub}/resourceGroups/{rg}``. The leading
                slash is optional and will be normalized.
            request_id: GUID of the role assignment schedule request, as
                returned by the SelfActivate POST.

        Returns:
            JSON envelope with:
              - ``requestId``: echo of the input
              - ``scope``: normalized scope
              - ``status``: ``properties.status`` (PendingApproval,
                Provisioned, Denied, Failed, Cancelled, Revoked, ...)
              - ``durationHours``: parsed integer hours from
                ``scheduleInfo.expiration.duration`` (e.g. ``"PT1H"`` -> 1).
                ``None`` when expiration is type ``NoExpiration`` or the
                duration is not parseable.
              - ``justification``: requester's justification text
              - ``ticketInfo``: Jira/ServiceNow ticket metadata if supplied
              - ``raw``: the full ARM response body for callers needing more
        """
        if not request_id or not isinstance(request_id, str):
            raise ValueError("request_id must be a non-empty string (GUID)")
        scope_norm = _normalize_arm_scope(scope)
        path = (
            f"{scope_norm}/providers/Microsoft.Authorization"
            f"/roleAssignmentScheduleRequests/{request_id}"
        )
        log.info("arm_get_request_status scope=%s request_id=%s", scope_norm, request_id)
        raw = await _arm_get(path, api_version=ARM_PIM_API_VERSION)
        props = raw.get("properties", {}) or {}

        # Parse PT<H>H or PT<M>M out of scheduleInfo.expiration.duration.
        # Most PIM activations use whole-hour ISO-8601 durations (PT1H..PT8H);
        # we support minutes too for completeness but round to hours.
        duration_hours: int | None = None
        sched = props.get("scheduleInfo") or {}
        expiration = sched.get("expiration") or {}
        dur = expiration.get("duration")
        if isinstance(dur, str):
            m = re.match(r"^PT(?:(?P<h>\d+)H)?(?:(?P<m>\d+)M)?$", dur)
            if m and (m.group("h") or m.group("m")):
                hours = int(m.group("h") or 0)
                minutes = int(m.group("m") or 0)
                duration_hours = hours + (1 if minutes >= 30 else 0)

        return {
            "requestId": request_id,
            "scope": scope_norm,
            "status": props.get("status"),
            "durationHours": duration_hours,
            "expirationType": expiration.get("type"),
            "justification": props.get("justification"),
            "ticketInfo": props.get("ticketInfo"),
            "principalId": props.get("principalId"),
            "roleDefinitionId": props.get("roleDefinitionId"),
            "createdOn": props.get("createdOn"),
            "raw": raw,
        }

    @mcp.tool()
    async def arm_get_request_approver(scope: str, request_id: str) -> dict[str, Any]:
        """Get approver identity / decision for a PIM-on-Azure-resources request.

        ARM-scoped twin of ``get_request_approver``. Reads the policy
        assignment that governs the role at ``scope`` and returns its
        ``Approval_EndUser_Assignment`` rule's ``primaryApprovers`` and
        ``approvalMode``. For single-stage approval policies with one
        configured approver this gives the agent the same audit signal as
        the Graph approval-steps endpoint without needing a per-request
        callback.

        Limitations:
          - For multi-stage policies, returns all stages in declaration order.
          - For dynamic-approver policies (e.g. requester's manager), returns
            the policy rule shape rather than the resolved approver identity.
          - Does not return per-request decision timestamps (ARM's PIM data
            model does not expose them at the schedule-request level the way
            Graph approval steps do). For final disposition use
            ``arm_get_request_status``.\u00a0The intersection of "policy says X
            is the approver" + "request status flipped to Provisioned" is
            sufficient for most single-approver audit needs.

        Read-only. Requires the MI to hold ``Reader`` (or stronger) on
        ``scope``.

        Args:
            scope: ARM scope path of the request.
            request_id: GUID of the role assignment schedule request (used
                to look up the role and resolve the governing policy).

        Returns:
            JSON envelope with:
              - ``requestId``: echo of the input
              - ``scope``: normalized scope
              - ``roleDefinitionId``: ARM role definition ID from the request
              - ``policyAssignmentName``: name of the resolved policy assignment
              - ``approvalRequired``: bool
              - ``approvalMode``: ``SingleStage`` / ``Serial`` / ``NoApproval``
              - ``stages``: list of stage objects, each with
                ``approverType``, ``primaryApprovers`` (id/userType/displayName)
        """
        if not request_id or not isinstance(request_id, str):
            raise ValueError("request_id must be a non-empty string (GUID)")
        scope_norm = _normalize_arm_scope(scope)

        # Step 1: read the request to discover its roleDefinitionId.
        req_path = (
            f"{scope_norm}/providers/Microsoft.Authorization"
            f"/roleAssignmentScheduleRequests/{request_id}"
        )
        log.info("arm_get_request_approver scope=%s request_id=%s", scope_norm, request_id)
        request = await _arm_get(req_path, api_version=ARM_PIM_API_VERSION)
        role_def_id = (request.get("properties") or {}).get("roleDefinitionId")
        if not role_def_id:
            return {
                "requestId": request_id,
                "scope": scope_norm,
                "roleDefinitionId": None,
                "approvalRequired": None,
                "approvalMode": None,
                "stages": [],
                "note": "Request has no roleDefinitionId — cannot resolve policy.",
            }

        # Step 2: list policy assignments at scope and find the one for this role.
        # ARM filter syntax: $filter=atScope() and roleDefinitionId eq '<id>'
        # The API accepts the filter on the GET collection.
        from urllib.parse import quote as _q

        filt = f"atScope() and roleDefinitionId eq '{role_def_id}'"
        safe_chars = "=' "
        pa_path = (
            f"{scope_norm}/providers/Microsoft.Authorization"
            f"/roleManagementPolicyAssignments?$filter={_q(filt, safe=safe_chars)}"
        )
        # _arm_get appends api-version itself; embed $filter in the path so it
        # survives intact (httpx params would re-encode the quotes).
        pa_resp = await _arm_get(pa_path, api_version=ARM_PIM_API_VERSION)
        pa_list = pa_resp.get("value", []) or []
        if not pa_list:
            return {
                "requestId": request_id,
                "scope": scope_norm,
                "roleDefinitionId": role_def_id,
                "approvalRequired": None,
                "approvalMode": None,
                "stages": [],
                "note": "No roleManagementPolicyAssignment found for this role at scope.",
            }
        pa = pa_list[0]
        policy_id = (pa.get("properties") or {}).get("policyId")
        pa_name = pa.get("name")
        if not policy_id:
            return {
                "requestId": request_id,
                "scope": scope_norm,
                "roleDefinitionId": role_def_id,
                "policyAssignmentName": pa_name,
                "approvalRequired": None,
                "approvalMode": None,
                "stages": [],
                "note": "Policy assignment lacks policyId.",
            }

        # Step 3: GET the policy and pull the Approval_EndUser_Assignment rule.
        # policyId is itself a full ARM resource path beginning with '/subscriptions/...'
        policy = await _arm_get(policy_id, api_version=ARM_PIM_API_VERSION)
        rules = (policy.get("properties") or {}).get("rules") or []
        approval_rule = next(
            (
                r
                for r in rules
                if r.get("id") == "Approval_EndUser_Assignment"
                or r.get("ruleType") == "RoleManagementPolicyApprovalRule"
            ),
            None,
        )
        if not approval_rule:
            return {
                "requestId": request_id,
                "scope": scope_norm,
                "roleDefinitionId": role_def_id,
                "policyAssignmentName": pa_name,
                "approvalRequired": False,
                "approvalMode": "NoApproval",
                "stages": [],
                "note": "Policy has no Approval_EndUser_Assignment rule — activations bypass approval.",
            }
        setting = approval_rule.get("setting") or {}
        stages_raw = setting.get("approvalStages") or []
        stages = [
            {
                "approverType": s.get("approvalStageTimeOutInDays") and "TimeBound" or "Standard",
                "primaryApprovers": s.get("primaryApprovers") or [],
                "isApproverJustificationRequired": s.get("isApproverJustificationRequired"),
                "escalationApprovers": s.get("escalationApprovers") or [],
                "approvalStageTimeOutInDays": s.get("approvalStageTimeOutInDays"),
            }
            for s in stages_raw
        ]
        return {
            "requestId": request_id,
            "scope": scope_norm,
            "roleDefinitionId": role_def_id,
            "policyAssignmentName": pa_name,
            "approvalRequired": bool(setting.get("isApprovalRequired")),
            "approvalMode": setting.get("approvalMode"),
            "stages": stages,
        }

    @mcp.tool()
    async def arm_get_role_definition(scope: str, role_definition_id: str) -> dict[str, Any]:
        """Resolve an Azure RBAC role definition by GUID at a given scope.

        ARM-scoped twin of ``get_role_definition``. Use when the
        ``roleDefinitionId`` belongs to Azure RBAC (Reader =
        ``acdd72a7-3385-48ef-bd42-f606fba81ae7``, Contributor =
        ``b24988ac-...``, etc.) rather than to a directory role.

        Returns the role's display name, description, type (BuiltInRole vs
        CustomRole), and assignable scopes — enough for the agent to cite
        the role by name in audit comments and to evaluate role-allowlist
        rules (R005) without depending on the trigger payload.

        Read-only. Requires the MI to hold ``Reader`` (or stronger) on
        ``scope``.

        Args:
            scope: ARM scope path. The role-definitions endpoint is
                scope-bound, so pass the scope of the request being audited.
            role_definition_id: GUID of the Azure RBAC role definition.

        Returns:
            JSON envelope with id, roleName, description, type, scope,
            and the raw ARM body.
        """
        if not role_definition_id or not isinstance(role_definition_id, str):
            raise ValueError("role_definition_id must be a non-empty string (GUID)")
        scope_norm = _normalize_arm_scope(scope)
        path = (
            f"{scope_norm}/providers/Microsoft.Authorization"
            f"/roleDefinitions/{role_definition_id}"
        )
        log.info("arm_get_role_definition scope=%s role_definition_id=%s", scope_norm, role_definition_id)
        raw = await _arm_get(path, api_version=ARM_AUTHZ_API_VERSION)
        props = raw.get("properties", {}) or {}
        return {
            "id": raw.get("id"),
            "name": raw.get("name"),
            "roleName": props.get("roleName"),
            "description": props.get("description"),
            "type": props.get("type"),  # BuiltInRole | CustomRole
            "scope": scope_norm,
            "assignableScopes": props.get("assignableScopes"),
            "raw": raw,
        }

