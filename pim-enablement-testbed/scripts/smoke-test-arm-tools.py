"""Smoke test for the three ARM tools added in pim-mcp 0.10.0 (Wave C):

- arm_get_role_definition(scope, role_definition_id)
- arm_get_request_status(scope, request_id)
- arm_get_request_approver(scope, request_id)

Usage:
    python scripts/smoke-test-arm-tools.py <endpoint> <scope> [request_id]

If <request_id> is omitted, only the role-definition probe runs (which works
without any prior PIM request — it queries the well-known Reader role).
"""
import asyncio
import sys

from fastmcp import Client
from fastmcp.client.transports import StreamableHttpTransport

# Reader role — universal, present in every Azure subscription.
READER_ROLE_ID = "acdd72a7-3385-48ef-bd42-f606fba81ae7"


async def main(endpoint: str, scope: str, request_id: str | None) -> None:
    mcp_url = endpoint.rstrip("/") + "/mcp"
    print(f"==> Connecting to {mcp_url}")
    print(f"==> Scope: {scope}")

    async with Client(StreamableHttpTransport(mcp_url)) as client:
        # 1. Confirm the new tools are registered.
        tools = await client.list_tools()
        names = sorted(t.name for t in tools)
        print(f"\n==> Tools registered ({len(names)}): {names}")
        for required in ("arm_get_role_definition", "arm_get_request_status", "arm_get_request_approver"):
            mark = "✓" if required in names else "✗ MISSING"
            print(f"    {mark} {required}")

        # 2. Probe arm_get_role_definition with the Reader role.
        print(f"\n==> arm_get_role_definition(scope=<scope>, role_definition_id={READER_ROLE_ID})  # Reader")
        r = await client.call_tool(
            "arm_get_role_definition",
            {"scope": scope, "role_definition_id": READER_ROLE_ID},
        )
        print(f"    error={r.is_error}")
        body = r.content[0].text if r.content else str(r)
        print(f"    {body[:600]}")

        if not request_id:
            print("\n(no request_id provided — skipping arm_get_request_status / arm_get_request_approver)")
            return

        # 3. arm_get_request_status — should return durationHours int.
        print(f"\n==> arm_get_request_status(scope=<scope>, request_id={request_id})")
        r = await client.call_tool(
            "arm_get_request_status",
            {"scope": scope, "request_id": request_id},
        )
        print(f"    error={r.is_error}")
        body = r.content[0].text if r.content else str(r)
        print(f"    {body[:1200]}")

        # 4. arm_get_request_approver — 3-step policyAssignment lookup.
        print(f"\n==> arm_get_request_approver(scope=<scope>, request_id={request_id})")
        r = await client.call_tool(
            "arm_get_request_approver",
            {"scope": scope, "request_id": request_id},
        )
        print(f"    error={r.is_error}")
        body = r.content[0].text if r.content else str(r)
        print(f"    {body[:1500]}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: smoke-test-arm-tools.py <endpoint> <scope> [request_id]")
        sys.exit(2)
    endpoint = sys.argv[1]
    scope = sys.argv[2]
    rid = sys.argv[3] if len(sys.argv) > 3 else None
    asyncio.run(main(endpoint, scope, rid))
