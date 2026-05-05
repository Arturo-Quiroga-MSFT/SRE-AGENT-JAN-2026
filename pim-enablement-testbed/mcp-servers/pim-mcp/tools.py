"""PIM MCP tool implementations — single tool, read-only by construction.

Exposes one tool only: ``list_pending_pim_requests``.

The endpoint hit (``/v1.0/roleManagement/directory/roleAssignmentScheduleRequests``)
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
        }

    @mcp.tool()
    async def health() -> dict[str, str]:
        """Liveness probe."""
        return {"status": "ok"}
