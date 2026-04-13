#!/usr/bin/env python3
"""Test the Azure Monitor → SRE Agent reactive alert pipeline end-to-end.

Workflow:
  1. Check current circuit breaker & alert rule status
  2. Trigger 5xx errors on the grocery API (trips the circuit breaker)
  3. Verify CB is OPEN
  4. Optionally fire the HTTP trigger manually (skips the alert/Logic App wait)
  5. Reset the circuit breaker

Usage:
    python test_reactive_flow.py                # full test
    python test_reactive_flow.py --manual-fire  # also fire trigger directly
    python test_reactive_flow.py --reset-only   # just reset CB + rate limit

Requires:
    - Azure CLI (az) logged in
    - .env.deployment in repo root
    - setup_reactive_alert.py already run
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

SRE_AUDIENCE = "https://azuresre.dev"

# ── Config ────────────────────────────────────────────────────────────

CONFIG = {
    "SRE_AGENT_ENDPOINT": "https://aq-main--2cdce1d3.daa74423.eastus2.azuresre.ai",
    "API_BASE_URL": "https://ca-api-ps64h2ydsavgc.icymeadow-96da5d2b.eastus2.azurecontainerapps.io",
    "RG": "rg-aqsre",
    "ALERT_RULE_NAME": "alert-api-5xx",
}


def load_env():
    env_file = Path(__file__).resolve().parent.parent / ".env.deployment"
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            line = line.strip()
            if line.startswith("#") or "=" not in line:
                continue
            line = line.removeprefix("export ")
            key, _, val = line.partition("=")
            os.environ.setdefault(key.strip(), val.strip().strip('"').strip("'"))
    for key in CONFIG:
        if key in os.environ:
            CONFIG[key] = os.environ[key]


def http_get(url: str, timeout: int = 15) -> dict | None:
    """Simple GET returning JSON or None."""
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except Exception as exc:
        print(f"  WARNING: GET {url[:60]}... failed: {exc}")
        return None


def http_post(url: str, body: dict | None = None, timeout: int = 15) -> tuple[int, str]:
    """Simple POST returning (status_code, body_text)."""
    data = json.dumps(body).encode() if body else None
    headers = {"Content-Type": "application/json"} if data else {}
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", errors="replace")
    except Exception as exc:
        return 0, str(exc)


def get_sre_token():
    return subprocess.check_output(
        ["az", "account", "get-access-token",
         "--resource", SRE_AUDIENCE, "--query", "accessToken", "-o", "tsv"],
        text=True, stderr=subprocess.DEVNULL,
    ).strip()


# ── Test Steps ────────────────────────────────────────────────────────

def check_status():
    """Check current API and alert status."""
    print("\n── 1. Current Status ──")
    base = CONFIG["API_BASE_URL"]

    # Health
    health = http_get(f"{base}/health")
    if health:
        print(f"  API health: {health.get('status', 'unknown')}")
    else:
        print("  API health: UNREACHABLE")
        return False

    # Supplier status + CB
    status = http_get(f"{base}/api/supplier/status")
    if status:
        cb = status.get("circuitBreaker", {})
        print(f"  Rate limiter: {status.get('requestCount', '?')}/{status.get('limit', '?')} "
              f"({'RATE LIMITED' if status.get('isRateLimited') else 'OK'})")
        print(f"  Circuit breaker: {cb.get('state', '?')} "
              f"(failures: {cb.get('failureCount', '?')}/{cb.get('threshold', '?')})")
        if cb.get("state") == "OPEN":
            retry = cb.get("retryAfterMs")
            if retry and retry > 0:
                print(f"    Resets in: {retry / 1000:.1f}s")
            else:
                print(f"    Cool-down expired, next call will probe.")
    else:
        print("  Supplier status: unavailable")

    return True


def trigger_5xx_errors(count: int = 8):
    """Trigger rate limit failures to trip the circuit breaker."""
    print(f"\n── 2. Triggering {count} rate-limit calls to trip CB ──")
    base = CONFIG["API_BASE_URL"]

    for i in range(1, count + 1):
        code, body = http_post(f"{base}/api/demo/trigger-rate-limit")
        print(f"  req {i}: HTTP {code}")
        if code == 0:
            # SSL/connection error, retry once
            time.sleep(1)
            code, body = http_post(f"{base}/api/demo/trigger-rate-limit")
            print(f"  req {i} (retry): HTTP {code}")

    # Wait a moment for state to settle
    time.sleep(2)

    # Check CB state
    status = http_get(f"{base}/api/supplier/status")
    if status:
        cb = status.get("circuitBreaker", {})
        state = cb.get("state", "UNKNOWN")
        print(f"\n  Circuit breaker is now: {state}")
        if state == "OPEN":
            print("  5xx errors should now be flowing into Loki.")
            return True
        else:
            print(f"  WARNING: CB not OPEN (state={state}). May need more failures.")
            return False
    return False


def manual_fire_trigger():
    """Directly fire the SRE Agent HTTP Trigger with a simulated alert payload."""
    print("\n── 3. Manual fire: sending test alert payload to SRE Agent ──")

    endpoint = CONFIG["SRE_AGENT_ENDPOINT"]
    token = get_sre_token()

    # Find the trigger
    req = urllib.request.Request(
        f"{endpoint}/api/v1/httptriggers",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        triggers = json.loads(resp.read().decode())

    trigger_url = None
    for t in (triggers or []):
        if t.get("name") == "azure-monitor-5xx-alert":
            trigger_url = f"{endpoint}/api/v1/httptriggers/trigger/{t['id']}"
            break

    if not trigger_url:
        print("  ERROR: HTTP trigger 'azure-monitor-5xx-alert' not found.")
        print("  Run setup_reactive_alert.py first.")
        return

    print(f"  Trigger URL: {trigger_url}")

    # Simulate Azure Monitor Common Alert Schema payload
    alert_payload = {
        "schemaId": "azureMonitorCommonAlertSchema",
        "data": {
            "essentials": {
                "alertId": f"/subscriptions/{os.environ.get('SUBSCRIPTION_ID', 'test')}/test-alert",
                "alertRule": CONFIG["ALERT_RULE_NAME"],
                "severity": "Sev2",
                "signalType": "Metric",
                "monitorCondition": "Fired",
                "monitoringService": "Platform",
                "alertTargetIDs": [
                    f"/subscriptions/{os.environ.get('SUBSCRIPTION_ID', 'test')}"
                    f"/resourceGroups/{CONFIG['RG']}"
                    f"/providers/Microsoft.App/containerapps/ca-api-ps64h2ydsavgc"
                ],
                "configurationItems": ["ca-api-ps64h2ydsavgc"],
                "originAlertId": "test-manual-fire",
                "firedDateTime": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "description": "HTTP 5xx errors detected on grocery-api (manual test fire)",
                "essentialsVersion": "1.0",
                "alertContextVersion": "1.0",
            },
        },
    }

    data = json.dumps(alert_payload).encode()
    fire_req = urllib.request.Request(
        trigger_url, data=data,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(fire_req, timeout=60) as resp:
            body = resp.read().decode()
            print(f"  HTTP {resp.status}")
            if body.strip():
                try:
                    print(f"  Response: {json.dumps(json.loads(body), indent=2)}")
                except json.JSONDecodeError:
                    print(f"  Response: {body[:300]}")
            print("\n  Check the SRE Agent UI for a new investigation thread.")
    except urllib.error.HTTPError as exc:
        print(f"  HTTP {exc.code}: {exc.read().decode()[:300]}")


def reset_demo():
    """Reset rate limiter and circuit breaker for demo readiness."""
    print("\n── Reset: restoring demo state ──")
    base = CONFIG["API_BASE_URL"]

    code, body = http_post(f"{base}/api/demo/reset-rate-limit")
    print(f"  Reset rate limit: HTTP {code}")

    code, body = http_post(f"{base}/api/demo/reset-circuit-breaker")
    print(f"  Reset circuit breaker: HTTP {code}")

    time.sleep(1)
    status = http_get(f"{base}/api/supplier/status")
    if status:
        cb = status.get("circuitBreaker", {})
        print(f"  Final state: rate_limited={status.get('isRateLimited')}, "
              f"CB={cb.get('state')}, failures={cb.get('failureCount')}")


# ── Main ──────────────────────────────────────────────────────────────

def main():
    load_env()

    parser = argparse.ArgumentParser(
        description="Test the Azure Monitor → SRE Agent reactive alert pipeline",
    )
    parser.add_argument("--manual-fire", action="store_true",
                        help="Also fire the HTTP trigger directly (skip alert/Logic App wait)")
    parser.add_argument("--reset-only", action="store_true",
                        help="Only reset rate limit + circuit breaker")
    args = parser.parse_args()

    print("╔══════════════════════════════════════════════════════════════╗")
    print("║  Reactive Alert Pipeline — End-to-End Test                  ║")
    print("╚══════════════════════════════════════════════════════════════╝")

    if args.reset_only:
        reset_demo()
        return

    reachable = check_status()
    if not reachable:
        print("\nAPI is unreachable. Exiting.")
        sys.exit(1)

    cb_open = trigger_5xx_errors(count=8)

    if args.manual_fire:
        manual_fire_trigger()

    if cb_open:
        print("\n── What happens next (if alert pipeline is wired) ──")
        print("  1. Azure Monitor evaluates the 5xx metric (1m frequency)")
        print("  2. Alert fires → action group webhook → Logic App")
        print("  3. Logic App acquires MI token → POSTs to SRE Agent HTTP Trigger")
        print("  4. SRE Agent starts investigation thread")
        print(f"\n  Check the SRE Agent UI: {CONFIG['SRE_AGENT_ENDPOINT']}")

    # Ask before resetting
    print()
    try:
        answer = input("Reset rate limit + circuit breaker? [Y/n] ")
    except (EOFError, KeyboardInterrupt):
        answer = "n"
    if answer.lower() != "n":
        reset_demo()
    else:
        print("  Skipping reset. Run with --reset-only to clean up later.")


if __name__ == "__main__":
    main()
