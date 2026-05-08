"""Smoke-test the live pim-mcp Container App end-to-end.

Connects to the streamable-http endpoint, lists tools, calls
list_pending_pim_requests, and prints the response. Fully validates:
ingress -> MCP -> MI -> Graph.

Usage:
    python scripts/smoke-test-pim-mcp.py <pim-mcp-endpoint>
"""
import asyncio
import sys

from fastmcp import Client
from fastmcp.client.transports import StreamableHttpTransport


async def main(endpoint: str) -> None:
    mcp_url = endpoint.rstrip("/") + "/mcp"
    print(f"==> Connecting to {mcp_url} (streamable-http)")

    async with Client(StreamableHttpTransport(mcp_url)) as client:
        print("==> Listing tools")
        tools = await client.list_tools()
        for tool in tools:
            print(f"    - {tool.name}: {tool.description.splitlines()[0] if tool.description else ''}")

        print("\n==> Calling health()")
        health = await client.call_tool("health", {})
        print(f"    {health.content[0].text if health.content else health}")

        print("\n==> Calling list_pending_pim_requests(top=5)")
        result = await client.call_tool("list_pending_pim_requests", {"top": 5})
        if result.is_error:
            print(f"    ERROR: {result.content[0].text if result.content else result}")
            sys.exit(1)
        text = result.content[0].text if result.content else "(no content)"
        print(f"    {text[:1000]}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: smoke-test-pim-mcp.py <endpoint>")
        sys.exit(2)
    asyncio.run(main(sys.argv[1]))
