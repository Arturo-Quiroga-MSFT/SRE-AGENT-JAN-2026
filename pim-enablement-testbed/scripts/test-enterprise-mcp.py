#!/usr/bin/env python
"""Quick smoke test of the Microsoft MCP Server for Enterprise (PIM scenario).

Prerequisites (one-time per tenant — see docs/enterprise-mcp-setup.md):
  1. POST /servicePrincipals to provision the MCP Server SP in your tenant.
  2. Register a custom MCP Client app (record its Application/Client ID).
  3. Grant-EntraBetaMCPServerPermission with at least:
       MCP.RoleManagement.Read.All
       MCP.RoleAssignmentSchedule.Read.All
       MCP.RoleEligibilitySchedule.Read.All
       MCP.User.Read.All
  4. Configure the app for "public client / native" so device-code flow works:
       Authentication blade -> Allow public client flows = Yes.

Setup:
    uv venv .venv && source .venv/bin/activate    # or: python -m venv .venv
    uv pip install "mcp[cli]>=1.2.0" msal azure-identity httpx

Run:
    export MCP_TENANT_ID="<your-tenant-id>"
    export MCP_CLIENT_APP_ID="<the-client-app-id-you-registered>"
    python scripts/test-enterprise-mcp.py

What it does:
    1. Acquires a delegated token for api://<EnterpriseMcpAppId>/.default via
       device-code flow (you sign in once interactively).
    2. Connects to https://mcp.svc.cloud.microsoft/enterprise (streamable HTTP).
    3. Lists the server's tools (expect 3: suggest_queries, get, list_properties).
    4. Calls microsoft_graph_suggest_queries with a PIM intent.
    5. Calls microsoft_graph_get for /roleManagement/directory/roleAssignmentScheduleRequests
       filtered to PendingApproval and prints the result.
"""

from __future__ import annotations

import asyncio
import json
import os
import sys

import msal
from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client

ENTERPRISE_MCP_APPID = "e8c77dc2-69b3-43f4-bc51-3213c9d915b4"
ENTERPRISE_MCP_URL = "https://mcp.svc.cloud.microsoft/enterprise"
SCOPE = f"api://{ENTERPRISE_MCP_APPID}/.default"


def acquire_token(tenant_id: str, client_id: str) -> str:
    """Device-code flow against the registered MCP Client app."""
    authority = f"https://login.microsoftonline.com/{tenant_id}"
    app = msal.PublicClientApplication(client_id=client_id, authority=authority)

    # Try silent first (cached account)
    accounts = app.get_accounts()
    if accounts:
        result = app.acquire_token_silent([SCOPE], account=accounts[0])
        if result and "access_token" in result:
            return result["access_token"]

    flow = app.initiate_device_flow(scopes=[SCOPE])
    if "user_code" not in flow:
        raise RuntimeError(f"Failed to start device flow: {json.dumps(flow, indent=2)}")
    print("\n" + flow["message"] + "\n", flush=True)
    result = app.acquire_token_by_device_flow(flow)
    if "access_token" not in result:
        raise RuntimeError(f"Auth failed: {result.get('error_description', result)}")
    return result["access_token"]


async def run(token: str) -> None:
    headers = {"Authorization": f"Bearer {token}"}

    print(f"==> Connecting to {ENTERPRISE_MCP_URL}")
    async with streamablehttp_client(ENTERPRISE_MCP_URL, headers=headers) as (
        read_stream,
        write_stream,
        _,
    ):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()

            # 1. List tools
            print("\n==> Tools exposed by the server:")
            tools = await session.list_tools()
            for t in tools.tools:
                print(f"  - {t.name}: {t.description[:90] if t.description else ''}")

            # 2. Ask the server to suggest the right Graph query
            print("\n==> microsoft_graph_suggest_queries(intent='list pending PIM activation requests')")
            suggest = await session.call_tool(
                "microsoft_graph_suggest_queries",
                {"intent": "list pending PIM activation requests"},
            )
            print(_pretty(suggest))

            # 3. Execute the PIM read directly
            print("\n==> microsoft_graph_get(/roleManagement/directory/roleAssignmentScheduleRequests?$filter=status eq 'PendingApproval')")
            result = await session.call_tool(
                "microsoft_graph_get",
                {
                    "url": "/roleManagement/directory/roleAssignmentScheduleRequests",
                    "queryParameters": {"$filter": "status eq 'PendingApproval'", "$top": "10"},
                },
            )
            print(_pretty(result))

            # 4. Bonus: schema lookup for the PIM request entity
            print("\n==> microsoft_graph_list_properties(unifiedRoleAssignmentScheduleRequest)")
            schema = await session.call_tool(
                "microsoft_graph_list_properties",
                {"entity": "unifiedRoleAssignmentScheduleRequest"},
            )
            print(_pretty(schema))


def _pretty(call_result) -> str:
    """Render an MCP CallToolResult compactly."""
    out = []
    for c in call_result.content:
        if hasattr(c, "text"):
            text = c.text
            try:
                text = json.dumps(json.loads(text), indent=2)[:2000]
            except Exception:
                text = text[:2000]
            out.append(text)
        else:
            out.append(str(c)[:2000])
    return "\n".join(out) if out else "(no content)"


def main() -> int:
    tenant_id = os.environ.get("MCP_TENANT_ID")
    client_id = os.environ.get("MCP_CLIENT_APP_ID")
    if not tenant_id or not client_id:
        print("ERROR: set MCP_TENANT_ID and MCP_CLIENT_APP_ID env vars first.", file=sys.stderr)
        print("       MCP_CLIENT_APP_ID is the App Id of the custom MCP Client app you", file=sys.stderr)
        print("       registered per docs/enterprise-mcp-setup.md (Step 2).", file=sys.stderr)
        return 2

    token = acquire_token(tenant_id, client_id)
    asyncio.run(run(token))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
