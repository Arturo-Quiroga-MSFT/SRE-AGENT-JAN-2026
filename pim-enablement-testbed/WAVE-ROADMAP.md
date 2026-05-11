# PIM Recommender — Wave Roadmap (Closing the Zafin Gaps)

> **Created:** 2026-05-11
> **Author:** Arturo Quiroga, PSA
> **Source:** Gap analysis against [Zafin's Deterministic Rule Pack](../partner-context/ZAFIN_PIM_APPROVER_AGENT_RULE_PACK_MAY2026.md), specifically Sections 20 (Final Operating Model) and 21 (Summary posture).
> **Current testbed implementation:** R001–R008 in [`agent/validation-rules.yaml`](agent/validation-rules.yaml). Custom agent config in [`PIM-RECOMMENDER-AGENT-CONFIG.md`](PIM-RECOMMENDER-AGENT-CONFIG.md).

This document is the running plan for closing the deltas between our current `pim-recommender` testbed and Zafin's deterministic rule pack. Each wave will be developed on its own branch and merged back to `main` once smoke-tested end-to-end.

---

## Gap analysis — Section 20 (Final Operating Model)

| # | Zafin step | Testbed status | Gap |
|---|---|---|---|
| 1 | Read PIM request | ✅ `list_pending_pim_requests` | — |
| 2 | Extract role/scope/duration/justification/ticket | ✅ Agent does this | — |
| 3 | Validate ticket in Jira | 🟡 Agent calls `jira_search` but `validation-rules.yaml` R001 predicate not wired to inspect state/type/freshness | **Gap 1** |
| 4 | Validate requester relationship to ticket | ❌ R003 always SKIPs (blocked by R001 terminal flag) | **Gap 2** |
| 5 | Validate requester group/team authorization | ✅ R004 — live PASS via `get_user_group_memberships` | — |
| 6 | Validate role against Role Allowlist | 🟡 R005 wired but allowlist contains `PLACEHOLDER` values | **Gap 3** |
| 7 | Validate scope against Scope Catalog | 🟡 R006 wired but contains `PLACEHOLDER-sub-id` | **Gap 3** |
| 8 | Validate duration using **strictest** limit | 🟡 R007 checks one cap; not `min(role, scope, ticket-type, change-window)` | **Gap 4** |
| 9 | Validate MFA, account status, risk signals | ❌ Not implemented | **Gap 5** |
| 10 | Check SoD conflicts | ❌ Not implemented | **Gap 6** |
| 11 | Check high-risk role / prod/client ambiguity / break-glass | ❌ Not implemented (R005 just FAILs high-risk; doesn't route to Human Review) | **Gap 7** |
| 12 | Generate Approve / Reject / Human Review | ❌ Emits `ELIGIBLE / NOT ELIGIBLE / REVIEW MANUALLY` (wrong vocabulary) | **Gap 8** |
| 13 | Send Teams card with PIM deep link | 🟡 Email works; Teams cross-tenant blocked in PoC tenant | **Gap 9** |
| 14 | Optional: requester notification on rejection | ❌ Not implemented | **Gap 10** |
| 15 | Store full audit record | ✅ Jira ticket + comment + remote link | — |
| 16 | Capture human approver final decision | ❌ Agent ends after recommendation | **Gap 11** |

## Gap analysis — Section 21 (Summary posture)

| Posture statement | Status |
|---|---|
| Explicitly authorized | 🟡 Need real allowlists (Gap 3) |
| Linked to valid business ticket | 🟡 Need wired ticket validation (Gap 1) |
| Bound to requester role and team | ✅ R004 + R005 |
| Limited to minimum necessary scope | 🟡 R006 placeholder; no scope-minimization (PIM-024) |
| Limited to minimum necessary duration | 🟡 Single-cap; need `min()` (Gap 4) |
| Protected by MFA and Conditional Access | ❌ (Gap 5) |
| Reviewed for SoD conflicts | ❌ (Gap 6) |
| Escalated when high-risk, ambiguous, exceptional | ❌ All FAILs today; no Human-Review routing (Gap 7) |
| Fully auditable | ✅ Jira + email trail |

**Critical default-posture mismatch:** today our agent emits `NOT ELIGIBLE / Deny` for Privileged Role Administrator. Zafin's posture (section 21) requires `Human Review Needed` for high-risk roles. This is the highest-leverage single fix and is the headline target of Wave A.

---

## Wave plan

Each wave gets its own branch (`wave-a-vocab-routing`, `wave-b-ticket-validation`, etc.), is smoke-tested via the scheduled task, and is merged back to `main` only after a fully-green run.

### Wave A — Vocabulary + Human-Review routing  *(branch: `wave-a-vocab-routing`)*

**Effort:** 2–3 hours. **New tools required:** none. **Highest ROI.**

**Closes:** Gaps 7, 8.

**Tasks:**

1. Rewrite verdict vocabulary in `PIM-RECOMMENDER-INSTRUCTIONS.md`:
   - `ELIGIBLE` → `Approve`
   - `NOT ELIGIBLE` → `Reject with Remarks`
   - `REVIEW MANUALLY` → `Human Review Needed`
2. Extend `agent/validation-rules.yaml` schema — add per-rule `decision_on_fail: Reject | HumanReview` field. Backfill existing R001–R008 with appropriate decisions per Zafin section 6.
3. Add new predicates from Zafin's high-risk catalog (Table 4):
   - `role_in_high_risk_catalog` — fires `decision_on_fail: HumanReview` for Owner, User Access Administrator, Global Administrator, Privileged Role Administrator, Conditional Access Administrator, Security Administrator, Key Vault Administrator, Billing Administrator, Compliance Administrator.
4. Add new predicates for sensitive scope (PIM-026, PIM-027):
   - `scope_is_tenant_root` — `decision_on_fail: HumanReview`
   - `scope_is_management_group` — `decision_on_fail: HumanReview`
5. Update Instructions verdict-computation logic:
   - **Any** rule firing `HumanReview` → final verdict `Human Review Needed` (trumps Reject).
   - **Any** rule firing `Reject` with no HumanReview → `Reject with Remarks`.
   - All pass → `Approve`.
6. Update Adaptive Card payload + email subject template to use the three Zafin labels.
7. Smoke-test: trigger a fresh `Privileged Role Administrator` request and confirm verdict is now `Human Review Needed`, not `NOT ELIGIBLE`.

**Acceptance criteria:**

- Scheduled-task run for Privileged Role Administrator emits `Human Review Needed`.
- Jira audit ticket and Outlook email both use Zafin's three-decision vocabulary.
- No new tools added; no new MCP calls.

---

### Wave B — Real ticket validation  *(branch: `wave-b-ticket-validation`)*

**Effort:** half day. **New tools required:** none (`jira_get_issue` already attached).

**Closes:** Gaps 1, 2.

**Tasks:**

1. Add predicates to `validation-rules.yaml` for PIM-005 through PIM-013:
   - `ticket_id_required` (Reject)
   - `ticket_exists_in_jira` (Reject) — wire to `jira_search`
   - `ticket_status_active` (Reject if status ∈ {Done, Closed, Cancelled, Rejected, Duplicate})
   - `ticket_type_valid` (HumanReview if not in {Incident, Change, SR, Deployment, Problem, Security Exception})
   - `ticket_age_within_window` (HumanReview) — per-ticket-type thresholds from Zafin Table 3
   - `requester_linked_to_ticket` (Reject if requester ∉ {reporter, assignee, team members})
2. Remove the "R001 terminal blocks R002/R003" pattern from Instructions — each ticket-related predicate runs independently.
3. Smoke-test: open a real Jira ticket for the requester, trigger a request citing it, verify Approve-path predicates fire.

**Acceptance criteria:**

- Closed/missing tickets produce specific `Reject` reasons cited verbatim in the audit ticket.
- Stale or non-standard ticket types produce `Human Review Needed`, not `Reject`.
- Approve-path becomes reachable for a properly-formed request (still gated by Wave C's real allowlist).

---

### Wave C — Real allowlists + duration `min()`  *(branch: `wave-c-allowlists-duration`)*

**Effort:** half day. **Dependency:** Zafin provides real Table 1 + Table 2 values for their tenant.

**Closes:** Gaps 3, 4.

**Tasks:**

1. **Request from Zafin** (blocker — send before starting):
   - Real Table 1 (Role Allowlist) populated with their team↔role↔scope↔duration mappings.
   - Real Table 2 (Scope Catalog) with their subscription IDs, environments, authorized teams, durations.
2. Replace all `PLACEHOLDER` rows in `agent/validation-rules.yaml`.
3. Implement `allowed_duration = min(role_max, scope_max, ticket_type_max, change_window)` per Zafin section 7.1.
   - May require splitting R007 into DUR-001 through DUR-006.
   - Encode the duration matrix from Zafin section 7.3 as a YAML lookup.
4. Smoke-test: trigger requests at various scope/role/duration combinations and verify the strictest limit always wins.

**Acceptance criteria:**

- No `PLACEHOLDER` strings remain in `validation-rules.yaml`.
- A request that's within role max but exceeds scope max produces `Reject with Remarks` citing the scope limit.
- Approve-path reachable end-to-end for a compliant request (Wave B + Wave C combined).

---

### Wave D — Observability gaps  *(branch: `wave-d-observability`, deferred)*

**Effort:** multi-day. **Dependency:** new tools required.

**Closes:** Gaps 5, 6, 10, 11.

**Tasks (require new `pim-mcp` tools):**

1. **MFA / Conditional Access state** (PIM-016 family):
   - New tool: `pim-mcp_check_user_mfa_status` — Graph `signInActivity` + `conditionalAccessPolicies` reads.
2. **SoD conflict scan** (PIM-033 to PIM-036):
   - New tool: `pim-mcp_detect_sod_conflict` — Graph group/role overlap reader.
3. **Capture human decision** (step 16):
   - Watcher pattern in agent: re-call `get_request_status` for evaluated requests until terminal.
4. **Requester rejection notification** (step 14):
   - Additional `SendOutlookEmail` call gated on `decision == Reject`.

**Not started until:** Wave A is shipping value and Zafin has signed off on Wave A/B/C output format.

---

## Branch / merge protocol

1. Create wave branch from `main`: `git checkout -b wave-<letter>-<short-name>`.
2. Implement and smoke-test on the branch.
3. Capture the smoke-test run in `SRE-AGENT-CHATS/<NN>.md` formatted to match siblings.
4. Open a PR (or fast-forward merge for solo work) only after a green run is captured.
5. After merge, delete the wave branch.
6. Roadmap entry above gets a ✅ status update and link to the merging chat-log file.

---

## Status

| Wave | Branch | Status | Merge commit | Smoke-test log |
|---|---|---|---|---|
| A | `wave-a-vocab-routing` | 🚧 in progress | — | — |
| B | `wave-b-ticket-validation` | ⏸ not started | — | — |
| C | `wave-c-allowlists-duration` | ⏸ blocked on Zafin Table 1/2 | — | — |
| D | `wave-d-observability` | ⏸ deferred | — | — |
