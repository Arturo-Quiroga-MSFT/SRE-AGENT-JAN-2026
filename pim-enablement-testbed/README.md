# PIM Enablement Testbed

> Azure SRE Agent — PIM Enablement use case for Zafin
> Status: **E2E partially validated (May 7, 2026)** · Layer 1 (gap-filler) and Layer 2 (Graph plumbing) green; Layer 3 (Foundry agent wiring) in progress
> Architecture: **Hybrid — Enterprise MCP + thin custom MCP for one endpoint**
> Target: mid-June 2026 internal demo · end-of-June customer-facing demo

This testbed implements the **PIM Enablement** use case agreed with Zafin
on May 1, 2026: an SRE agent that **validates** privileged-access requests
and **recommends** approve / deny via Adaptive Card in Teams. A human still
approves in the PIM portal — banking compliance forbids fully autonomous
approvals.

**May 4 update — major simplification (with one caveat):** Microsoft shipped the
[**MCP Server for Enterprise**](https://learn.microsoft.com/en-us/graph/mcp-server/overview)
(public preview) which exposes Microsoft Graph (including most PIM data) as a
hosted, Microsoft-managed remote MCP server. We use it for ~90% of the
required Graph reads. See [`docs/enterprise-mcp-setup.md`](docs/enterprise-mcp-setup.md).

**May 4 update — verified gap (live test in `MngEnvMCAP094150` tenant):** the
`/roleManagement/directory/roleAssignmentScheduleRequests` endpoint — the only
endpoint that exposes **PendingApproval** PIM requests — is **structurally
unreachable** through the Enterprise MCP server in current preview, even with
an Entra ID P2 license and all 7 published `MCP.*` scopes granted. Root cause:
the Graph endpoint requires the **`RoleAssignmentSchedule.ReadWrite.Directory`**
delegated permission (Graph chose not to publish a delegated read-only variant
for the *Requests* collection — see
[Graph API reference](https://learn.microsoft.com/en-us/graph/api/rbacapplication-list-roleassignmentschedulerequests?view=graph-rest-1.0&tabs=http#permissions)),
but the Enterprise MCP server in preview only mirrors `Read.*` Graph scopes
(write support is on Microsoft's roadmap, no ETA). We therefore keep a **tiny
custom MCP server** (1 tool: `list_pending_pim_requests`) that uses an app-only
Graph token via Managed Identity to fill exactly this one gap. See
[`mcp-servers/pim-mcp/`](mcp-servers/pim-mcp/) and
[`infra/pim-mcp-aca.bicep`](infra/pim-mcp-aca.bicep).

Architecture and design rationale: see
[`partner-context/PIM_ENABLEMENT_ARCH_SKETCH.md`](../partner-context/PIM_ENABLEMENT_ARCH_SKETCH.md)
and the standalone deck
[`partner-context/ZAFIN_PIM_ENABLEMENT_DECK_MAY2026.pptx`](../partner-context/ZAFIN_PIM_ENABLEMENT_DECK_MAY2026.pptx).

**Live test artifacts (May 5–7):**
[`test-plan-May-5-2026.md`](./test-plan-May-5-2026.md) ·
[`test-results-May-5-2026.md`](./test-results-May-5-2026.md) ·
[`from-sre-agent-1.md`](./from-sre-agent-1.md) (sample SRE-agent self-summary).

---

## Current state — May 7, 2026

| Layer | What it covers | Status |
|---|---|---|
| **Layer 1 — gap-filler infra** | `pim-mcp` 0.2.4 deployed to Container Apps; MI bound to Graph; SSE `/sse` healthy; smoke test green | ✅ |
| **Layer 2 — Graph plumbing** | Test users created (`pim-requester`, `pim-approver`); eligibility assigned (`Provisioned`); approval policy patched (`isApprovalRequired=true`); requester self-activation lands `PendingApproval` | ✅ |
| **Layer 1 ↔ 2 chain** | `list_pending_pim_requests` returns the live PendingApproval request with matching GUID, justification, ticket info | ✅ |
| **Layer 3 — Foundry agent wiring** | Add `pim-mcp` as MCP tool on the SRE agent; verify tool discovery; run prompts 5a/5b/6/8; capture latency | 🟡 in progress |
| **Layer 4 — agent reasoning** | Self-knowledge prompt; `list_pending_pim_requests` invocation; rule-grounded approve/deny recommendation; post-approval re-check | ⬜ blocked on Layer 3 |
| **Layer 5 — latency loop** | 10-trial p50/p95 over `list_pending_pim_requests` for the test-results doc | ⬜ |

**Demo readiness:** the gap-filler + Graph plumbing fully proves the architectural decision (hybrid Enterprise MCP + 1-tool custom MCP). What remains is the Foundry surface — a click-through to register the MCP tool and a small set of prompt validations.

---

## Problem the agent solves

Zafin operates ~2,000–3,000 ops tickets/day. PIM activations require
manual human validation against multiple criteria (ticket exists, ticket
is recent, requester is in the right group, role/scope is in the
allow-list). This creates delays, operational overhead, and inconsistency.

**Goal:** reduce approval time and improve consistency by having an agent
do the deterministic validation work and present the human approver with
a structured recommendation. The human still acts.

**Quantitative targets (Zafin):** 5–10% ticket automation by end of Q2,
25% by end of Q3.

---

## Initial findings — what is needed to set this up

These findings drive the artifact list below. **F1 and F4 were rewritten
on May 4** after the Enterprise MCP server was discovered.

### F1. Agent identity model — Delegated (service account)

**Decision:** The Microsoft MCP Server for Enterprise uses **delegated
permissions only** — application / Managed Identity auth is **not
supported** for PIM reads via this server.

For the scheduled-poll trigger we use a **dedicated service-account
user** in Zafin's tenant, PIM-eligible for read-only roles, granted the
required `MCP.*` scopes on a custom MCP Client app. The agent
authenticates as that user.

For Jira reads/writes and Teams webhook posting, we still use a
Managed Identity (or App Registration secret) since those are not Graph
calls.

**Why:** banking-compliance defensible; full audit trail flows through
Microsoft Graph activity logs filtered on the MCP server `AppId`
(`e8c77dc2-69b3-43f4-bc51-3213c9d915b4`).

### F2. Trigger mechanism — gap

**Decision (V1):** scheduled poll of pending PIM activation requests via
the Enterprise MCP server every 60 seconds. **V2:** move to Graph change
notifications or Event Grid.

### F3. Teams output — gap

**Decision (V1):** Teams **incoming webhook URL** scoped to the approver
channel. **V2:** Microsoft Graph `chats/messages` with per-user
attribution.

### F4. PIM access — hybrid (Enterprise MCP + 1-tool custom MCP)

**Enterprise MCP** ([Microsoft MCP Server for Enterprise](https://learn.microsoft.com/en-us/graph/mcp-server/overview))
is a Microsoft-hosted remote MCP server at
`https://mcp.svc.cloud.microsoft/enterprise` that exposes 3 tools:

- `microsoft_graph_suggest_queries` — RAG over a curated catalog of Graph
  API examples
- `microsoft_graph_get` — runs read-only Graph calls under the user's
  privileges
- `microsoft_graph_list_properties` — schema lookup for Graph entities

PIM is partially in scope ("Privileged access: who has which directory
roles, how assigned, and PIM status"). **Microsoft Foundry is a
first-class supported client.** This eliminates the bulk of
net-new development we had planned.

**Constraints:**

- Delegated auth only (see F1).
- Public cloud only (Zafin is fine here).
- 100 requests/min/user limit on top of standard Graph throttling.
- One-time per-tenant provisioning required (see
  [`docs/enterprise-mcp-setup.md`](docs/enterprise-mcp-setup.md)).
- **Read-only in current preview** — only `MCP.*.Read.*` scopes are published;
  no `ReadWrite` variants exist yet.

**Verified gap (live-tested May 4 in `MngEnvMCAP094150` tenant):** the
`/roleManagement/directory/roleAssignmentScheduleRequests` endpoint —
**the** endpoint where `status eq 'PendingApproval'` lives — returns
`403 Forbidden "not authorized by the available scopes"` even with an
Entra ID P2 license active and all 7 published MCP scopes granted. The
Graph documentation
([API reference](https://learn.microsoft.com/en-us/graph/api/rbacapplication-list-roleassignmentschedulerequests?view=graph-rest-1.0&tabs=http#permissions))
states the LIST operation requires `RoleAssignmentSchedule.ReadWrite.Directory`
or `RoleManagement.ReadWrite.Directory` — both `ReadWrite`. Microsoft's
Enterprise-MCP roadmap commits to write-support "in a future release" but no
ETA. Confirmed reachable today through Enterprise MCP:
`roleAssignmentSchedules`, `roleAssignmentScheduleInstances`,
`roleEligibilitySchedules`, `roleEligibilityScheduleInstances`, `users`,
`groups`, `subscribedSkus`.

**Hybrid resolution:** keep one tiny custom MCP server
([`mcp-servers/pim-mcp/`](mcp-servers/pim-mcp/)) that exposes a single tool
(`list_pending_pim_requests`) using **app-only** Graph auth via Managed
Identity. **Live finding 2026-05-05:** even the app-only path requires
`RoleAssignmentSchedule.ReadWrite.Directory` at runtime (the `Read.Directory`
scope alone returns 403 — see [`docs/UPSTREAM_BUGS.md`](docs/UPSTREAM_BUGS.md)
BUG-001). The custom server is read-only **by construction** (no write tool
is registered) so the elevated token is latent only — compliance posture
is unchanged but documented as Residual Risk #4 in
[`docs/threat-model.md`](docs/threat-model.md).

### F5. Validation rules — Zafin owns the content

The deterministic rules the agent applies are **Zafin's policy**, not
ours. We own the **schema + engine**; they own the **content**. V1 ships
with placeholder rules so we can demo end-to-end before the real rule
table arrives.

### F6. Audit trail — Jira comment + Graph activity logs

V1 audit trail is two-layered:

- **Per-recommendation**: immutable Jira comment on the ticket containing
  inputs read, rules evaluated, verdict, confidence, timestamp.
- **Tenant-wide**: every Enterprise-MCP call is captured in **Microsoft
  Graph activity logs**, filterable by `AppId == e8c77dc2-69b3-43f4-bc51-3213c9d915b4`.
  Microsoft-managed; no extra work on our side.

**V2:** add Storage append-blob if Zafin compliance team requires
file-based retention.

### F7. Identity gotcha — App ID vs SP Object ID

Per the Apr 14 testbed finding: any role assignments still target the
**Service Principal Object ID** of the agent's managed identity, not the
App / Client ID. Less relevant now that PIM reads use a delegated service
account, but still applies to any MI-based assignment (Jira/Teams paths).

### F8. Reuse vs new (revised May 4 post live-test)

| Component | Reuse / Hosted | New |
|---|---|---|
| **PIM reads (90%)** — schedules, eligibilities, users, groups | ✅ **Microsoft MCP Server for Enterprise (Microsoft-hosted)** | — |
| **PIM pending-request reads** — only the `roleAssignmentScheduleRequests` endpoint | — | **NEW (small):** 1-tool custom MCP, app-only auth via MI ([`mcp-servers/pim-mcp/`](mcp-servers/pim-mcp/)) |
| Jira MCP server | ✅ Existing (Jan PoC) | — |
| Container Apps + Bicep patterns | ✅ From `aks-private-testbed/` and `grocery-sre-demo/` | — |
| MCP Client app registration | — | NEW (one-time tenant provisioning) |
| Service-account user + PIM eligibility | — | NEW (one-time test-tenant provisioning) |
| Adaptive Card template | — | NEW |
| Validation rules engine | — | NEW (schema; placeholder content) |
| Teams output (webhook) | — | NEW (small) |
| Test users / groups / PIM-eligible assignments | — | NEW (one-time provisioning) |

---

## Folder layout

```text
pim-enablement-testbed/
├── README.md                       # This file
├── azure.yaml                      # azd template
├── test-plan-May-5-2026.md         # 10-step E2E validation plan
├── test-results-May-5-2026.md      # Live execution log (Steps 2–4 ✅)
├── from-sre-agent-1.md             # Sample SRE-agent self-summary of this testbed
├── infra/                          # Bicep
│   ├── main.bicep                  # Subscription-level orchestrator
│   ├── pim-test-rg.bicep           # Test RG + Log Analytics + CAE
│   ├── agent-mi.bicep              # MI for Jira / Teams / pim-mcp app-only Graph
│   └── pim-mcp-aca.bicep           # ACTIVE — gap-filler ACA for the one Graph endpoint
│                                   # Enterprise MCP cannot reach today.
├── mcp-servers/
│   └── pim-mcp/                    # ACTIVE — single-tool custom MCP
│                                   # (list_pending_pim_requests + health).
│                                   # App-only Graph auth via Managed Identity.
│                                   # Read-only by construction (no write tools).
│                                   # Will be retired when Enterprise MCP ships
│                                   # write-scope support.
├── agent/
│   ├── knowledge.md                # Agent system prompt + rules + flow
│   ├── adaptive-card.json          # Output card template
│   └── validation-rules.yaml       # Placeholder rule table (Zafin owns content)
├── scripts/
│   ├── REPRODUCE.md                # Step-by-step reproduction guide
│   ├── provision-enterprise-mcp.ps1  # One-time Enterprise-MCP tenant provisioning
│   ├── grant-pim-mcp-app-role.ps1  # Grant app-only Graph roles to pim-mcp MI
│   ├── create-test-users.ps1       # Idempotent test-user creation (requester + approver)
│   ├── seed-test-users.ps1         # Older seed script (groups + bulk users)
│   ├── assign-pim-eligibility.ps1  # Step 2 — assign requester as PIM-eligible
│   ├── configure-pim-approval.ps1  # Step 3 — require approval on activation policy (Beta cmdlets)
│   ├── trigger-pim-activation.ps1  # Step 4 — requester submits self-activation (device code)
│   ├── smoke-test-pim-mcp.py       # Layer-1 smoke test: SSE → list_pending_pim_requests
│   ├── test-enterprise-mcp.py      # Enterprise-MCP reachability probe
│   ├── trigger-pim-request.sh      # Synthetic activation request for demo
│   └── verify-deployment.sh        # End-to-end smoke test
└── docs/
    ├── enterprise-mcp-setup.md     # One-time provisioning walkthrough
    ├── demo-script.md              # Happy path + 3 failure paths
    ├── threat-model.md             # Compliance / threat-model note
    ├── UPSTREAM_BUGS.md            # BUG-001: ReadWrite scope required at runtime
    └── deployment-runbook.md       # Step-by-step setup
```

> `infra/pim-mcp-aca.bicep` and `mcp-servers/pim-mcp/` are **active** as a
> single-purpose gap-filler for the `roleAssignmentScheduleRequests` endpoint
> only. They are scoped to retire as soon as Microsoft publishes
> `MCP.RoleAssignmentSchedule.ReadWrite.Directory` (or equivalent write scope)
> on the Enterprise MCP server. Track:
> <https://github.com/microsoft/EnterpriseMCP/issues>.

---

## Prerequisites

| # | Item | Notes |
|---|---|---|
| 1 | Test Entra tenant with **PIM enabled** + **Entra ID P2** license | Required for PIM data via Graph |
| 2 | Azure subscription where the test RG lives | Cost: minimal |
| 3 | Tenant-admin permissions for one-time MCP Server provisioning | `Application.ReadWrite.All`, `DelegatedPermissionGrant.ReadWrite.All` |
| 4 | Azure CLI ≥ 2.65 + Bicep ≥ 0.30 | `az upgrade` |
| 5 | PowerShell 7 + `Microsoft.Entra.Beta` ≥ 1.0.13 | For `Grant-EntraBetaMCPServerPermission` |
| 6 | Foundry workspace + permissions to create an SRE Agent | Existing `aq-main` workspace is fine |
| 7 | Existing Jira MCP endpoint + Jira project for test tickets | From Jan PoC |
| 8 | Teams channel + permission to create an Incoming Webhook | Decide channel in next session |

---

## What you need from Zafin (asks for next session)

| # | Ask | Blocking? |
|---|---|---|
| D1 | Validation rule table (the actual criteria the agent applies) | Soft — placeholders unblock demo |
| D2 | Role / scope allow-list policy | Soft |
| D3 | Teams channel(s) for Adaptive Card output | Hard for production; webhook URL works for demo |
| D4 | Audit format requirement (banking compliance team) | Soft for V1 (Jira comment + Graph activity logs) |
| D5 | **Confirm Enterprise MCP server is approved for use in Zafin's tenant** | **Hard — new May 4 ask.** Requires one-time provisioning by tenant admin. |
| D6 | Service-account user identity for the agent (PIM-eligible reader) | Hard for production; we provision in our test tenant for V1 |
| D7 | Confirm SP **Object IDs** used in their Jira/Teams MI assignments | One-line confirmation |

---

## Build order (mid-June target)

| Week | Focus | Status |
|------|-------|---|
| **W1** | Provision test tenant + RG; provision Enterprise MCP Server; MCP Client app; service-account user | ✅ |
| **W1** | Build + deploy `pim-mcp` 0.2.4 to ACA; MI bound; smoke test green | ✅ |
| **W1** | Agent knowledge file + Adaptive Card + placeholder rules | ✅ |
| **W2** (now) | E2E test plan; create test users; assign eligibility; configure approval; trigger activation; full chain validated | ✅ Steps 2–4 |
| **W2** | Wire `pim-mcp` into Foundry SRE agent; run prompt validations 5a/5b/6/8 | 🟡 in progress |
| **W2** | Latency loop (p50/p95); approver flow + post-approval re-check | ⬜ |
| **W3** | Wire Jira MCP + Teams webhook; first true end-to-end (PIM event → recommendation → card) | ⬜ |
| **W3** | Failure-path scenarios; demo walkthrough; threat-model note finalize | ⬜ |
| **W4** | Buffer / iterate; rehearse | ⬜ |
| **W5** (mid-June) | Internal demo to Poornika / Jiban / Richard | ⬜ |
| **W6** | Iterate on Zafin's actual rule table once received; customer demo | ⬜ |

> The Enterprise MCP server pivot collapsed the original PIM-MCP build into
> ~2 days of provisioning + a single-tool gap-filler. Layers 1 and 2 are
> validated end-to-end as of May 7. Remaining work is Foundry-side surface
> wiring + rule iteration.

---

## Open risks

1. **Enterprise MCP server is preview.** Watch for breaking changes
   before mid-June. The custom `pim-mcp` is also preview-tier code; both
   need a smoke test the day before any demo.
2. **`roleAssignmentScheduleRequests` requires app-only or `ReadWrite` delegated**
   ([Graph docs](https://learn.microsoft.com/en-us/graph/api/rbacapplication-list-roleassignmentschedulerequests?view=graph-rest-1.0&tabs=http#permissions)).
   Our custom `pim-mcp` uses **app-only** auth via Managed Identity.
   **Verified live 2026-05-05:** despite the docs claiming
   `RoleAssignmentSchedule.Read.Directory` (app) is sufficient, Graph
   runtime returns `403 PermissionScopeNotGranted` and explicitly
   demands `RoleAssignmentSchedule.ReadWrite.Directory`. We therefore
   grant **both** roles (Read kept for the day Microsoft fixes the
   runtime). Compensating control: the server registers no write tools
   so the elevated token is latent only. Banking compliance review needs
   to be aware that pending-request reads happen as the app, not as a
   user. Full details and reproduction in
   [`docs/UPSTREAM_BUGS.md`](docs/UPSTREAM_BUGS.md) (BUG-001).
3. **Delegated auth only for Enterprise MCP** — the service-account user
   becomes a real identity to manage. Document MFA / Conditional Access
   exemptions carefully.
4. **Tenant-admin provisioning gate** in Zafin's tenant could slow
   things down — confirm D5 fast. (Now also requires app-permission
   grant for the custom pim-mcp MI: both
   `RoleAssignmentSchedule.ReadWrite.Directory` and
   `RoleAssignmentSchedule.Read.Directory` app roles — see
   [`docs/UPSTREAM_BUGS.md`](docs/UPSTREAM_BUGS.md) BUG-001 — plus
   `AcrPull` on the ACR holding the `pim-mcp` image.)
5. **Zafin validation rules** may arrive late or change V1 placeholder
   schema. Keep `validation-rules.yaml` simple and configurable.
6. **Optimus partner overlap** unresolved — boundary doc owed by Richard.

---

## Related artifacts

- Architecture sketch: [`../partner-context/PIM_ENABLEMENT_ARCH_SKETCH.md`](../partner-context/PIM_ENABLEMENT_ARCH_SKETCH.md)
- Internal-review deck: [`../partner-context/ZAFIN_PIM_ENABLEMENT_DECK_MAY2026.pptx`](../partner-context/ZAFIN_PIM_ENABLEMENT_DECK_MAY2026.pptx)
- Hybrid identity slide: [`../partner-context/ZAFIN_HYBRID_IDENTITY_ONESLIDE.pptx`](../partner-context/ZAFIN_HYBRID_IDENTITY_ONESLIDE.pptx)
- Validated RBAC pattern: [`../partner-context/ZAFIN_AKS_LOCKED_FINDINGS.md`](../partner-context/ZAFIN_AKS_LOCKED_FINDINGS.md)
- Updated gap analysis: [`../partner-context/ZAFIN_GAP_ANALYSIS_MARCH_2026.md`](../partner-context/ZAFIN_GAP_ANALYSIS_MARCH_2026.md)
- Microsoft MCP Server for Enterprise — Overview: <https://learn.microsoft.com/en-us/graph/mcp-server/overview>
- Microsoft MCP Server for Enterprise — Repo: <https://github.com/microsoft/EnterpriseMCP>
- Use from Microsoft Foundry: <https://learn.microsoft.com/graph/mcp-server/use-enterprise-mcp-server-microsoft-foundry>
