"""One-off smoke test for the two tools added in pim-mcp 0.5.0:

- get_request_status(request_id)
- list_active_role_assignments(principal_id)

Usage:
    python scripts/smoke-test-new-tools.py <endpoint> <request_id> <principal_id>
"""
import asyncio
import sys

from fastmcp import Client
from fastmcp.client.transports import StreamableHttpTransport


async def main(endpoint: str, request_id: str, principal_id: str) -> None:
    mcp_url = endpoint.rstrip("/") + "/mcp"
    print(f"==> Connecting to {mcp_url}")

    async with Client(StreamableHttpTransport(mcp_url)) as client:
        tools = await client.list_tools()
        names = sorted(t.name for t in tools)
        print(f"==> Tools registered: {names}")

        print(f"\n==> get_request_status(request_id={request_id})")
        r1 = await client.call_tool("get_request_status", {"request_id": request_id})
        print(f"    error={r1.is_error}")
        print(f"    {r1.content[0].text[:1500] if r1.content else r1}")

        print(f"\n==> list_active_role_assignments(principal_id={principal_id}, top=10)")
        r2 = await client.call_tool(
            "list_active_role_assignments",
            {"principal_id": principal_id, "top": 10},
        )
        print(f"    error={r2.is_error}")
        print(f"    {r2.content[0].text[:1500] if r2.content else r2}")


if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: smoke-test-new-tools.py <endpoint> <request_id> <principal_id>")
        sys.exit(2)
    asyncio.run(main(sys.argv[1], sys.argv[2], sys.argv[3]))
