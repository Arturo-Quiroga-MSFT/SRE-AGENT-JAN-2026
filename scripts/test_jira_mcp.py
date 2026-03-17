#!/usr/bin/env python3
"""Test the local Jira MCP server by calling create_issue."""

import json
import urllib.request

MCP_URL = "http://localhost:9000/mcp"
HEADERS = {
    "Content-Type": "application/json",
    "Accept": "application/json, text/event-stream",
}


def mcp_call(method, params=None, msg_id=1, session_id=None):
    """Send an MCP JSON-RPC call and return parsed response."""
    body = {"jsonrpc": "2.0", "method": method, "id": msg_id}
    if params:
        body["params"] = params

    headers = dict(HEADERS)
    if session_id:
        headers["mcp-session-id"] = session_id

    req = urllib.request.Request(
        MCP_URL,
        data=json.dumps(body).encode(),
        headers=headers,
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        # Get session ID from response headers
        sid = resp.headers.get("mcp-session-id", session_id)
        raw = resp.read().decode()

    # Parse SSE format
    for line in raw.split("\n"):
        if line.startswith("data: "):
            return json.loads(line[6:]), sid
    # Try plain JSON
    return json.loads(raw), sid


def main():
    # Step 1: Initialize
    print("1. Initializing MCP session...")
    result, session_id = mcp_call("initialize", {
        "protocolVersion": "2024-11-05",
        "capabilities": {},
        "clientInfo": {"name": "test", "version": "1.0"},
    })
    print(f"   Session: {session_id}")
    print(f"   Server: {result.get('result', {}).get('serverInfo', {})}")

    # Step 2: List tools
    print("\n2. Listing tools...")
    result, session_id = mcp_call("tools/list", msg_id=2, session_id=session_id)
    tools = [t["name"] for t in result.get("result", {}).get("tools", [])]
    print(f"   Found {len(tools)} tools")
    create_tools = [t for t in tools if "create" in t.lower()]
    print(f"   Create tools: {create_tools}")

    # Step 3: Try calling jira_create_issue
    if "jira_create_issue" in tools:
        print("\n3. Testing jira_create_issue (will create a ticket)...")
        result, session_id = mcp_call("tools/call", {
            "name": "jira_create_issue",
            "arguments": {
                "project_key": "SCRUM",
                "summary": "[TEST] SRE Agent connectivity test - safe to delete",
                "issue_type": "Task",
                "description": "Automated test from local MCP validation script. Safe to delete.",
            },
        }, msg_id=3, session_id=session_id)

        if "error" in result:
            print(f"   ERROR: {result['error']}")
        else:
            print(f"   SUCCESS: {json.dumps(result.get('result', {}), indent=2)[:500]}")
    else:
        print(f"\n3. create_issue not found in tools. Available: {tools[:10]}...")


if __name__ == "__main__":
    main()
