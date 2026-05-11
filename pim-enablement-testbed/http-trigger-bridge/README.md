# PIM HTTP Trigger Bridge — Azure Function (UNWIRED reference)

> **Status:** Reference scaffold for Zafin review. **Not deployed**, not wired to a live Microsoft Graph subscription, and not yet pointed at a real SRE Agent HTTP trigger URL. This folder exists so the production event-driven design lives in the repo alongside the testbed implementation.
>
> **Promotion path:** see [`../WAVE-ROADMAP.md`](../WAVE-ROADMAP.md) → **Wave E — Event-driven trigger**. Wave E lands after Waves A–D have proven the rule pack against the scheduled-task path.

## What this Function does

A minimal HTTPS bridge that sits between **Microsoft Graph change notifications** for PIM activation requests and the **`pim-recommender` SRE Agent HTTP trigger**. It exists because Graph webhooks ship plain HTTPS posts with Graph's own auth model, but the SRE Agent HTTP trigger endpoint requires an **Azure Resource Manager bearer token whose audience is the SRE Agent app ID** (`59f0a04a-b322-4310-adc9-39ac41e9631e`). The Function bridges those two auth models using its system-assigned managed identity.

```
┌───────────────────────────────────────────────────────────────────────┐
│  Microsoft Graph                                                       │
│  /identityGovernance/privilegedAccess/roleAssignmentScheduleRequests   │
│       │  changeType=created                                            │
│       ▼                                                                │
│  HTTPS POST notification (JSON)                                        │
│       │                                                                │
│       ▼                                                                │
│  THIS FUNCTION (graph_webhook trigger)                                 │
│   • validate clientState                                               │
│   • for each notification: extract requestId from resource path        │
│   • acquire ARM token for SRE Agent app via DefaultAzureCredential     │
│   • POST to <SRE_AGENT_HTTP_TRIGGER_URL> with                          │
│     { "requestId": "...", "source": "graph-subscription" }             │
│       │                                                                │
│       ▼                                                                │
│  SRE Agent HTTP trigger (pim-request-created)                          │
│       │  invokes custom agent pim-recommender                          │
│       ▼                                                                │
│  pim-recommender evaluates R001–R011, emits Adaptive Card, audits      │
│  to Jira, mails the approver.                                          │
└───────────────────────────────────────────────────────────────────────┘
```

## Why not call the SRE Agent directly from Graph?

Three reasons, all from the [HTTP triggers documentation](https://learn.microsoft.com/en-us/azure/sre-agent/http-triggers):

1. **Auth audience mismatch.** Graph notifications carry no Azure auth; the SRE Agent trigger requires `Authorization: Bearer <token>` where the audience is the SRE Agent app ID. The Function mints that token from its managed identity (no secrets).
2. **Validation handshake.** Graph subscription creation requires a synchronous validation response (return the `validationToken` query param as `text/plain` within 10 seconds). The SRE Agent trigger returns `HTTP 202` and runs async — it can't satisfy the handshake.
3. **Subscription lifecycle.** Graph subscriptions for `roleAssignmentScheduleRequests` expire roughly every three days. The Function's `renew` timer entry handles renewal so the data plane doesn't go silent.

## File layout

```
http-trigger-bridge/
├── README.md                  # this file
├── host.json                  # Functions host config
├── requirements.txt           # azure-functions, azure-identity, httpx, ...
├── local.settings.json.sample # env var template (never check in real secrets)
├── function_app.py            # the three Functions: graph_webhook, renew, create_subscription
└── .funcignore                # exclude venv, .git, etc. from deployment package
```

## The three Functions

| Name | Trigger | Purpose |
|---|---|---|
| `graph_webhook` | `httpTrigger` (anonymous, POST/GET) | Handles Graph's validation handshake on `GET` and the change-notification POSTs on `POST`. For each notification, mints an ARM token via the Function's MI and forwards `{ requestId, source: "graph-subscription" }` to the SRE Agent HTTP trigger. |
| `renew_subscription` | `timerTrigger` (every 12 hours) | Calls Graph `PATCH /subscriptions/{id}` to extend `expirationDateTime`. PIM resource subscriptions max out around three days; renewing every 12 hours keeps them well inside the safe window. |
| `create_subscription_admin` | `httpTrigger` (admin-only, POST) | One-shot helper to create the initial Graph subscription. Not strictly needed at runtime — you can also create the subscription via `az rest` or Postman. Kept here so the entire wiring is reproducible from this folder. |

## Configuration (env vars)

| Variable | Required | Description |
|---|---|---|
| `SRE_AGENT_HTTP_TRIGGER_URL` | yes | The trigger URL copied from **Builder → HTTP triggers → pim-request-created → Trigger URL** in the SRE Agent portal. |
| `SRE_AGENT_APP_ID` | yes | Defaults to `59f0a04a-b322-4310-adc9-39ac41e9631e` (the SRE Agent app ID). Override only if Microsoft rotates it. |
| `GRAPH_SUBSCRIPTION_CLIENT_STATE` | yes | A random opaque secret (≥ 32 chars). Stored on the subscription; Graph echoes it on every notification. The Function rejects any notification whose `clientState` doesn't match. |
| `GRAPH_SUBSCRIPTION_ID` | yes (after first create) | The GUID returned by `POST /subscriptions`. Stored so `renew_subscription` knows what to PATCH. |
| `GRAPH_NOTIFICATION_RESOURCE` | yes | `/identityGovernance/privilegedAccess/roleAssignmentScheduleRequests?$filter=action eq 'selfActivate' and status eq 'PendingApproval'` — narrows the firehose. |
| `ALLOWED_NOTIFICATION_HOSTS` | optional | Comma-separated list of allowed `notificationUrl` hosts; defaults to `graph.microsoft.com`. |

The Function's **system-assigned managed identity** must have:

- `Microsoft.App/agents/threads/write` on the SRE Agent resource (to invoke the HTTP trigger).
- Application permission `RoleManagement.Read.Directory` on Microsoft Graph (to read PIM requests, only used in optional enrichment paths).

## Required role assignment

Once deployed, grant the Function's MI access to the SRE Agent. This is the same pattern as `pim-mcp` → Graph; see [`PIM-RECOMMENDER-AGENT-CONFIG.md`](../PIM-RECOMMENDER-AGENT-CONFIG.md) for the production pattern.

```bash
# After Function deploy, capture its system MI principalId
FUNC_PRINCIPAL_ID=$(az functionapp identity show \
  -g <rg> -n <func-app> --query principalId -o tsv)

# Custom role 'SRE Agent Thread Writer' must already exist on the agent;
# if not, see the SRE Agent HTTP-triggers doc for the role definition.
az role assignment create \
  --assignee "$FUNC_PRINCIPAL_ID" \
  --role "SRE Agent Thread Writer" \
  --scope "<sre-agent-resource-id>"
```

## What's still missing before this becomes runnable

This is intentionally **incomplete** so nothing in this folder accidentally goes live during the testbed phase. Promotion checklist:

1. Create the HTTP trigger `pim-request-created` in the SRE Agent portal (**Builder → HTTP triggers → + Create trigger**), assigned to `pim-recommender`, autonomy = Review. Copy the Trigger URL.
2. `azd init` or `func init` this folder into a real Function App project (target Python 3.11, Flex Consumption plan, Linux). Add `infra/main.bicep` to provision the Function App + storage + system MI + Application Insights.
3. Set the env vars above as App Settings (or wire to Key Vault references).
4. Deploy with `func azure functionapp publish` or `azd up`.
5. POST to `create_subscription_admin` once to register the Graph subscription. Save the returned `id` into `GRAPH_SUBSCRIPTION_ID`.
6. Trigger a real `Privileged Role Administrator` activation in the test tenant. Within seconds (not minutes), `pim-recommender` should run with `source: graph-subscription` visible in the agent's thread context and the resulting Jira audit ticket.

## Non-goals

- **Not** a replacement for the scheduled-task path. Keep `pim-pending-request-evaluator` running on its 5-minute cron as a safety net: Graph can drop notifications under throttling, and the cron sweeps any orphan request a webhook missed.
- **Not** a multi-tenant bridge. One Function App per tenant — Graph subscriptions are tenant-scoped.
- **Not** an auth proxy for non-Microsoft tools. Datadog/Splunk/Jira webhooks each need their own bridge or a unified API Management front door; that's out of scope for this folder.

## References

- [HTTP triggers in Azure SRE Agent](https://learn.microsoft.com/en-us/azure/sre-agent/http-triggers) — endpoint shape, auth audience, payload conventions.
- [Microsoft Graph change notifications overview](https://learn.microsoft.com/en-us/graph/change-notifications-overview) — subscription lifecycle, validation handshake, `clientState`.
- [Graph subscription resource — PIM scope](https://learn.microsoft.com/en-us/graph/api/subscription-post-subscriptions) — supported `resource` strings for PIM activation requests.
- [`../PIM-RECOMMENDER-INSTRUCTIONS.md`](../PIM-RECOMMENDER-INSTRUCTIONS.md) — see **Workflow → step 1**, which already recognizes the push-mode payload this Function emits.
- [`../WAVE-ROADMAP.md`](../WAVE-ROADMAP.md) — Wave E (event-driven trigger) tracks promotion of this scaffold to production.
