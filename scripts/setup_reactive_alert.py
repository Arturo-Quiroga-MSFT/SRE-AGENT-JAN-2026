#!/usr/bin/env python3
"""Set up the Azure Monitor → SRE Agent reactive alert pipeline.

Creates:
  1. HTTP Trigger on the SRE Agent (for 5xx alerts)
  2. Consumption Logic App with system-assigned Managed Identity
  3. SRE Agent Admin role assignment for the Logic App
  4. Azure Monitor metric alert rule with action group

Usage:
    python setup_reactive_alert.py              # full setup
    python setup_reactive_alert.py --dry-run    # show what would be created
    python setup_reactive_alert.py --step 1     # run only step 1

Requires:
    - Azure CLI (az) logged in with Owner / Contributor + RBAC Admin
    - SRE Agent already deployed
    - .env.deployment in repo root
"""

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

# ── Configuration ─────────────────────────────────────────────────────

SRE_AUDIENCE = "https://azuresre.dev"

# Loaded from .env.deployment or overridden via env vars
CONFIG = {
    "RG": "rg-aqsre",
    "LOCATION": "eastus2",
    "SUBSCRIPTION_ID": "7a28b21e-0d3e-4435-a686-d92889d4ee96",
    "SRE_AGENT_NAME": "aq-main",
    "SRE_AGENT_ENDPOINT": "https://aq-main--2cdce1d3.daa74423.eastus2.azuresre.ai",
    "CONTAINER_APP_NAME": "ca-api-ps64h2ydsavgc",
    "LOGIC_APP_NAME": "la-sre-5xx-bridge",
    "ACTION_GROUP_NAME": "ag-sre-5xx",
    "ALERT_RULE_NAME": "alert-api-5xx",
}


def load_env():
    """Load variables from .env.deployment."""
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

    # Override CONFIG from env where available
    for key in CONFIG:
        if key in os.environ:
            CONFIG[key] = os.environ[key]


def az(*cmd, capture=True, check=True):
    """Run an az CLI command; return parsed JSON or raw output."""
    full = ["az", *cmd]
    if capture:
        result = subprocess.run(full, capture_output=True, text=True, check=check)
        stdout = result.stdout.strip()
        if not stdout:
            return None
        try:
            return json.loads(stdout)
        except json.JSONDecodeError:
            return stdout
    else:
        subprocess.run(full, check=check)
        return None


def get_token(audience: str) -> str:
    """Get Azure AD token."""
    return subprocess.check_output(
        ["az", "account", "get-access-token",
         "--resource", audience, "--query", "accessToken", "-o", "tsv"],
        text=True, stderr=subprocess.DEVNULL,
    ).strip()


def sre_api(path, *, method="GET", body=None):
    """Call the SRE Agent data-plane API."""
    url = f"{CONFIG['SRE_AGENT_ENDPOINT'].rstrip('/')}{path}"
    token = get_token(SRE_AUDIENCE)
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read().decode()
        return json.loads(raw) if raw.strip() else None


# ── Step 1: Create HTTP Trigger ───────────────────────────────────────

TRIGGER_PROMPT = """An Azure Monitor metric alert has fired for HTTP 5xx errors on the grocery-sre-demo API.

Alert details:
- Alert rule: {payload.data.essentials.alertRule}
- Severity: {payload.data.essentials.severity}
- Fired at: {payload.data.essentials.firedDateTime}
- Affected resource: {payload.data.essentials.alertTargetIDs}
- Description: {payload.data.essentials.description}

Investigate this incident by:
1. Query Loki logs for the grocery-api container for errors in the last 15 minutes
2. Check for CIRCUIT_OPEN, SUPPLIER_RATE_LIMIT_429, or HTTP_HANDLER_ERROR events
3. Review the circuit breaker state via the /api/supplier/status endpoint
4. Identify the root cause (rate limit cascade, circuit breaker trip, or other)
5. Check if the circuit breaker is OPEN and when it will auto-reset
6. Recommend immediate remediation steps

Focus on: what triggered the 5xx errors, how many requests were affected, and whether the circuit breaker is open."""


def step1_create_trigger(dry_run=False):
    """Create the HTTP trigger on the SRE Agent."""
    print("\n═══ Step 1: Create HTTP Trigger on SRE Agent ═══")

    existing = sre_api("/api/v1/httptriggers")
    for t in (existing or []):
        if t.get("name") == "azure-monitor-5xx-alert":
            trigger_url = f"{CONFIG['SRE_AGENT_ENDPOINT']}/api/v1/httptriggers/trigger/{t['id']}"
            print(f"  Trigger already exists: {t['id']}")
            print(f"  URL: {trigger_url}")
            return t["id"], trigger_url

    if dry_run:
        print("  [DRY RUN] Would create trigger: azure-monitor-5xx-alert")
        return "dry-run-id", "dry-run-url"

    result = sre_api("/api/v1/httptriggers", method="POST", body={
        "name": "azure-monitor-5xx-alert",
        "enabled": True,
        "agentMode": "review",
        "threadMode": "newThread",
        "prompt": TRIGGER_PROMPT,
    })

    trigger_id = result["id"]
    trigger_url = f"{CONFIG['SRE_AGENT_ENDPOINT']}/api/v1/httptriggers/trigger/{trigger_id}"
    print(f"  Created trigger: {trigger_id}")
    print(f"  URL: {trigger_url}")
    return trigger_id, trigger_url


# ── Step 2: Create Logic App ─────────────────────────────────────────

def step2_create_logic_app(trigger_url: str, dry_run=False):
    """Create a Consumption Logic App that bridges Azure Monitor → SRE Agent."""
    print("\n═══ Step 2: Create Logic App (Azure Monitor → SRE Agent bridge) ═══")

    la_name = CONFIG["LOGIC_APP_NAME"]
    rg = CONFIG["RG"]
    location = CONFIG["LOCATION"]

    # Check if it already exists
    existing = az("resource", "list", "-g", rg,
                  "--query", f"[?name=='{la_name}' && type=='Microsoft.Logic/workflows']",
                  "-o", "json", check=False)
    if existing:
        print(f"  Logic App '{la_name}' already exists.")
        la_id = existing[0]["id"]
        identity = az("resource", "show", "--ids", la_id,
                      "--query", "identity.principalId", "-o", "tsv")
        return la_id, identity

    if dry_run:
        print(f"  [DRY RUN] Would create Logic App: {la_name}")
        return "dry-run-la-id", "dry-run-principal-id"

    # Logic App workflow definition — HTTP trigger receives Azure Monitor
    # common alert schema, forwards to SRE Agent HTTP Trigger with MI auth.
    workflow = {
        "definition": {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "triggers": {
                "When_alert_fires": {
                    "type": "Request",
                    "kind": "Http",
                    "inputs": {
                        "schema": {
                            "type": "object",
                            "properties": {
                                "schemaId": {"type": "string"},
                                "data": {"type": "object"},
                            },
                        },
                    },
                },
            },
            "actions": {
                "Forward_to_SRE_Agent": {
                    "type": "Http",
                    "runAfter": {},
                    "inputs": {
                        "method": "POST",
                        "uri": trigger_url,
                        "headers": {"Content-Type": "application/json"},
                        "body": "@triggerBody()",
                        "authentication": {
                            "type": "ManagedServiceIdentity",
                            "audience": SRE_AUDIENCE,
                        },
                    },
                },
            },
        },
    }

    # Write temp file for deployment
    tmp_file = Path(__file__).parent / ".tmp_logic_app_def.json"
    tmp_file.write_text(json.dumps(workflow, indent=2))

    try:
        az("logic", "workflow", "create",
           "-g", rg, "-n", la_name, "--location", location,
           "--definition", str(tmp_file),
           "--mi-system-assigned",
           "-o", "none")
    finally:
        tmp_file.unlink(missing_ok=True)

    print(f"  Created Logic App: {la_name}")

    # Get principal ID
    la_resource = az("resource", "show", "-g", rg,
                     "--resource-type", "Microsoft.Logic/workflows",
                     "-n", la_name, "-o", "json")
    la_id = la_resource["id"]
    principal_id = la_resource.get("identity", {}).get("principalId")
    print(f"  Resource ID: {la_id}")
    print(f"  Managed Identity principal: {principal_id}")

    # Get the callback URL for the HTTP trigger
    callback = az("logic", "workflow", "show", "-g", rg, "-n", la_name,
                  "--query", "accessEndpoint", "-o", "tsv")
    print(f"  Callback URL: {callback}")

    return la_id, principal_id


# ── Step 3: Assign SRE Agent Admin Role ───────────────────────────────

def step3_assign_role(principal_id: str, dry_run=False):
    """Assign SRE Agent Admin role to the Logic App's Managed Identity."""
    print("\n═══ Step 3: Assign SRE Agent Admin role to Logic App MI ═══")

    rg = CONFIG["RG"]
    sub = CONFIG["SUBSCRIPTION_ID"]
    sre_name = CONFIG["SRE_AGENT_NAME"]
    scope = (
        f"/subscriptions/{sub}/resourceGroups/{rg}"
        f"/providers/Microsoft.App/agents/{sre_name}"
    )

    if dry_run:
        print(f"  [DRY RUN] Would assign SRE Agent Admin to {principal_id}")
        print(f"  Scope: {scope}")
        return

    # List existing role assignments to avoid duplicates
    existing = az("role", "assignment", "list",
                  "--assignee", principal_id,
                  "--scope", scope,
                  "-o", "json", check=False)
    if existing:
        for r in existing:
            if "SRE Agent Admin" in r.get("roleDefinitionName", ""):
                print("  Role already assigned.")
                return

    # Find the SRE Agent Admin role definition
    role_defs = az("role", "definition", "list",
                   "--name", "SRE Agent Admin",
                   "--scope", scope, "-o", "json", check=False)

    if not role_defs:
        # Fall back: try the Azure SRE Agent Data Plane Admin
        role_defs = az("role", "definition", "list",
                       "--query", "[?contains(roleName, 'SRE Agent')]",
                       "--scope", scope, "-o", "json", check=False)

    if role_defs:
        role_name = role_defs[0]["roleName"]
        print(f"  Found role: {role_name}")
    else:
        role_name = "SRE Agent Admin"
        print(f"  Using role name: {role_name} (attempting assignment)")

    az("role", "assignment", "create",
       "--assignee-object-id", principal_id,
       "--assignee-principal-type", "ServicePrincipal",
       "--role", role_name,
       "--scope", scope,
       "-o", "none")
    print(f"  Assigned '{role_name}' to principal {principal_id}")


# ── Step 4: Create Alert Rule + Action Group ──────────────────────────

def step4_create_alert(dry_run=False):
    """Create the Azure Monitor metric alert and action group."""
    print("\n═══ Step 4: Create Azure Monitor 5xx alert + action group ═══")

    rg = CONFIG["RG"]
    sub = CONFIG["SUBSCRIPTION_ID"]
    ca_name = CONFIG["CONTAINER_APP_NAME"]
    ag_name = CONFIG["ACTION_GROUP_NAME"]
    alert_name = CONFIG["ALERT_RULE_NAME"]
    la_name = CONFIG["LOGIC_APP_NAME"]

    ca_id = (
        f"/subscriptions/{sub}/resourceGroups/{rg}"
        f"/providers/Microsoft.App/containerapps/{ca_name}"
    )

    if dry_run:
        print(f"  [DRY RUN] Would create action group: {ag_name}")
        print(f"  [DRY RUN] Would create alert rule: {alert_name}")
        print(f"    Scope: {ca_name}")
        print(f"    Condition: Requests with statusCodeCategory=5xx > 0 in 5m window")
        print(f"    Action: {ag_name} → Logic App → SRE Agent HTTP Trigger")
        return

    # 4a. Get Logic App callback URL for the webhook
    print("  Fetching Logic App callback URL...")

    callback_url = az(
        "rest", "--method", "POST",
        "--url", f"https://management.azure.com/subscriptions/{sub}"
                 f"/resourceGroups/{rg}/providers/Microsoft.Logic/workflows"
                 f"/{la_name}/triggers/When_alert_fires/listCallbackUrl"
                 f"?api-version=2016-06-01",
        "--query", "value", "-o", "tsv", check=False,
    )

    if not callback_url:
        print("  WARNING: Could not get Logic App callback URL.")
        print("  The action group will need the URL configured manually.")
        callback_url = "https://placeholder-get-from-logic-app"

    print(f"  Logic App callback: {callback_url[:80]}...")

    # 4b. Create action group with webhook pointing to Logic App
    existing_ag = az("monitor", "action-group", "list", "-g", rg,
                     "--query", f"[?name=='{ag_name}']", "-o", "json", check=False)
    if existing_ag:
        print(f"  Action group '{ag_name}' already exists.")
    else:
        az("monitor", "action-group", "create",
           "-g", rg, "-n", ag_name,
           "--short-name", "sre5xx",
           "--action", "webhook", "sre-agent-bridge", callback_url,
           "usecommonalertschema",
           "-o", "none")
        print(f"  Created action group: {ag_name}")

    # 4c. Create metric alert rule: Requests where statusCodeCategory == 5xx > 0
    existing_alert = az("monitor", "metrics", "alert", "list", "-g", rg,
                        "--query", f"[?name=='{alert_name}']", "-o", "json", check=False)
    if existing_alert:
        print(f"  Alert rule '{alert_name}' already exists.")
        return

    ag_id = (
        f"/subscriptions/{sub}/resourceGroups/{rg}"
        f"/providers/Microsoft.Insights/actionGroups/{ag_name}"
    )

    az("monitor", "metrics", "alert", "create",
       "-g", rg, "-n", alert_name,
       "--scopes", ca_id,
       "--condition", "total Requests > 0 where statusCodeCategory includes 5xx",
       "--window-size", "5m",
       "--evaluation-frequency", "1m",
       "--severity", "2",
       "--action", ag_id,
       "--description", "HTTP 5xx errors detected on grocery-api. Triggers SRE Agent investigation.",
       "--auto-mitigate", "true",
       "-o", "none")
    print(f"  Created alert rule: {alert_name}")
    print(f"    Scope: {ca_name}")
    print(f"    Condition: Requests with statusCodeCategory=5xx > 0 in 5m window")
    print(f"    Action: {ag_name} → Logic App → SRE Agent HTTP Trigger")


# ── Orchestrator ──────────────────────────────────────────────────────

def main():
    load_env()

    parser = argparse.ArgumentParser(
        description="Set up Azure Monitor → SRE Agent reactive alert pipeline",
    )
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would be created without making changes")
    parser.add_argument("--step", type=int, choices=[1, 2, 3, 4],
                        help="Run only a specific step (1-4)")
    args = parser.parse_args()

    print("╔══════════════════════════════════════════════════════════════╗")
    print("║  Azure Monitor → SRE Agent Reactive Alert Setup            ║")
    print("╚══════════════════════════════════════════════════════════════╝")
    print(f"\n  Resource Group:   {CONFIG['RG']}")
    print(f"  SRE Agent:        {CONFIG['SRE_AGENT_NAME']}")
    print(f"  Container App:    {CONFIG['CONTAINER_APP_NAME']}")
    print(f"  Logic App:        {CONFIG['LOGIC_APP_NAME']}")
    print(f"  Alert Rule:       {CONFIG['ALERT_RULE_NAME']}")
    if args.dry_run:
        print("\n  *** DRY RUN MODE — no changes will be made ***")

    trigger_id, trigger_url = None, None

    if args.step is None or args.step == 1:
        trigger_id, trigger_url = step1_create_trigger(args.dry_run)

    if args.step is None or args.step == 2:
        if not trigger_url:
            # Need trigger URL from step 1
            existing = sre_api("/api/v1/httptriggers")
            for t in (existing or []):
                if t.get("name") == "azure-monitor-5xx-alert":
                    trigger_url = f"{CONFIG['SRE_AGENT_ENDPOINT']}/api/v1/httptriggers/trigger/{t['id']}"
                    break
            if not trigger_url:
                print("\nERROR: No trigger found. Run step 1 first.", file=sys.stderr)
                sys.exit(1)
        la_id, principal_id = step2_create_logic_app(trigger_url, args.dry_run)
    else:
        principal_id = None

    if args.step is None or args.step == 3:
        if not principal_id:
            # Look it up
            la_resource = az("resource", "list", "-g", CONFIG["RG"],
                             "--query", f"[?name=='{CONFIG['LOGIC_APP_NAME']}']",
                             "-o", "json", check=False)
            if la_resource:
                principal_id = la_resource[0].get("identity", {}).get("principalId")
            if not principal_id:
                print("\nERROR: Logic App not found. Run step 2 first.", file=sys.stderr)
                sys.exit(1)
        step3_assign_role(principal_id, args.dry_run)

    if args.step is None or args.step == 4:
        step4_create_alert(args.dry_run)

    print("\n═══ Setup Complete ═══")
    if not args.dry_run:
        print("\nNext: test the pipeline with:")
        print("  python scripts/test_reactive_flow.py")


if __name__ == "__main__":
    main()
