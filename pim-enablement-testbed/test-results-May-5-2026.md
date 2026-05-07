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
| `pim-mcp` image | `0.2.4` |
| SSE path | `/sse` |
| Foundry SRE agent | TBD — record agent name + project here once wired |
| Test role | `Privileged Role Administrator` (or substitute) |
| Operator UPN | `arturoqu@MngEnvMCAP094150.onmicrosoft.com` (admin) |
| Requester UPN | `pim-requester@MngEnvMCAP094150.onmicrosoft.com` |
| Requester ObjectId | `8a986e7c-f44b-44e0-a8a2-cfc1071faf92` |
| Approver UPN | `pim-approver@MngEnvMCAP094150.onmicrosoft.com` |
| Approver ObjectId | `00a13120-c099-45bc-851a-861ade749067` |
| Initial password (both) | `TestP@ssw0rd!2026` (force-change on first sign-in) |

## Pre-flight (Layer 1 baseline) — ✅ PASS (2026-05-05)

```text
==> https://ca-pimtest-pimmcp.gentleocean-dea895de.eastus2.azurecontainerapps.io/sse
Tools discovered:
  - list_pending_pim_requests
  - health
health() → {"status":"ok"}
list_pending_pim_requests(top=5) → {"value":[], "fetchedCount":0, "pendingCount":0}
```

Smoke test from CLI succeeded. Gap-filler is healthy, no pending requests at start of run.

---

## Step 1 — Wire `pim-mcp` into the SRE agent in Foundry

**Action (manual, in Foundry portal):**
1. Open the SRE agent project in Microsoft Foundry
2. Add a new tool of type **MCP** (or **Custom MCP server**)
3. Endpoint URL: `https://ca-pimtest-pimmcp.gentleocean-dea895de.eastus2.azurecontainerapps.io/sse`
4. Auth: none (server is currently anonymous-ingress; MI is server-side only)
5. Save and confirm tool list shows `list_pending_pim_requests` and `health`

**Pass criteria:** Tool discovered in Foundry portal; visible in agent's tool list.

**Result:**
- [ ] Pass / [ ] Fail
- Setup time (clock): __________
- Friction notes: __________
- Screenshot path: __________

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

**Result:**
- [ ] Pass / [ ] Fail
- Tool call latency (from Foundry trace): __________ ms
- Self-knowledge prompt (5a) accurate? Y/N: __________
- Tool call prompt (5b) returned correct GUID? Y/N: __________
- Hallucination observed? Y/N: __________
- Agent response (paste excerpt):
  ```text
  
  ```

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

**Result:**
- [ ] Pass / [ ] Fail
- Verdict given: Approve / Deny / Review
- Tool calls invoked (list): __________
- Reasoning quality (1–5): __________
- Agent response (paste excerpt):
  ```text
  
  ```

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

**Result:**
- [ ] Pass / [ ] Fail
- Time approver took: __________
- Time from approval → status flip: __________
- Notes: __________

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

**Result:**
- [ ] Pass / [ ] Fail
- Returned count: __________
- Latency: __________ ms
- Notes: __________

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

**Overall verdict:**
- [ ] Keep MCP for V1 milestone (June 2026)
- [ ] Plan V2 migration to Function + OpenAPI
- [ ] Other: __________

**Confidence:** Low / Medium / High

**Open follow-ups for the team:**
- 
- 
- 
