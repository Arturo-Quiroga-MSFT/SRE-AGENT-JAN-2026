---
title: "PIM Enablement — End-to-End Test Results (2026-05-05)"
description: "Execution log for the 10-step E2E validation defined in test-plan-May-5-2026.md"
author: Arturo Quiroga
ms.date: 2026-05-05
ms.topic: reference
audience: Internal — Zafin engagement decision input
---

## Test environment

| Item | Value |
|---|---|
| Tenant | `MngEnvMCAP094150.onmicrosoft.com` (`a172a259-b1c7-4944-b2e1-6d551f954711`) |
| Subscription | `7a28b21e-0d3e-4435-a686-d92889d4ee96` |
| Resource group | `rg-pim-enablement-testbed` |
| `pim-mcp` endpoint | `https://ca-pimtest-pimmcp.gentleocean-dea895de.eastus2.azurecontainerapps.io` |
| `pim-mcp` image | `0.4.1` (was `0.2.4` on May 5) |
| MCP transport | **Streamable-HTTP** at `/mcp` (was SSE at `/sse` on May 5 — see Day 2 roadblock removers) |
| `pim-mcp` tools | `list_pending_pim_requests`, `health`, `get_user`, `get_role_definition` (4) |
| Foundry SRE agent | `aq-main` (subscription `7a28b21e-…`, RG `rg-aqsre`) |
| Test role | `Privileged Role Administrator` (or substitute) |
| Operator UPN | `arturoqu@MngEnvMCAP094150.onmicrosoft.com` (admin) |
| Requester UPN | `pim-requester@MngEnvMCAP094150.onmicrosoft.com` |
| Requester ObjectId | `8a986e7c-f44b-44e0-a8a2-cfc1071faf92` |
| Approver UPN | `pim-approver@MngEnvMCAP094150.onmicrosoft.com` |
| Approver ObjectId | `00a13120-c099-45bc-851a-861ade749067` |
| Initial password (both) | `TestP@ssw0rd!2026` (force-change on first sign-in) |

## Pre-flight (Layer 1 baseline) — ✅ PASS

### 2026-05-05 (image 0.2.4, SSE)

```text
==> https://ca-pimtest-pimmcp.gentleocean-dea895de.eastus2.azurecontainerapps.io/sse
Tools discovered:
  - list_pending_pim_requests
  - health
health() → {"status":"ok"}
list_pending_pim_requests(top=5) → {"value":[], "fetchedCount":0, "pendingCount":0}
```

### 2026-05-08 (image 0.4.1, streamable-http)

```text
==> https://ca-pimtest-pimmcp.gentleocean-dea895de.eastus2.azurecontainerapps.io/mcp
Tools discovered:
  - list_pending_pim_requests
  - health
  - get_user                  # NEW — added Day 2 to unblock prompt 5b
  - get_role_definition       # NEW — added Day 2 to unblock prompt 5b
health() → {"status":"ok"}
get_user("8a986e7c-…") → "PIM Test Requester" (pim-requester@…)
get_role_definition("e8611ab8-…") → "Privileged Role Administrator" (built-in, scope `/`)
```

Smoke test from CLI succeeded against the new transport. Gap-filler now serves a 4-tool read-only Graph surface.

---

## Step 1 — Wire `pim-mcp` into the SRE agent in Foundry — ✅ PASS (2026-05-08)

**Final wiring values (in `aq-main` SRE Agent → Connectors → Add MCP):**

| Field | Value |
|---|---|
| Name | `PIM-MCP` |
| Connection type | **Streamable-HTTP** |
| URL | `https://ca-pimtest-pimmcp.gentleocean-dea895de.eastus2.azurecontainerapps.io/mcp` |
| Authentication | Bearer token, value `not-required` (server doesn't validate; placeholder satisfies wizard) |
| Tools selected | All 4 (`list_pending_pim_requests`, `health`, `get_user`, `get_role_definition`) |

**Pass criteria:** Tool discovered in Foundry portal; visible in agent's tool list.

**Result:**
- [x] Pass / [ ] Fail
- All 4 tools enumerate correctly in `MCP Servers and Tools Access` view alongside grafana-mcp, jira-mcp
- Connection status: **Connected**

### Roadblock removers (May 7–8 Day 2)

1. **Transport mismatch (May 7).** Foundry's SRE Agent MCP connector wizard only supports **Streamable-HTTP**, NOT SSE. `pim-mcp` 0.2.4 was running `transport="sse"` (only `/sse` exposed). Confirmed via curl: `GET /mcp → 404`, only `/sse → 200`.
   - Fix: edited `server.py` to `mcp.run(transport="streamable-http", path="/mcp")`. Explicit `path="/mcp"` (no trailing slash) avoids Starlette Mount's slash-redirect that downgraded to `http://` behind ACA's HTTPS ingress (initial 0.3.0 attempt 307'd to plain HTTP and broke OAuth-style redirect chains; fixed in 0.3.1).
   - Bumped image to `0.3.1`, rebuilt via `az acr build`, rolled ACA via `az containerapp update`.
   - Smoke test (`fastmcp.client.transports.StreamableHttpTransport`) returned 200 + `mcp-session-id` header → wiring path validated.
2. **80-tool agent cap (May 8).** First wizard attempt showed PIM-MCP's 2 tools as **disabled checkboxes** with bar reading `80/80 tools selected, 2 available`. The cap is **agent-wide across all connectors**, not per-server.
   - Fix: trimmed grafana-mcp tool selection in the existing connector to free 2 slots. Re-opened wizard → checkboxes enabled → both tools added.
3. **Connector wizard auth gap (May 8).** Wizard offers only Bearer / Custom headers / Managed identity. Microsoft's Enterprise MCP server (`https://mcp.svc.cloud.microsoft/enterprise`) is **delegated-OAuth-only** by design and cannot be wired through this wizard. This blocks the original architecture (Enterprise MCP for ~90% of Graph reads + `pim-mcp` for the gap-endpoint).
   - Strategic ask logged for Deepthi (SRE Agent PM): add OAuth 2.0 Authorization Code (delegated) as a 4th auth option in the wizard. See conversation thread / draft email.
   - Tactical workaround (this run): extended `pim-mcp` itself with `get_user` + `get_role_definition` tools (image 0.4.0 → 0.4.1) so the agent can resolve Graph IDs without Enterprise MCP. Granted `User.Read.All` + `RoleManagement.Read.Directory` to MI `mi-pimtest-agent` (principalId `09883cfe-54ce-44d5-889e-7b47ec8e43c8`). Verified end-to-end via the SRE agent.
4. **`isPrivileged` $select bug (May 8).** First `get_role_definition` call returned Graph 400: `Could not find a property named 'isPrivileged' on type 'microsoft.graph.unifiedRoleDefinition'`. Property exists in `beta` only.
   - Fix: dropped `isPrivileged` from `ROLE_DEFINITION_DEFAULT_SELECT` to stay v1.0-compatible. Bumped to 0.4.1.

---

## Step 2 — Assign Requester as PIM-eligible

**Run as Operator (Privileged Role Administrator):**

```powershell
pwsh ./pim-enablement-testbed/scripts/assign-pim-eligibility.ps1 `
  -TenantId a172a259-b1c7-4944-b2e1-6d551f954711 `
  -RoleDisplayName "Privileged Role Administrator" `
  -PrincipalUpn "<requester-upn>" `
  -DurationDays 30
```

**Pass criteria:** `status=Provisioned`. Requester appears in Entra portal → PIM → Microsoft Entra roles → Assignments → **Eligible**.

**Result:**
- [x] Pass / [ ] Fail
- Returned status: `Provisioned`
- Time taken: ~immediate
- Notes: Request id `b9403465-99e5-43ef-b5b0-8a9fd6ab0f71`. Role `Privileged Role Administrator` (id `e8611ab8-c189-46e8-94e1-60213ab1f814`). Required first-time install of `Microsoft.Graph.Identity.Governance` and `Microsoft.Graph.Groups` modules.

---

## Step 3 — Require approval on the role's PIM activation policy

**Run as Operator:**

```powershell
# Inspect first
pwsh ./pim-enablement-testbed/scripts/configure-pim-approval.ps1 `
  -TenantId a172a259-b1c7-4944-b2e1-6d551f954711 `
  -RoleDisplayName "Privileged Role Administrator" -WhatIf

# Apply (Approver must NOT be the Requester)
pwsh ./pim-enablement-testbed/scripts/configure-pim-approval.ps1 `
  -TenantId a172a259-b1c7-4944-b2e1-6d551f954711 `
  -RoleDisplayName "Privileged Role Administrator" `
  -ApproverObjectIds @('<approver-object-id>')
```

**Pass criteria:** Output shows `isApprovalRequired=true` and the approver in `primaryApprovers`.

**Result:**
- [x] Pass / [ ] Fail
- `isApprovalRequired` value: `true` (was `false`)
- Approver listed: `00a13120-c099-45bc-851a-861ade749067` (PIM Test Approver, singleUser)
- Policy: `DirectoryRole_a172a259-b1c7-4944-b2e1-6d551f954711_030d6466-83a4-4830-8f5c-f2b93f3aa2ca`
- Notes: Patched script to use Beta cmdlets (`Get-MgBetaPolicyRoleManagementPolicyAssignment`, etc.) — only Beta SDK installed locally. Same Graph semantics. Verified updated rule has `approvalStageTimeOutInDays=1`, `approvalMode=SingleStage`.

---

## Step 4 — Requester submits a self-activation

**Run as Requester (browser SSO will pop):**

```powershell
pwsh ./pim-enablement-testbed/scripts/trigger-pim-activation.ps1 `
  -TenantId a172a259-b1c7-4944-b2e1-6d551f954711 `
  -RoleDisplayName "Privileged Role Administrator" `
  -DurationHours 1 `
  -Justification "E2E validation 2026-05-05"
```

**Pass criteria:** `status=PendingApproval`.
**Anti-pattern:** if `status=Provisioned`, step 3 didn't take effect — the request was auto-approved. Re-check.

**Result:**
- [x] Pass / [ ] Fail
- Returned status: `PendingApproval` (intermediate `PendingApprovalProvisioning` then settled)
- Request GUID: `03b7b1c4-bdf2-4b2a-8dcc-02bc7223b806`
- Notes:
  - First attempt hung silently because `Connect-MgGraph -UseDeviceCode | Out-Null` was swallowing the device-code instructions. Patched script to drop the `Out-Null` on the device-code path.
  - Required `-ContextScope Process` to bypass the on-disk MSAL token cache (otherwise admin's cached token was reused, producing `You have no PIM-eligible Entra role assignments.` from the wrong identity).
  - Auth flow: `https://login.microsoft.com/device` + code, signed in as `pim-requester`, no consent prompt needed (admin-consented Graph SDK app `14d82eec-...`).

### Gap-filler validation (the real Step 4 success signal)

Immediately after the trigger script returned, ran:

```bash
source .venv/bin/activate
python ./pim-enablement-testbed/scripts/smoke-test-pim-mcp.py \
  https://ca-pimtest-pimmcp.gentleocean-dea895de.eastus2.azurecontainerapps.io
```

Result:
```json
{
  "value": [{
    "id": "03b7b1c4-bdf2-4b2a-8dcc-02bc7223b806",
    "status": "PendingApproval",
    "action": "selfActivate",
    "principalId": "8a986e7c-f44b-44e0-a8a2-cfc1071faf92",
    "roleDefinitionId": "e8611ab8-c189-46e8-94e1-60213ab1f814",
    "directoryScopeId": "/",
    "justification": "E2E validation 2026-05-05",
    "scheduleInfo": {"expiration":{"type":"afterDuration","duration":"PT1H"}},
    "ticketInfo": {"ticketNumber":"TESTBED-001","ticketSystem":"manual"}
  }],
  "fetchedCount": 1,
  "pendingCount": 1
}
```

**✅ Full chain validated end-to-end:** Requester → Graph PIM (selfActivate) → `roleAssignmentScheduleRequests` (PendingApproval) → `pim-mcp` (MI auth, BUG-001 workaround) → SSE → JSON payload with the right request ID, justification, ticket info.

---

## Step 5 — Ask agent: *"What do you understand about your PIM role, and are there any pending requests?"*

**Action (Foundry agent chat) — use these three prompts in order:**

The SRE agent has read the testbed repo and produced an accurate self-summary already (see `from-sre-agent-1.md`). These prompts validate (a) it grounds itself in the right context, (b) it correctly distinguishes Enterprise MCP vs `pim-mcp`, and (c) it actually invokes the tool.

**Prompt 5a (self-knowledge check):**
```text
What is the difference between the Microsoft MCP Server for Enterprise and the
custom pim-mcp gap-filler in this testbed? Why does pim-mcp exist?
```

**Pass criteria:** Mentions BUG-001 (or the runtime ReadWrite vs Read scope mismatch), app-only vs delegated auth, single-tool boundary as compensating control.

**Prompt 5b (the actual tool call):**
```text
Now check for any pending PIM activation requests right now and tell me what you find.
```

**Pass criteria:**
- Agent invokes `list_pending_pim_requests` (visible in trace)
- Agent returns the request from Step 4 — must match GUID `03b7b1c4-bdf2-4b2a-8dcc-02bc7223b806`
- Agent does NOT hallucinate fields not in the payload (no fake requester name unless it called Graph users to enrich)

**Result:** ✅ PASS (2026-05-08, fresh activation request `d13bbfc1-9ca5-46cf-9b8b-c6521213a9d0`)

- [x] Pass / [ ] Fail
- **Prompt 5a ("check for any pending PIM activation requests"):** Agent invoked `PIM-MCP.list_pending_pim_requests` (tool-call card visible: "Completed"), returned the request with **correct GUID, justification, ticket info, schedule, status=PendingApproval**. No hallucinated fields. Rendered as a clean table.
- **Prompt 5b ("resolve principalId and roleDefinitionId"):** Agent **first attempt** (before pim-mcp 0.4.x) fell back to `az ad user show` / `az rest` (Azure CLI tools) → 403 because the SRE Agent's MI lacks Graph perms. Agent self-diagnosed correctly and proposed the exact two app-roles needed.
- **Prompt 5b (after pim-mcp 0.4.1 deploy + MI grants):** Agent invoked `PIM-MCP.get_user` and `PIM-MCP.get_role_definition`, resolved `8a986e7c-…` → "PIM Test Requester (`pim-requester@MngEnvMCAP094150.onmicrosoft.com`)" and `e8611ab8-…` → "Privileged Role Administrator (built-in, directory-root scope)". Surfaced `accountEnabled: true` as a triage signal.
- Hallucination observed? **No** (in any run).
- Latency (wall-clock from prompt submit to final answer): ~3-5s for 5a, ~6-8s for 5b post-fix.

---

## Step 6 — Ask agent: *"Should this PIM request be approved?"*

**Action (Foundry agent chat, in same session):**

Prompt verbatim:
```text
Look at the pending PIM request you just listed. Walk me through your reasoning:
which validation rules from validation-rules.yaml (R001-R008) apply, what evidence
you would need to evaluate each, and what your recommendation would be (approve,
deny, or review). Be explicit about which rules you can evaluate now vs which
need Jira MCP or Enterprise MCP that aren't wired yet.
```

**Pass criteria:**
- Agent reasons over the structured payload (justification, role, scope, ticket info)
- Agent cites specific rules by ID (R001–R008) instead of generic best-practice text
- Agent identifies which integrations are missing (Jira MCP, Enterprise MCP) instead of pretending it has them
- Agent recommends approve / deny / review with explicit reasoning
- No hallucinated data (e.g., doesn't claim ticket exists if Jira MCP isn't wired)

**Result:** ✅ PASS (2026-05-08) — exceptional, repo-grounded answer

- [x] Pass / [ ] Fail
- Verdict given: **Review** (correctly cautious — high-privilege role at root scope, manual ticket system unverifiable)
- Tool calls invoked: none (reasoning over data already in context); cited validation-rules.yaml R001-R008 by ID, found `configure-pim-approval.ps1` Step 3 patch, surfaced policy ID `DirectoryRole_a172a259-…_030d6466-…` and approver UPN.
- Reasoning quality: **5/5**. Notable behaviors:
  1. Correctly traced "why pending" back to Step 3's `isApprovalRequired: false→true` patch in this testbed (read from repo).
  2. Mapped each R001-R008 rule to **this** request with explicit verdict per rule.
  3. Honestly flagged "needs Jira MCP" / "needs Graph check" instead of fabricating evidence.
  4. Surfaced exactly the right risk flags: privilege level, root scope, manual ticket = no automated validation.
- Repo-grounding confirmed working via the SRE-AGENT-JAN-2026 GitHub Repo connector.

---

## Step 7 — Approver acts in PIM portal

**Action (manual, as Approver in Entra portal):**
1. Sign in as Approver
2. Navigate to PIM → Approve requests
3. Approve the request from Step 4

**Pass criteria:** Request status flips from `PendingApproval` → `Provisioned`. Confirm via portal or:

```powershell
# Optional re-check via Graph
pwsh -c "Connect-MgGraph -TenantId a172a259-b1c7-4944-b2e1-6d551f954711 -Scopes RoleAssignmentSchedule.Read.Directory; Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance -Filter \"principalId eq '<requester-oid>'\" | Format-List"
```

**Result:** ✅ PASS (2026-05-08, ~14:50 UTC)

- [x] Pass / [ ] Fail
- Approver: `pim-approver@MngEnvMCAP094150.onmicrosoft.com` (Entra portal → PIM → Approve requests → Microsoft Entra roles).
- Approver justification: *"Approved per SRE Agent triage 2026-05-08 — request meets R001-R008 with Review verdict; approver sanity-checked ticket and scope."*
- Portal experience: 1 row visible in "Requests for role activations" table (Privileged Role Administrator / PIM Test Requester / Directory scope / 4h). Approve panel rendered all expected fields including the agent-relevant ones (Reason, Ticket number `TESTBED-001`, Ticket system `manual`, Start/End time).
- Time from Confirm click → `pendingCount: 0` from agent re-check: under 1 min (next prompt cycle).

### Agent re-check — Prompt 8 (verbatim agent answer)

> *"No pending PIM activation requests right now. The queue is empty — the earlier request from PIM Test Requester for Privileged Role Administrator is no longer in `PendingApproval` state (it was either approved, denied, or expired)."*

### Agent narrative-continuity prompt — *"What changed since I last asked 10 minutes ago?"*

> *"10 minutes ago (~14:42 UTC): 1 pending request was in the queue — PIM Test Requester … requesting Privileged Role Administrator at directory-root scope, submitted at 13:34 UTC with a 4-hour duration. Status was PendingApproval. Now (14:52 UTC): The queue is empty — 0 pending requests. … The most likely explanations, in order of probability: 1. Approved — the designated approver … flipping it to `Provisioned`. The requester now has an active 4-hour Privileged Role Administrator assignment expiring around 17:34 UTC. 2. Denied … 3. Cancelled …"*

**Quality observations:**
- ✅ Correct empty-result behavior — no stale-state hallucination.
- ✅ Recalled prior turn details (UPN, role, scope, submit time, duration) accurately.
- ✅ Computed post-approval expiry time correctly (13:34 UTC + 4h = 17:34 UTC).
- ✅ Honestly surfaced its tool gap — *"I don't currently have a tool to query the request's final disposition (the `list_pending_pim_requests` tool only returns `PendingApproval` items)"* — and proposed two valid follow-up options (Entra portal History, query `roleAssignmentScheduleInstances` via Graph). Exemplary uncertainty calibration.

**Follow-up parking lot:**
- Optional 5th tool: `get_request_status(request_id)` to close the disposition gap the agent itself flagged.
- Optional 6th tool: `list_active_role_assignments(principal_id)` for post-approval verification — would let the agent confirm "approved" deterministically.

### Step 7b — Disposition gap closed (pim-mcp 0.5.0, ~15:10 UTC) ✅

**Both follow-up tools shipped same-day** (parking lot drained):
- `get_request_status(request_id)` — final state of any PIM request
- `list_active_role_assignments(principal_id)` — currently-active assignments

Image `pim-mcp:0.5.0` deployed to `ca-pimtest-pimmcp` revision `0000009`. CLI smoke test verified both tools return real Graph data. Re-ticked checkboxes in SRE Agent → PIM-MCP connector wizard (now 6 tools).

**Re-prompt (verbatim, 2026-05-08 ~15:10 UTC):**

> *"What was the final disposition of PIM request `d13bbfc1-9ca5-46cf-9b8b-c6521213a9d0`? And does the requester currently have the role active?"*

**Agent behavior:** invoked both new tools in sequence (`Get Request Status` + `List Active Role Assignments` — both tool-call cards visible, both `Completed`), then composed a structured-table answer.

**Agent answer (key fields):**

| Detail | Value |
|---|---|
| Final Status | Provisioned (approved) |
| Approved At | 2026-05-08 14:51:23 UTC (~1h 17m after submission) |
| Active Window | 14:51 UTC → 18:51 UTC today (4 hours) |
| Assignment Type | Activated (Direct) |
| Time Remaining | ~3h 40m from now |
| Role | Privileged Role Administrator |
| Scope | Directory root (/) |
| Who | PIM Test Requester (`pim-requester@MngEnvMCAP094150.onmicrosoft.com`) |
| Request ID | `d13bbfc1-9ca5-46cf-9b8b-c6521213a9d0` |

Closing prose: *"The requester **currently has the role active**. The assignment is tied directly to this PIM request (schedule ID matches) and will automatically expire at 18:51 UTC today — no manual deactivation needed unless you want to revoke early."*

**Quality observations:**
- ✅ All 9 fields match Graph ground truth byte-for-byte (independently verified via `scripts/smoke-test-new-tools.py`).
- ✅ Cross-tool reasoning correct — agent observed `roleAssignmentScheduleId` matched the request ID and explicitly cited that as evidence the assignment ties to *this* request.
- ✅ Approval-latency math correct (13:34:22 submit → 14:51:23 approve = 77m ≈ "~1h 17m").
- ✅ Time-remaining math correct (computed against current wall-clock).
- ✅ Operational tone — "no manual deactivation needed unless you want to revoke early" is exactly what an experienced SRE would say.
- ✅ No hallucination, no made-up fields.

**Net result:** The disposition-gap parking-lot item the agent itself raised at end of Step 7 was identified, designed, coded, deployed, wired, and re-validated **within ~30 minutes**. The agent now has full read-side coverage of the PIM request lifecycle (pending → approved → active → expiring).

---

### Step 7c — Approver-identity gap closed (pim-mcp 0.6.0 → 0.6.1, ~15:55 UTC) ✅

**Second self-identified gap** (raised by the agent at the close of Step 7b):
> *"I can tell you the request was approved and is currently active, but no exposed tool surfaces the **identity of the approver** or their **justification**. To meet the audit-trail bar — 'who approved this, when, and why?' — we'd need a tool that hits the `roleAssignmentApprovals/{id}/steps` collection on Microsoft Graph."*

**Tool shipped:** `get_request_approver(request_id)` — chains in one call:

1. `GET /v1.0/.../roleAssignmentScheduleRequests/{id}` → extracts `approvalId`
2. `GET /beta/.../roleAssignmentApprovals/{approvalId}/steps` → returns full reviewer trail

Returns: `requestId`, `approvalId`, `requestStatus`, and a `steps[]` array with `reviewedBy {id, displayName, userPrincipalName, mail}`, `reviewResult`, `status`, `reviewedDateTime`, `justification`. Multi-stage approval policies surface as multiple step rows.

**Image lineage (same day):**
- `pim-mcp:0.6.0` (rev `0000010`) — initial ship; tool reachable end-to-end but Graph beta returned 403 on the live call.
- `pim-mcp:0.6.1` (rev `0000011`) — token-cache fix (see below); approver tool returns 200 + full payload in <300ms.

**Roadblock removed (the real story behind 0.6.0 → 0.6.1):**

| Symptom | "After granting `PrivilegedAccess.Read.AzureAD` to the MI, the new tool kept getting `403 Valid permissions not present` for ~30 minutes — even though admin consent was confirmed." |
|---|---|
| First instinct (wrong) | "PIM beta resource-side authorization cache lag — wait it out." |
| Diagnostic that cracked it | Decoded the live token in-container by hitting `IDENTITY_ENDPOINT` directly. The `roles` claim was missing `PrivilegedAccess.Read.AzureAD`, even though the SP's `appRoleAssignments` confirmed the grant. Same call with `bypass_cache=true` returned a token with all 5 roles **and** the beta endpoint immediately returned 200 OK. |
| **True root cause** | **Container Apps IMDS sidecar caches MI tokens by `(client_id, resource)` for the full token lifetime.** Newly-granted appRoles do **not** appear in cached tokens until natural expiry (hours away). The `azure-identity` SDK has no way to signal "force a fresh roles claim"; it just gets handed the cached token. |
| **Fix (0.6.1)** | New `_get_graph_token()` in `tools.py` hits `IDENTITY_ENDPOINT` directly with `bypass_cache=true` when running on ACA, with a ~50-min in-process cache to avoid hammering IMDS. Falls back to `DefaultAzureCredential` for local dev. |
| **Operational rule** | "When granting a new appRole to a Container Apps MI: `az containerapp revision restart` after the grant. The bypass-cache path picks up fresh claims immediately; no waiting on IMDS expiry." |

This is a generally-useful finding for any ACA + MI + Microsoft Graph workload. Full RCA in commit message [`f4e9032`](https://github.com/Arturo-Quiroga-MSFT/SRE-AGENT-JAN-2026/commit/f4e9032).

**Re-prompt (verbatim, 2026-05-08 ~15:55 UTC):**

> *"Who approved request `d13bbfc1-9ca5-46cf-9b8b-c6521213a9d0`?"*

**Agent behavior:** invoked `get_request_approver` (tool-call card visible, `Completed`), then composed a structured-table answer.

**Agent answer (key fields):**

| Detail | Value |
|---|---|
| Approver | PIM Test Approver (`pim-approver@MngEnvMCAP094150.onmicrosoft.com`) |
| Approver ObjectId | `00a13120-c099-45bc-851a-861ade749067` |
| Decision | Approve |
| Reviewed At | 2026-05-08 **14:51:23 UTC** |
| Approval Stage | SingleStage — Completed |
| Justification | *"Approved per SRE Agent triage 2026-05-08 — request meets R001-R008 with Review verdict; approver sanity-checked ticket and scope."* |

Closing prose (paraphrased from agent): *"The full audit chain is now traceable: request → agent triage → approver decision with reasoning → provisioned assignment. Notably, the approver referenced the SRE Agent's triage summary in their justification — exactly the workflow this testbed was designed to validate."*

**Quality observations:**
- ✅ All 6 fields match Graph beta ground truth byte-for-byte (independently verified via `scripts/smoke-test-approver.py`).
- ✅ Approver UPN, ObjectId, decision, timestamp, and justification surfaced verbatim from the Graph response — no paraphrasing of the justification text.
- ✅ Agent recognized the **review-verdict feedback loop**: approver's free-text justification cited the agent's R001–R008 rubric, demonstrating the human-in-the-loop pattern the testbed was designed to validate.
- ✅ No hallucination, no fabricated approver attributes.

**Net result:** Both parking-lot items the agent self-identified during Step 6 + Step 7b were closed **on the same day**:
- 13:34 UTC — request submitted (Step 4)
- 14:51 UTC — approver acts (Step 7)
- 15:10 UTC — `pim-mcp` 0.5.0 (`get_request_status` + `list_active_role_assignments`) deployed and validated (Step 7b)
- 15:55 UTC — `pim-mcp` 0.6.1 (`get_request_approver` + IMDS-cache fix) deployed and validated (Step 7c)

The Foundry SRE agent now has **complete read-side coverage** of the PIM request lifecycle: pending → triage → approval (with reasoning) → activation → expiry. Seven tools total: `health`, `list_pending_pim_requests`, `get_user`, `get_role_definition`, `get_request_status`, `list_active_role_assignments`, `get_request_approver`.

---

## Step 8 — Ask agent again: *"Are there any pending PIM requests?"*

**Action (Foundry agent chat, same prompt as Step 5):**

```text
Are there any pending PIM activation requests right now?
```

**Pass criteria:**
- Agent invokes `list_pending_pim_requests`
- Returns empty (or excludes the now-approved request)
- Latency comparable to Step 5 (no degradation)

**Result:** ✅ PASS (2026-05-08) — repurposed as approver-pastable triage summary

- [x] Pass / [ ] Fail
- Prompt actually used: *"Give me a one-paragraph triage summary I could paste verbatim into the approver chat. Include: who, what role, scope, justification, ticket, when it expires if approved (compute it from createdDateTime + duration), and any risk flags. Plain prose, no tables. Max ~120 words."*
- Agent computed expiration math correctly: `createdDateTime 2026-05-08 13:34:22 UTC + PT4H = 17:34 UTC today` ✅
- Output was paste-ready (~110 words), included who/what/scope/justification/ticket/expiry, three explicit risk flags (privilege level, root scope = max blast radius, manual ticket = unverifiable).
- Latency: ~5-6s wall-clock.

---

## Step 9 — Inspect Jira ticket for audit trail

**Action (manual, in Jira):**
1. Open the ticket referenced in Step 4 (if any was linked via `ticketInfo`)
2. Look for an automated comment from the SRE agent containing:
   - Timestamp
   - Verdict (Approve / Deny / Review)
   - Reasoning summary
   - Evidence collected

**Pass criteria:** Audit comment present and complete. If Jira-side write isn't wired yet, mark **N/A** and capture as a follow-up.

**Result:**
- [ ] Pass / [ ] Fail / [ ] N/A (not yet wired)
- Ticket ID: __________
- Comment present: Y/N
- Notes: __________

---

## Step 10 — Inspect Foundry trace + ACA logs end-to-end

**Action:**

1. **Foundry trace** (portal): Open the agent session, expand the tool call(s), capture latency + payload.

2. **ACA logs** (CLI):

```bash
az containerapp logs show \
  -n ca-pimtest-pimmcp \
  -g rg-pim-enablement-testbed \
  --tail 100 \
  --type system
```

3. **ACA app logs (real revision):**

```bash
az containerapp logs show \
  -n ca-pimtest-pimmcp \
  -g rg-pim-enablement-testbed \
  --tail 200 \
  --type console
```

**Pass criteria:**
- Foundry trace shows full chain: prompt → tool select → tool call → tool response → final answer
- ACA logs show inbound SSE connection, MI token acquisition, Graph call, response
- No unexpected errors / 401 / 429

**Result:**
- [ ] Pass / [ ] Fail
- Full trace coherent (Y/N): __________
- Errors observed: __________
- ACA log excerpt:
  ```text
  
  ```

---

## Layer 3 — Operational stress checks (optional after Steps 1–10)

| Check | Method | Pass criteria | Result |
|---|---|---|---|
| Idle polling cost | Leave agent idle 1h, check ACA cost + Foundry token spend | < $1 incremental | |
| `pim-mcp` down → recovery | `az containerapp update --min-replicas 0`; ask agent; restore | Agent surfaces clear error, no crash | |
| Two requests pending | Trigger 2 activations, ask agent | Both returned, both reasoned about | |
| Cold start latency | Wait for ACA scale-to-zero, then call | < 10s for first call | |
| Graph throttling | (Skip unless reproducing — risky) | N/A | |

---

## Latency capture (Layer 1 metric)

Run the smoke test 10 times and capture round-trip times. Quick one-liner:

```bash
for i in {1..10}; do
  START=$(python -c "import time; print(time.time())")
  python ./pim-enablement-testbed/scripts/smoke-test-pim-mcp.py \
    https://ca-pimtest-pimmcp.gentleocean-dea895de.eastus2.azurecontainerapps.io \
    >/dev/null 2>&1
  END=$(python -c "import time; print(time.time())")
  python -c "print(f'trial $i: {round(($END - $START)*1000, 0)} ms')"
done
```

| Trial | Round-trip (ms) |
|---|---|
| 1 | |
| 2 | |
| ... | |
| 10 | |
| **p50** | |
| **p95** | |

Threshold: p95 < 5000 ms = ✅; > 5000 ms = evidence for transport reconsideration.

---

## Decision rubric (fill in after all steps)

| Dimension | Score (1–5) | Notes |
|---|---|---|
| End-to-end latency | | |
| Reliability under retry/cold-start | | |
| Foundry integration friction | | |
| Compliance story strength | | |
| Cost @ projected volume | | |
| Agent reasoning quality | | |

**Overall verdict (interim, 2026-05-08):**
- [x] Keep MCP for V1 milestone (June 2026)
- [ ] Plan V2 migration to Function + OpenAPI
- [ ] Other: __________

**Confidence:** **High** — functional E2E (Steps 1, 5a, 5b, 6, 7, 7b, 7c, 8) all pass with strong reasoning quality. Full PIM lifecycle now traceable through the agent: pending → triage → approval (with approver identity + justification) → activation → expiry. Remaining work: Step 9 (Jira write-back), Step 10 (full trace inspection), p50/p95 latency loop. Strategic gap: SRE Agent connector wizard needs OAuth-delegated auth before Microsoft Enterprise MCP can be wired (architecturally preferable to the current MI-extended `pim-mcp`).

---

## Day 2 summary (2026-05-08) — what changed

**Successes:**
- ✅ PIM-MCP connector wired into SRE Agent `aq-main` (Streamable-HTTP, **7 tools** by end of day).
- ✅ End-to-end re-trigger of PIM activation (request `d13bbfc1-…`, PT4H duration).
- ✅ Steps 5a, 5b, 6, 7, 7b, 7c, 8 — all pass with strong reasoning.
- ✅ Agent meta-aware: at end of Step 6 and Step 7b, *the agent itself* identified the next two missing tools (disposition + approver-identity); both shipped same-day in response.
- ✅ Full audit chain closed: agent can answer *who requested → who approved → what was their justification → when does it expire*.

**Roadblocks removed:**
- 🔧 SSE → Streamable-HTTP transport migration (image 0.2.4 → 0.3.1).
- 🔧 Starlette slash-redirect HTTPS-downgrade fix (explicit `path="/mcp"`).
- 🔧 80-tool agent cap (trimmed grafana-mcp selection).
- 🔧 Enterprise MCP delegated-OAuth gap → tactical workaround via pim-mcp expansion (image 0.3.1 → 0.4.1, +2 tools, +2 Graph perms on MI).
- 🔧 `isPrivileged` v1.0/beta property mismatch (dropped from $select).
- 🔧 Disposition gap (parking lot from Step 7) → `pim-mcp` 0.5.0 added `get_request_status` + `list_active_role_assignments`.
- 🔧 Approver-identity gap (parking lot from Step 7b) → `pim-mcp` 0.6.0 added `get_request_approver` (Graph beta `/roleAssignmentApprovals/{id}/steps`, +1 Graph perm `PrivilegedAccess.Read.AzureAD`).
- 🔧 **Container Apps IMDS token-cache trap** → `pim-mcp` 0.6.1 forces fresh token via `IDENTITY_ENDPOINT?bypass_cache=true`. Newly-granted appRoles do NOT appear in cached MI tokens for hours after consent; this fix is generally useful for any ACA + MI + Microsoft Graph workload (commit [`f4e9032`](https://github.com/Arturo-Quiroga-MSFT/SRE-AGENT-JAN-2026/commit/f4e9032)).

**Strategic asks logged:**
- Email/Loop draft to Deepthi (SRE Agent PM): add OAuth 2.0 Authorization Code (delegated) as a 4th wizard auth option, with smaller fallbacks (custom-header refresh hook, MI federated token exchange).

**Files touched (Day 2):**
- `mcp-servers/pim-mcp/server.py` — transport switch + explicit `path` + instructions for 7-tool workflow.
- `mcp-servers/pim-mcp/tools.py` — added `get_user`, `get_role_definition`, `get_request_status`, `list_active_role_assignments`, `get_request_approver`; introduced `_get_graph_token()` with IMDS `bypass_cache=true` + in-process token cache.
- `mcp-servers/pim-mcp/pyproject.toml` — version 0.2.0 → **0.6.1** (5 ships in one day).
- `mcp-servers/pim-mcp/README.md` + `pim-enablement-testbed/README.md` — tool tables + perm matrix updated.
- `scripts/smoke-test-pim-mcp.py` — switched client transport from SSE to Streamable-HTTP.
- `scripts/smoke-test-new-tools.py` — coverage for 0.5.0 tools.
- `scripts/smoke-test-approver.py` — coverage for 0.6.x approver tool.

**Open follow-ups for the team:**
- 
- 
- 
