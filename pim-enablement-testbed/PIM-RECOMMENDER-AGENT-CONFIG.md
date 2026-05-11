# `pim-recommender` Custom Agent — Configuration Reference

Captures every setting needed to recreate the `pim-recommender` custom agent in the **Azure SRE Agent** UI. This is the source of truth for the agent that automates Option A (scheduled-tick PIM evaluation).

**Last verified:** 2026-05-11 (run `6ef1864a` — first fully-green end-to-end execution, see [`SRE-AGENT-CHATS/13.md`](SRE-AGENT-CHATS/13.md))

---

## 1. Agent identity

| Field | Value |
|---|---|
| Name | `pim-recommender` |
| Type | Custom agent |
| Mode | Review (human-in-the-loop; agent recommends, never approves) |
| Description | Read-only advisory agent that evaluates pending Microsoft Entra PIM activation requests against R001–R008 and produces PASS/FAIL/REVIEW verdicts for a human approver. |
| Instructions source | [`PIM-RECOMMENDER-INSTRUCTIONS.md`](PIM-RECOMMENDER-INSTRUCTIONS.md) — copy verbatim into the Instructions field. |

---

## 2. Tools (Choose tools panel)

**Final attached surface: 16 tools** — 10 PIM-MCP + 5 jira-mcp + 1 Outlook. Visualization (`Plot*`) and all default jira-mcp write/read tools outside the audit workflow have been removed to enforce least-privilege and prevent the agent from improvising side-quest tool calls.

### 2.1 `PIM-MCP` (10 tools — all checked)

Custom MCP server. Streamable-HTTP endpoint.

| Setting | Value |
|---|---|
| Server name (in UI) | `PIM-MCP` |
| Transport | Streamable-HTTP |
| Endpoint | `https://ca-pimtest-pimmcp.gentleocean-dea895de.eastus2.azurecontainerapps.io/mcp` |
| Auth | App-only (Managed Identity `mi-pimtest-agent`, principal `09883cfe-54ce-44d5-889e-7b47ec8e43c8`) |
| Image | `aqr2d2acr001.azurecr.io/pim-mcp:0.9.0` |
| Hosting | Container App `ca-pimtest-pimmcp` revision `0000014` in `rg-pim-enablement-testbed` |

**Tools attached (all 10 — verified 2026-05-11):**

1. `PIM-MCP_list_pending_pim_requests` — queue discovery (called first every run)
2. `PIM-MCP_get_user` — resolve requester from `principalId`
3. `PIM-MCP_get_role_definition` — resolve role from `roleDefinitionId`
4. `PIM-MCP_get_user_group_memberships` — **R004** transitive group check *(pim-mcp 0.9.0)*
5. `PIM-MCP_list_active_role_assignments` — posture check, cross-reference for R008
6. `PIM-MCP_list_eligible_role_assignments` — eligibility surface (informational; not used by R001–R008 yet)
7. `PIM-MCP_list_pim_request_history` — **R008** activation-frequency (`window_hours=24`)
8. `PIM-MCP_get_request_approver` — approval-status audit trail
9. `PIM-MCP_get_request_status` — final disposition for non-pending requests
10. `PIM-MCP_health` — readiness probe (rarely called by agent; useful for manual debugging)

### 2.2 `jira-mcp` (5 tools attached — verified 2026-05-11)

Jira Cloud MCP connector. Surface trimmed from ~50 default tools to the minimum required by R001 and the audit workflow.

| Setting | Value |
|---|---|
| Jira site | `https://aq-r2d2.atlassian.net` |
| Project | `SCRUM` |

**Tools attached (exactly these 5):**

1. `jira-mcp_jira_search` — **R001** ticket-existence lookup (JQL search by key or title)
2. `jira-mcp_jira_get_issue` — optional ticket-detail reader (used for R002/R003 state/assignee checks once wired)
3. `jira-mcp_jira_create_issue` — creates the audit ticket (one per evaluated request)
4. `jira-mcp_jira_add_comment` — appends the full validation checklist
5. `jira-mcp_jira_create_remote_issue_link` — PIM portal back-reference on the audit ticket

**Explicitly excluded (do not re-add):**

- `jira-mcp_jira_create_issue_link` — link types vary by project; "Relates to" not configured in SCRUM and Instructions forbid this call.
- `jira-mcp_jira_update_*`, `jira-mcp_jira_transition_*`, `jira-mcp_jira_delete_*`, `jira-mcp_jira_create_sprint`, `jira-mcp_jira_add_watcher`, `jira-mcp_jira_link_to_epic`, etc. — all write verbs outside the Instructions allowlist.
- All other read tools (`jira_get_all_projects`, `jira_get_board_issues`, `jira_get_transitions`, etc.) — not needed for R001–R008; removing them prevents the agent from improvising side-quests.

> **R001 dependency:** `jira-mcp_jira_search` is mandatory — without it the agent falls back to `REVIEW MANUALLY` for R001 on every run.

### 2.3 `SendOutlookEmail` (Office 365 Outlook connector)

| Setting | Value |
|---|---|
| Connector | Office 365 Outlook |
| Action | `Send an email (V2)` (exposed to the agent as `SendOutlookEmail`) |
| Authorized mailbox (From) | `aquiroga@microsoft.com` |
| Default recipient (To) | `aquiroga@microsoft.com` *(approver mailbox; same tenant constraint applies)* |
| Importance | High |

> **Cross-tenant note:** the connector must be authorized with a mailbox in the same tenant as the agent host. Cross-tenant Outlook sending is blocked.

### 2.4 `Visualization` (`Plot*` tools) — **removed**

`PlotAreaChartWithCorrelation`, `PlotBarChart`, `PlotHeatmap`, `PlotPieChart`, `PlotScatter` are not used by the PIM evaluation workflow and have been removed from the toolset. Do not re-add unless a future rule requires chart output in the Adaptive Card.

---

## 3. Scheduled task

| Field | Value |
|---|---|
| Task name | `pim-pending-request-evaluator` |
| Cron expression | `*/5 * * * *` (every 5 minutes) |
| Mode | Review |
| Prompt | See section 4 below |
| Status | Active |
| First successful run | `2026-05-11T11:18:41` local — Run ID `6ef1864a-2aac-4c9d-87e6-3cecb0f443b7` |
| First fully-green run | `2026-05-11T12:13:24` local — request `8e22bd4e`, SCRUM-21, email HTTP 200 |

### 3.1 Scheduled-task prompt (short — delegates to Instructions)

```text
pim-pending-request-evaluator

Execute the standard PIM evaluation workflow defined in your Instructions:

1. Call PIM-MCP_list_pending_pim_requests.
2. If empty: emit "No pending PIM requests at <UTC ISO timestamp>." and stop.
3. Otherwise, for each pending request: gather inputs, evaluate R001–R008,
   emit the Adaptive Card, create the Jira audit ticket (create_issue +
   add_comment + create_remote_issue_link only — never create_issue_link),
   and send the verdict via SendOutlookEmail.
4. End with the one-line run summary: "Run <run-id> evaluated N request(s):
   X PASS, Y FAIL, Z REVIEW."
```

---

## 4. Repository files the agent depends on

| Path | Purpose |
|---|---|
| [`agent/validation-rules.yaml`](agent/validation-rules.yaml) | R001–R008 predicates. Source of truth for rule evaluation. Currently contains real GUID `a19dbeba-9826-4954-bde8-effef5dc7e85` (test-tenant-oncall) for R004 + `PLACEHOLDER` strings for R005/R006 allowlists. |
| [`agent/knowledge.md`](agent/knowledge.md) | Operating rules, throttling guidance, failure handling. Re-read on every run per Instructions. |
| [`agent/adaptive-card.json`](agent/adaptive-card.json) | Adaptive Card template reference. |
| [`PIM-RECOMMENDER-INSTRUCTIONS.md`](PIM-RECOMMENDER-INSTRUCTIONS.md) | Agent Instructions — paste into the SRE Agent UI verbatim. |

---

## 5. Test-tenant context (constants the agent operates against)

| Item | Value |
|---|---|
| Tenant | `MngEnvMCAP094150.onmicrosoft.com` |
| Tenant ID | `a172a259-b1c7-4944-b2e1-6d551f954711` |
| Subscription | `7a28b21e-0d3e-4435-a686-d92889d4ee96` |
| Requester | `pim-requester@MngEnvMCAP094150.onmicrosoft.com` (oid `8a986e7c-f44b-44e0-a8a2-cfc1071faf92`) |
| Approver (oid) | `00a13120-c099-45bc-851a-861ade749067` |
| Test on-call group | `a19dbeba-9826-4954-bde8-effef5dc7e85` (R004 PASS path) |
| Test role | `Privileged Role Administrator` (`e8611ab8-c189-46e8-94e1-60213ab1f814`) |

### 5.1 Triggering a fresh request

```bash
cd pim-enablement-testbed/scripts
pwsh ./trigger-pim-activation.ps1 \
  -TenantId a172a259-b1c7-4944-b2e1-6d551f954711 \
  -RoleDisplayName "Privileged Role Administrator" \
  -DurationHours 1 \
  -Justification "<reason>" \
  -TicketNumber "<TICKET-ID>" \
  -UseDeviceCode
```

Sign in as `pim-requester@…` (NOT admin). Only one `PendingApproval` request per principal at a time — deny or cancel any existing one first.

---

## 6. Verified milestones

| Date | Milestone | Reference |
|---|---|---|
| 2026-05-10 | First live R004 PASS via `get_user_group_memberships` | [`SRE-AGENT-CHATS/11.md`](SRE-AGENT-CHATS/11.md), SCRUM-19 |
| 2026-05-11 11:18 | First scheduled-task auto-run (Option A trigger working) | [`SRE-AGENT-CHATS/12.md`](SRE-AGENT-CHATS/12.md), SCRUM-20 |
| 2026-05-11 12:13 | First fully-green end-to-end (5/5 steps including email) | [`SRE-AGENT-CHATS/13.md`](SRE-AGENT-CHATS/13.md), SCRUM-21 |

---

## 7. Known gaps / next iterations

- **R005/R006 allowlists** still contain `PLACEHOLDER` values. Zafin must supply real role + scope allowlists before this graduates beyond the testbed.
- **R001 predicate type `ticket_state_in`** in `validation-rules.yaml` is not yet wired to inspect Jira state/age/assignee fields — the agent does the lookup via `jira-mcp_search` but cannot enforce state/recency/assignee rules until R001/R002/R003 predicates are implemented in the agent's evaluation loop.
- **Wave 2 PIM-MCP tools** not yet integrated: `get_pim_policy`, `get_role_eligibility_schedule`, `list_role_assignments_for_role`.
- **Cross-tenant Teams posting** blocked by Entra; Outlook email is the current delivery channel.
