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
        "Read-only access to PIM activation requests in PendingApproval state. "
        "This server exists ONLY to fill the gap left by Microsoft's Enterprise "
        "MCP server, which cannot reach the roleAssignmentScheduleRequests "
        "Graph endpoint in current preview. Use this for the trigger; use the "
        "Microsoft Enterprise MCP server (microsoft_graph_get) for everything "
        "else. NEVER attempt to approve or deny — no write tool exists."
    ),
)

register_tools(mcp)


if __name__ == "__main__":
    log.info("PIM MCP server starting on 0.0.0.0:8000 (SSE)")
    mcp.run(transport="sse", host="0.0.0.0", port=8000)
