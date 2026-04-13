#!/usr/bin/env python3
"""Client for Azure SRE Agent HTTP Triggers API.

Usage:
    python sre_agent_api.py list
    python sre_agent_api.py create --name <name> --prompt <prompt_text>
    python sre_agent_api.py get <trigger_id>
    python sre_agent_api.py delete <trigger_id>
    python sre_agent_api.py fire <trigger_url> --payload '{"key":"val"}'

Requires:
    - Azure CLI (az) logged in
    - SRE Agent endpoint set in .env.deployment or via --endpoint
"""

import argparse
import json
import os
import subprocess
import sys
import urllib.request
import urllib.error
from pathlib import Path

# SRE Agent data-plane audience
SRE_AUDIENCE = "https://azuresre.dev"


def load_env():
    """Load variables from .env.deployment if it exists."""
    env_file = Path(__file__).resolve().parent.parent / ".env.deployment"
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            line = line.strip()
            if line.startswith("#") or "=" not in line:
                continue
            line = line.removeprefix("export ")
            key, _, val = line.partition("=")
            val = val.strip().strip('"').strip("'")
            os.environ.setdefault(key.strip(), val)


def get_token(audience: str) -> str:
    """Acquire an Azure AD token for the given audience via az CLI."""
    try:
        token = subprocess.check_output(
            [
                "az", "account", "get-access-token",
                "--resource", audience,
                "--query", "accessToken",
                "-o", "tsv",
            ],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except subprocess.CalledProcessError as exc:
        print(f"ERROR: Failed to get token for audience {audience}.", file=sys.stderr)
        print("       Make sure you are logged in: az login", file=sys.stderr)
        sys.exit(1)
    return token


def api_call(endpoint: str, path: str, *, method: str = "GET",
             body: dict | None = None, audience: str = SRE_AUDIENCE) -> dict | list | None:
    """Make an authenticated HTTP call to the SRE Agent API."""
    url = f"{endpoint.rstrip('/')}{path}"
    token = get_token(audience)
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    data = json.dumps(body).encode("utf-8") if body else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8")
            if not raw.strip():
                return None
            return json.loads(raw)
    except urllib.error.HTTPError as exc:
        error_body = exc.read().decode("utf-8", errors="replace")
        print(f"ERROR: HTTP {exc.code} {exc.reason}", file=sys.stderr)
        print(f"  URL: {url}", file=sys.stderr)
        print(f"  Body: {error_body[:500]}", file=sys.stderr)
        sys.exit(1)


# ── Commands ──────────────────────────────────────────────────────────


def cmd_list(args):
    """List all HTTP triggers."""
    triggers = api_call(args.endpoint, "/api/v1/httptriggers")
    if not triggers:
        print("No HTTP triggers found.")
        return
    for t in triggers:
        status = "enabled" if t.get("enabled") else "disabled"
        print(f"  {t['id']}  {t['name']}  [{status}]")
        print(f"    URL: {args.endpoint}/api/v1/httptriggers/trigger/{t['id']}")


def cmd_create(args):
    """Create a new HTTP trigger."""
    payload = {
        "name": args.name,
        "enabled": True,
        "agentMode": args.mode,
        "threadMode": args.thread_mode,
        "prompt": args.prompt,
    }
    if args.subagent:
        payload["subAgent"] = args.subagent

    result = api_call(args.endpoint, "/api/v1/httptriggers", method="POST", body=payload)
    trigger_id = result.get("id", "unknown")
    trigger_url = f"{args.endpoint}/api/v1/httptriggers/trigger/{trigger_id}"
    print(f"Created trigger: {result.get('name')}")
    print(f"  ID:  {trigger_id}")
    print(f"  URL: {trigger_url}")
    print(json.dumps(result, indent=2))


def cmd_get(args):
    """Get details of a specific trigger."""
    result = api_call(args.endpoint, f"/api/v1/httptriggers/{args.trigger_id}")
    print(json.dumps(result, indent=2))


def cmd_delete(args):
    """Delete a trigger."""
    api_call(args.endpoint, f"/api/v1/httptriggers/{args.trigger_id}", method="DELETE")
    print(f"Deleted trigger {args.trigger_id}")


def cmd_fire(args):
    """Fire a trigger URL with a JSON payload (for testing)."""
    payload = json.loads(args.payload) if args.payload else {}
    url = args.trigger_url
    token = get_token(SRE_AUDIENCE)
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")

    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode("utf-8")
            print(f"HTTP {resp.status}")
            if raw.strip():
                try:
                    print(json.dumps(json.loads(raw), indent=2))
                except json.JSONDecodeError:
                    print(raw[:500])
    except urllib.error.HTTPError as exc:
        error_body = exc.read().decode("utf-8", errors="replace")
        print(f"HTTP {exc.code} {exc.reason}")
        print(error_body[:500])


# ── CLI ───────────────────────────────────────────────────────────────


def main():
    load_env()

    default_endpoint = os.environ.get(
        "SRE_AGENT_ENDPOINT",
        "https://aq-main--2cdce1d3.daa74423.eastus2.azuresre.ai",
    )

    parser = argparse.ArgumentParser(
        description="Azure SRE Agent HTTP Triggers CLI",
    )
    parser.add_argument(
        "--endpoint", default=default_endpoint,
        help=f"SRE Agent endpoint (default: {default_endpoint})",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # list
    sub.add_parser("list", help="List all HTTP triggers")

    # create
    p_create = sub.add_parser("create", help="Create an HTTP trigger")
    p_create.add_argument("--name", required=True, help="Trigger name")
    p_create.add_argument("--prompt", required=True, help="Agent prompt (use {payload.X} placeholders)")
    p_create.add_argument("--mode", default="review", choices=["review", "autonomous"],
                          help="Agent mode (default: review)")
    p_create.add_argument("--thread-mode", default="newThread", choices=["newThread", "sameThread"],
                          help="Thread mode (default: newThread)")
    p_create.add_argument("--subagent", default=None, help="Optional sub-agent name")

    # get
    p_get = sub.add_parser("get", help="Get trigger details")
    p_get.add_argument("trigger_id", help="Trigger ID")

    # delete
    p_del = sub.add_parser("delete", help="Delete a trigger")
    p_del.add_argument("trigger_id", help="Trigger ID")

    # fire
    p_fire = sub.add_parser("fire", help="Fire a trigger URL with test payload")
    p_fire.add_argument("trigger_url", help="Full trigger URL")
    p_fire.add_argument("--payload", default="{}", help="JSON payload string")

    args = parser.parse_args()

    cmd_map = {
        "list": cmd_list,
        "create": cmd_create,
        "get": cmd_get,
        "delete": cmd_delete,
        "fire": cmd_fire,
    }
    cmd_map[args.command](args)


if __name__ == "__main__":
    main()
