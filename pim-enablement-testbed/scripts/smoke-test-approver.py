"""One-off smoke test for the get_request_approver tool added in pim-mcp 0.6.0.

Usage:
    python scripts/smoke-test-approver.py <endpoint> <request_id>
"""
import asyncio
import sys

from fastmcp import Client
from fastmcp.client.transports import StreamableHttpTransport


async def main(endpoint: str, request_id: str) -> None:
    mcp_url = endpoint.rstrip("/") + "/mcp"
    print(f"==> Connecting to {mcp_url}")

    async with Client(StreamableHttpTransport(mcp_url)) as client:
        tools = await client.list_tools()
        names = sorted(t.name for t in tools)
        print(f"==> Tools registered ({len(names)}): {names}")

        print(f"\n==> get_request_approver(request_id={request_id})")
        r = await client.call_tool("get_request_approver", {"request_id": request_id})
        print(f"    error={r.is_error}")
        print(f"    {r.content[0].text[:2500] if r.content else r}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: smoke-test-approver.py <endpoint> <request_id>")
        sys.exit(2)
    asyncio.run(main(sys.argv[1], sys.argv[2]))
