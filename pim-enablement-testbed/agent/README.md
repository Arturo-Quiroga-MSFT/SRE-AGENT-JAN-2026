# `agent/` — Azure SRE Agent grounding contract

This directory holds the three artifacts the Azure SRE Agent (`aq-main`)
loads at the start of each PIM-enablement session. They are **inputs to
the agent's reasoning**, not code that runs.

| File | Role |
|---|---|
| [`knowledge.md`](knowledge.md) | System prompt + behavior rules. Defines identity ("PIM Enablement Agent"), scope, MCP-server inventory, decision flow, output format, citation rules. |
| [`validation-rules.yaml`](validation-rules.yaml) | Machine-readable rule table (`R001`–`R008`). The agent cites rule IDs in every verdict. |
| [`adaptive-card.json`](adaptive-card.json) | Teams Adaptive Card schema for posting recommendations to approvers. |

---

## Ownership split — read this before editing anything

The single most important fact about this directory: **engine semantics are
ours, content values are Zafin's.** We deliberately shipped placeholders so
the demo could run end-to-end before Zafin's policy team ratified the real
table.

| File | Engine semantics — **we own** | Content / values — **Zafin owns** | Status |
|---|---|---|---|
| `validation-rules.yaml` | Predicate vocabulary, hard/soft/terminal evaluation order, V1 predicate types | Role allowlist, scope prefixes, on-call group OIDs, ticket-state list, duration cap, frequency thresholds | **Placeholder** — open question **D1** |
| `knowledge.md` | Section structure, tool-call rules, citation format, output schema | Rule rationales, escalation contacts, tenant-specific URLs | Demo-ready, low-stakes edits expected |
| `adaptive-card.json` | Card schema, field bindings, action handlers | Branding, approver routing, button labels | Demo-ready |

> Tracked as **D1** in the open-questions table at
> [`../README.md`](../README.md) (line ~305) and
> [`../from-sre-agent-1.md`](../from-sre-agent-1.md). Until D1 closes,
> any rule values in this directory are **illustrative only**.

---

## What "PLACEHOLDER" means in `validation-rules.yaml`

The YAML uses three sentinel patterns. Anywhere you see one of these, the
value is **not** ratified by Zafin:

| Sentinel | Example | Meaning |
|---|---|---|
| `PLACEHOLDER-...` literal | `PLACEHOLDER-sub-id`, `PLACEHOLDER-group-objectid-oncall-prod` | String value must be replaced before production use |
| `# PLACEHOLDER — Zafin to confirm` inline comment | `"Contributor"   # PLACEHOLDER — Zafin to confirm` | Specific list entry is a guess; Zafin to keep, drop, or replace |
| Header banner | `PLACEHOLDER content. Zafin owns the real rule table (ask D1).` (top of file) | Whole file's content tier is unratified |

Today's demo denials in
[SCRUM-15](https://aq-r2d2.atlassian.net/browse/SCRUM-15) and
[SCRUM-16](https://aq-r2d2.atlassian.net/browse/SCRUM-16) deliberately
trip the placeholder allowlists (Privileged Role Administrator at scope
`/`) so we can exercise the engine end-to-end. The verdicts demonstrate
that the **mechanism** works; the **values** still need Zafin sign-off.

---

## Predicate cheat sheet (V1)

These are the eight predicates the engine understands today. Zafin can
assemble any rule table from this vocabulary without us shipping new
code:

| Predicate | Type | Semantics |
|---|---|---|
| `ticket_state_in` | `list[str]` | Linked Jira ticket's `status` must be in the list |
| `ticket_age_max_hours` | `int` | Linked ticket must have been opened within N hours |
| `requester_assignee_match` | `bool` | Requester must equal ticket assignee |
| `group_membership_any` | `list[str]` | Requester must be a member of at least one group OID |
| `role_in_allowlist` | `list[str]` | Requested role definition must be in the list |
| `scope_prefix_in_allowlist` | `list[str]` | Requested scope must start with one of the prefixes |
| `activation_duration_max_hours` | `int` | Activation duration cap |
| `recent_activations_max` | `{window_hours, count}` | Cap on activations of this role by this user inside a sliding window |

Each rule additionally specifies:

- `kind: hard` → failure ⇒ verdict **NOT ELIGIBLE**.
- `kind: soft` → failure ⇒ verdict **ELIGIBLE** with reduced confidence.
- `terminal: true` → stops further evaluation on failure.

---

## How to ratify (Zafin checklist)

To close D1, Zafin needs to provide values for the variables below.
Once received, edit `validation-rules.yaml` in place and remove every
`PLACEHOLDER` sentinel.

| Variable | Source | Used by rule(s) |
|---|---|---|
| Approved Jira ticket states | Service Desk SOP | R001 |
| Maximum ticket age | Change-management policy | R002 |
| On-call group object IDs (Entra) | Identity team | R004 |
| Approved role list (display names or definition IDs) | PIM policy | R005 |
| Approved scope prefixes (subscription + RG patterns) | Cloud platform team | R006 |
| Maximum activation duration | PIM policy | R007 |
| Activation-frequency threshold | PIM policy / abuse heuristics | R008 |

After ratification, update the file header banner from
`PLACEHOLDER content...` to `Zafin-ratified vN as of YYYY-MM-DD` and bump
`version:` in the YAML. The agent picks up the new content on its next
session — no redeploy needed.

---

## References

- [`../README.md`](../README.md) — testbed status, open questions table (D1 row)
- [`../docs/UPSTREAM_BUGS.md`](../docs/UPSTREAM_BUGS.md) — why `pim-mcp` exists alongside Enterprise MCP
- [`../docs/threat-model.md`](../docs/threat-model.md) — read-only-by-construction guarantee + audit-trail design
- [`../../partner-context/ZAFIN_SRE_AGENT_DESIGN_PATTERN.md`](../../partner-context/ZAFIN_SRE_AGENT_DESIGN_PATTERN.md) — the design pattern the engine semantics implement
- [`../SRE-AGENT-CHATS/`](../SRE-AGENT-CHATS/) — live transcripts where the agent applies these rules
