"""PIM MCP tool implementations — read-only by construction.

Exposes six tools, all GET-only against Microsoft Graph v1.0:

- ``list_pending_pim_requests`` — the trigger surface (PendingApproval only)
- ``get_request_status`` — final disposition of a specific request by ID
- ``list_active_role_assignments`` — currently-active assignments for a principal
- ``get_user`` — resolve principalId to displayName/UPN/etc.
- ``get_role_definition`` — resolve roleDefinitionId to displayName/etc.
- ``health`` — liveness probe

The primary endpoint (``/v1.0/roleManagement/directory/roleAssignmentScheduleRequests``)
requires either:
- delegated ``RoleAssignmentSchedule.ReadWrite.Directory`` (not available
  through Microsoft's Enterprise MCP preview), or
- application ``RoleAssignmentSchedule.Read.Directory`` (this server uses this
  via Managed Identity).

See https://learn.microsoft.com/en-us/graph/api/rbacapplication-list-roleassignmentschedulerequests
"""

from __future__ import annotations

import logging
import os
from typing import Any

import httpx
from azure.identity import DefaultAzureCredential
from fastmcp import FastMCP

log = logging.getLogger("pim-mcp.tools")

GRAPH_BASE_URL = os.getenv("GRAPH_BASE_URL", "https://graph.microsoft.com/v1.0")
GRAPH_SCOPE = "https://graph.microsoft.com/.default"
PIM_REQUESTS_PATH = "/roleManagement/directory/roleAssignmentScheduleRequests"
PIM_INSTANCES_PATH = "/roleManagement/directory/roleAssignmentScheduleInstances"
USERS_PATH = "/users"
ROLE_DEFINITIONS_PATH = "/roleManagement/directory/roleDefinitions"

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


def _get_credential() -> DefaultAzureCredential:
    global _credential
    if _credential is None:
        _credential = DefaultAzureCredential()
    return _credential


async def _graph_get(path: str, params: dict[str, str] | None = None) -> dict[str, Any]:
    """Authenticated GET against Microsoft Graph (app-only via MI)."""
    token = _get_credential().get_token(GRAPH_SCOPE).token
    url = f"{GRAPH_BASE_URL}{path}"
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


def register_tools(mcp: FastMCP) -> None:
    """Register the single PIM read tool with the MCP server."""

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
        return {
            "value": pending,
            "@odata.context": raw.get("@odata.context"),
            "fetchedCount": len(all_items),
            "pendingCount": len(pending),
            "hint": (
                "This tool only returns PendingApproval requests. To check the "
                "final disposition of a request that is no longer pending, call "
                "get_request_status(request_id). To see currently-active role "
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
        return await _graph_get(
            f"{PIM_REQUESTS_PATH}/{request_id}",
            params={"$select": REQUEST_STATUS_SELECT},
        )

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
        return {
            "value": items,
            "@odata.context": raw.get("@odata.context"),
            "count": len(items),
        }
