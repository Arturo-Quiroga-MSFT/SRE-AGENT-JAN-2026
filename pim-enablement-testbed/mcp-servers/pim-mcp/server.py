"""PIM MCP Server — gap-filler for the one Graph endpoint Enterprise MCP can't reach.

Single tool: ``list_pending_pim_requests``.

Why this exists
---------------
The Microsoft MCP Server for Enterprise (preview, May 2026) does ~90% of the
PIM reads we need, but the ``/roleManagement/directory/roleAssignmentScheduleRequests``
endpoint requires the ``RoleAssignmentSchedule.ReadWrite.Directory`` *delegated*
Graph permission (Microsoft Graph chose not to publish a delegated read-only
variant for the *Requests* collection). Enterprise MCP currently only exposes
``MCP.*.Read.*`` scopes, so that endpoint is structurally unreachable.

For *application* permissions, ``RoleAssignmentSchedule.Read.Directory`` IS
sufficient for the same endpoint. We therefore use a Managed Identity (app-only
auth) here. This server exposes **no write tools** — banking-compliance design
constraint.

Auth: ``DefaultAzureCredential`` picks up the User-Assigned Managed Identity in
Container Apps via the ``AZURE_CLIENT_ID`` env var.

Run locally::

    uv sync
    AZURE_CLIENT_ID=<mi-client-id> uv run python server.py

Run in container::

    docker build -t pim-mcp .
    docker run -p 8000:8000 -e AZURE_CLIENT_ID=<mi-client-id> pim-mcp

Retire when: Microsoft publishes ``MCP.RoleAssignmentSchedule.ReadWrite.Directory``
(or equivalent write scope) on the Enterprise MCP server. Track at
https://github.com/microsoft/EnterpriseMCP/issues.
"""

from __future__ import annotations

import logging
import os

from fastmcp import FastMCP

from tools import register_tools

LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
logging.basicConfig(level=LOG_LEVEL, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("pim-mcp")

mcp = FastMCP(
    name="pim-mcp",
    instructions=(
        "Read-only PIM + supporting Graph reader (Managed Identity auth). "
        "Workflow: (1) call list_pending_pim_requests to find requests awaiting "
        "approval; (2) call get_user / get_role_definition to resolve principalId "
        "and roleDefinitionId into human-readable identities; (3) call "
        "get_request_status(request_id) to check the final disposition of a "
        "specific request that is no longer pending (approved/denied/cancelled/"
        "expired); (4) call get_request_approver(request_id) for the audit trail "
        "— who approved/denied, when, with what justification; (5) call "
        "list_active_role_assignments(principal_id) to verify a user's currently-"
        "active role assignments post-approval; (6) call "
        "list_eligible_role_assignments(principal_id?) to see who is *eligible* "
        "to activate which role (PIM eligibilities, not yet active). "
        "These tools exist because the SRE Agent connector wizard does not yet "
        "support delegated-OAuth MCP servers like Microsoft's Enterprise MCP, "
        "so we proxy a minimal Graph read surface here via app-only auth. "
        "NEVER attempt to approve, deny, or write — no write tool exists."
    ),
)

register_tools(mcp)


if __name__ == "__main__":
    log.info("PIM MCP server starting on 0.0.0.0:8000 (streamable-http at /mcp)")
    # path="/mcp" (no trailing slash) avoids Starlette's Mount slash-redirect that
    # downgrades to http:// behind ACA's HTTPS ingress and breaks Foundry connector.
    mcp.run(
        transport="streamable-http",
        host="0.0.0.0",
        port=8000,
        path="/mcp",
    )
