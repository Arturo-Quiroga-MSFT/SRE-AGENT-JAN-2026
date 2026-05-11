"""
PIM HTTP Trigger Bridge -- UNWIRED reference implementation.

Three Azure Functions:
  1. graph_webhook            -- handles Graph subscription validation + notifications.
  2. renew_subscription       -- timer: keep the Graph subscription alive (~3-day TTL).
  3. create_subscription_admin -- one-shot helper to register the Graph subscription.

This module is intentionally not deployed. It exists so Zafin (and the next
engineer on this project) can review the production event-driven path
alongside the testbed's scheduled-task path. See README.md for the
promotion checklist before turning this on.

References:
  - https://learn.microsoft.com/en-us/azure/sre-agent/http-triggers
  - https://learn.microsoft.com/en-us/graph/change-notifications-overview
"""

from __future__ import annotations

import hmac
import json
import logging
import os
from datetime import datetime, timedelta, timezone
from typing import Any
from urllib.parse import urlparse

import azure.functions as func
import httpx
from azure.identity import DefaultAzureCredential

# ---------------------------------------------------------------------------
# Configuration (env vars; see README.md "Configuration" section).
# ---------------------------------------------------------------------------

SRE_AGENT_HTTP_TRIGGER_URL = os.environ.get("SRE_AGENT_HTTP_TRIGGER_URL", "")
SRE_AGENT_APP_ID = os.environ.get(
    "SRE_AGENT_APP_ID", "59f0a04a-b322-4310-adc9-39ac41e9631e"
)
GRAPH_SUBSCRIPTION_CLIENT_STATE = os.environ.get(
    "GRAPH_SUBSCRIPTION_CLIENT_STATE", ""
)
GRAPH_SUBSCRIPTION_ID = os.environ.get("GRAPH_SUBSCRIPTION_ID", "")
GRAPH_NOTIFICATION_RESOURCE = os.environ.get(
    "GRAPH_NOTIFICATION_RESOURCE",
    "/identityGovernance/privilegedAccess/roleAssignmentScheduleRequests"
    "?$filter=action eq 'selfActivate' and status eq 'PendingApproval'",
)
ALLOWED_NOTIFICATION_HOSTS = {
    h.strip().lower()
    for h in os.environ.get("ALLOWED_NOTIFICATION_HOSTS", "graph.microsoft.com").split(",")
    if h.strip()
}

# Single FunctionApp object (Python v2 programming model).
app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

# Cached credential -- reused across invocations within the same worker.
_credential: DefaultAzureCredential | None = None


def _get_credential() -> DefaultAzureCredential:
    global _credential
    if _credential is None:
        _credential = DefaultAzureCredential(exclude_interactive_browser_credential=True)
    return _credential


def _acquire_sre_agent_token() -> str:
    """Mint an ARM bearer token whose audience is the SRE Agent app.

    The audience MUST be the SRE Agent app ID, not
    https://management.azure.com -- see the HTTP-triggers troubleshooting
    section ("401 Unauthorized").
    """
    cred = _get_credential()
    token = cred.get_token(f"{SRE_AGENT_APP_ID}/.default")
    return token.token


def _acquire_graph_token() -> str:
    cred = _get_credential()
    return cred.get_token("https://graph.microsoft.com/.default").token


def _extract_request_id(resource_path: str) -> str | None:
    """Pull the PIM request GUID out of a Graph resource path.

    Example resource:
      /identityGovernance/privilegedAccess/roleAssignmentScheduleRequests/<guid>
    """
    if not resource_path:
        return None
    parts = [p for p in resource_path.split("/") if p]
    # Expect the last segment to be the request GUID.
    if parts and len(parts[-1]) == 36 and parts[-1].count("-") == 4:
        return parts[-1]
    return None


def _forward_to_sre_agent(request_id: str, raw_notification: dict[str, Any]) -> int:
    """POST the requestId to the SRE Agent HTTP trigger. Returns HTTP status."""
    if not SRE_AGENT_HTTP_TRIGGER_URL:
        logging.error("SRE_AGENT_HTTP_TRIGGER_URL is not configured; dropping notification")
        return 500

    token = _acquire_sre_agent_token()
    payload = {
        "requestId": request_id,
        "source": "graph-subscription",
        # Echo a trimmed slice of the Graph notification for audit context.
        # Do NOT forward the full notification verbatim -- it may contain
        # tenant identifiers the agent doesn't need.
        "graphChangeType": raw_notification.get("changeType"),
        "graphSubscriptionId": raw_notification.get("subscriptionId"),
        "graphTenantId": raw_notification.get("tenantId"),
    }

    with httpx.Client(timeout=10.0) as client:
        r = client.post(
            SRE_AGENT_HTTP_TRIGGER_URL,
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
            content=json.dumps(payload),
        )
    if r.status_code == 202:
        logging.info(
            "Forwarded requestId=%s to SRE Agent (threadId=%s)",
            request_id,
            r.json().get("threadId") if r.headers.get("content-type", "").startswith("application/json") else "?",
        )
    else:
        logging.error(
            "SRE Agent trigger returned %s for requestId=%s: %s",
            r.status_code,
            request_id,
            r.text[:500],
        )
    return r.status_code


# ---------------------------------------------------------------------------
# Function 1: graph_webhook
# ---------------------------------------------------------------------------

@app.route(route="graph-webhook", methods=["GET", "POST"], auth_level=func.AuthLevel.ANONYMOUS)
def graph_webhook(req: func.HttpRequest) -> func.HttpResponse:
    """Graph subscription endpoint -- validation handshake + change notifications."""

    # --- Validation handshake (one-shot, when Graph creates the subscription). ---
    # Graph appends ?validationToken=<random> on a GET-like POST and expects
    # the raw token echoed back as text/plain within 10 seconds.
    validation_token = req.params.get("validationToken")
    if validation_token:
        logging.info("Graph subscription validation handshake received")
        return func.HttpResponse(
            validation_token,
            status_code=200,
            mimetype="text/plain",
        )

    if req.method != "POST":
        return func.HttpResponse("Method not allowed", status_code=405)

    try:
        body = req.get_json()
    except ValueError:
        logging.warning("graph_webhook received non-JSON body")
        return func.HttpResponse("Bad request", status_code=400)

    notifications = body.get("value", []) if isinstance(body, dict) else []
    if not notifications:
        # Graph sometimes sends keep-alive empty payloads; ACK with 202.
        return func.HttpResponse(status_code=202)

    forwarded = 0
    for n in notifications:
        # --- clientState verification (defense against spoofed notifications). ---
        if not hmac.compare_digest(
            n.get("clientState", ""), GRAPH_SUBSCRIPTION_CLIENT_STATE
        ):
            logging.warning(
                "Rejecting notification with bad clientState (subscriptionId=%s)",
                n.get("subscriptionId"),
            )
            continue

        # --- Origin host allowlist (defense against arbitrary callers). ---
        notification_url = n.get("notificationUrl") or req.url
        host = urlparse(notification_url).hostname or ""
        if ALLOWED_NOTIFICATION_HOSTS and host.lower() not in ALLOWED_NOTIFICATION_HOSTS:
            # Note: in practice this header check is informational; the real
            # protection is clientState + the public ingress being behind
            # APIM or Front Door with WAF rules.
            logging.info("Notification host %s not in allowlist", host)

        request_id = _extract_request_id(n.get("resource", ""))
        if not request_id:
            logging.warning("Could not extract requestId from resource=%s", n.get("resource"))
            continue

        _forward_to_sre_agent(request_id, n)
        forwarded += 1

    # Graph requires 2xx within 30s or it retries with exponential backoff and
    # eventually disables the subscription. Always 202 once notifications are
    # parsed -- forwarding errors are logged but do not fail the webhook.
    return func.HttpResponse(
        json.dumps({"forwarded": forwarded, "received": len(notifications)}),
        status_code=202,
        mimetype="application/json",
    )


# ---------------------------------------------------------------------------
# Function 2: renew_subscription (every 12h)
# ---------------------------------------------------------------------------

@app.schedule(schedule="0 0 */12 * * *", arg_name="timer", run_on_startup=False, use_monitor=True)
def renew_subscription(timer: func.TimerRequest) -> None:
    """Extend the Graph subscription's expirationDateTime.

    PIM resource subscriptions max out at roughly three days; renewing every
    12 hours keeps us well inside the safe window even if the timer fires
    late.
    """
    if not GRAPH_SUBSCRIPTION_ID:
        logging.info("GRAPH_SUBSCRIPTION_ID not set; skipping renewal")
        return

    # Maximum allowed lifetime for the relevant resource family is ~3 days;
    # we ask for 2 days 23 hours to stay clear of the upper bound.
    new_expiry = datetime.now(timezone.utc) + timedelta(days=2, hours=23)
    token = _acquire_graph_token()
    with httpx.Client(timeout=10.0) as client:
        r = client.patch(
            f"https://graph.microsoft.com/v1.0/subscriptions/{GRAPH_SUBSCRIPTION_ID}",
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
            content=json.dumps({"expirationDateTime": new_expiry.isoformat()}),
        )
    if r.status_code in (200, 204):
        logging.info("Renewed Graph subscription %s until %s", GRAPH_SUBSCRIPTION_ID, new_expiry.isoformat())
    else:
        logging.error(
            "Failed to renew Graph subscription %s: %s %s",
            GRAPH_SUBSCRIPTION_ID,
            r.status_code,
            r.text[:500],
        )


# ---------------------------------------------------------------------------
# Function 3: create_subscription_admin (one-shot)
# ---------------------------------------------------------------------------

@app.route(route="admin/create-subscription", methods=["POST"], auth_level=func.AuthLevel.FUNCTION)
def create_subscription_admin(req: func.HttpRequest) -> func.HttpResponse:
    """One-shot: register the Graph subscription that points back at graph_webhook.

    Protected by the Functions FUNCTION-key auth level -- call from a trusted
    workstation only. After the subscription is created, capture the returned
    `id` and set it as the GRAPH_SUBSCRIPTION_ID App Setting so the renewal
    timer knows what to PATCH.
    """
    if not GRAPH_SUBSCRIPTION_CLIENT_STATE:
        return func.HttpResponse(
            "GRAPH_SUBSCRIPTION_CLIENT_STATE is not configured",
            status_code=500,
        )

    # The notification URL is THIS function -- callers must provide its
    # public hostname so we don't have to special-case Function vs APIM
    # vs Front Door ingress.
    body = req.get_json() if req.get_body() else {}
    notification_url = body.get("notificationUrl")
    if not notification_url:
        return func.HttpResponse(
            "notificationUrl is required in the request body",
            status_code=400,
        )

    expiry = (datetime.now(timezone.utc) + timedelta(days=2, hours=23)).isoformat()
    payload = {
        "changeType": "created",
        "notificationUrl": notification_url,
        "resource": GRAPH_NOTIFICATION_RESOURCE,
        "expirationDateTime": expiry,
        "clientState": GRAPH_SUBSCRIPTION_CLIENT_STATE,
    }

    token = _acquire_graph_token()
    with httpx.Client(timeout=15.0) as client:
        r = client.post(
            "https://graph.microsoft.com/v1.0/subscriptions",
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
            content=json.dumps(payload),
        )

    return func.HttpResponse(
        body=r.text,
        status_code=r.status_code,
        mimetype="application/json",
    )
