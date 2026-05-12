# Wave B — Testbed Limitations (and what production needs to bring)

> **Audience:** Zafin and any future partner adopting the `pim-recommender` reference implementation.
> **Purpose:** Honest catalog of where the Wave B testbed differs from a production deployment, so partners know exactly what to bring to make the agent fully effective in their environment.
>
> Wave B's job is to validate the **wiring** (jira-mcp tool calls, status reads, type checks, age math, identity correlation) against a real Jira project. The testbed uses [`aq-r2d2.atlassian.net`](https://aq-r2d2.atlassian.net) (project `SCRUM`) which has limitations around issue type taxonomy and identity that would not exist in a partner tenant. This document calls those out.

---

## TL;DR

| Caveat | Severity | Production fix | Testbed workaround |
|---|---|---|---|
| 1. Issue type taxonomy mismatch | Medium | Use Jira project template aligned with ITSM (ITIL or custom) | Lenient `ticket_type_in` allowlist + Zafin-canonical-to-testbed mapping in agent Instructions |
| 2. No SSO bridge between test Entra tenant and Atlassian | High | Atlassian Access + Entra ID SAML SSO | Hardcoded `agent/identity-map.yaml` lookup |
| 3. Single Jira project / no project-key prefix discipline | Low | Project naming convention (`PROD-`, `OPS-`, `INC-`) | None — testbed uses `SCRUM-` for everything |
| 4. Jira account is a human user (Arturo) | Medium | Atlassian "service account" with API token, scoped roles | Same; document as "use API token even in testbed" |
| 5. No real change-management or incident workflow | Low | Real Jira workflows reflecting Change Approval Board, Incident Severity, etc. | Default SCRUM workflow (To Do / In Progress / Done) |

---

## Caveat 1 — Issue type taxonomy mismatch

### Problem

Atlassian's default SCRUM template ships with **Story / Task / Bug / Epic / Subtask**. Zafin's deterministic rule pack assumes ITIL-flavored types: **Incident / Change Request / Service Request / Deployment / Problem / Security Exception**.

The R001d-ticket-type-valid predicate is wired against the Zafin-canonical names. If we evaluated SCRUM-default tickets directly against that allowlist, every ticket would FAIL with `decision_on_fail: HumanReview`.

### Production fix

Partners should use Jira project templates that already match their ITSM taxonomy:

- **Jira Service Management** (recommended) ships with Incident, Service Request, Change, Problem out of the box.
- **Custom Jira Software project** with custom issue types added in Project Settings → Issue Types.

### Testbed workaround

Two options, both implemented in the agent layer (no schema change):

**Option A** — *Add custom issue types to the SCRUM project (10 min in the Atlassian UI)*

1. `https://aq-r2d2.atlassian.net/jira/settings/issues/issue-types` → **+ Add issue type**
2. Create: Incident, Change Request, Service Request, Deployment, Problem, Security Exception
3. Associate them with the SCRUM project's issue type scheme
4. Use them on the four Wave B fixture tickets

This is the closer-to-production option and is recommended.

**Option B** — *Lenient mapping in agent Instructions*

The agent's `PIM-RECOMMENDER-INSTRUCTIONS.md` carries a translation table:

```
SCRUM-default → Zafin-canonical (testbed only)
  Story         → Change Request
  Task          → Service Request
  Bug           → Incident
  Epic          → (rejected — not operational)
  Subtask       → (rejected — not operational)
```

Less work but the predicate becomes essentially a tautology in the testbed (because the mapping is already injective onto valid types). Use only if Option A is blocked.

---

## Caveat 2 — No SSO bridge between test Entra tenant and Atlassian

### Problem

The R003-requester-linked-to-ticket predicate needs to answer: *"is the PIM requester (`pim-requester@MngEnvMCAP094150.onmicrosoft.com`) the reporter, assignee, or watcher of Jira ticket `SCRUM-42`?"*

But:

- `pim-requester@MngEnvMCAP094150.onmicrosoft.com` is an Entra principal in a test tenant
- `aq-r2d2.atlassian.net` has no Atlassian Access SAML bridge to that tenant
- Therefore there is no Atlassian `accountId` corresponding to the PIM requester

### Production fix

Three converging requirements at the partner tenant:

1. **Atlassian Access** subscription (per-user license), enabling SAML SSO.
2. **Entra ID Enterprise Application** for Atlassian Cloud, configured for SAML SSO + automatic user provisioning (SCIM).
3. **Atlassian directory sync** so every Entra principal that could appear as a PIM requester also exists as an Atlassian user with a stable `accountId`.

When all three are in place, the agent can resolve identity at evaluation time:

```
entra_upn  →  Atlassian /rest/api/3/user/search?query=<upn>  →  accountId
```

### Testbed workaround

Hardcoded YAML map at `agent/identity-map.yaml`:

```yaml
mappings:
  pim-requester@MngEnvMCAP094150.onmicrosoft.com:
    account_id: "<your aq-r2d2 accountId>"
    display_name: "PIM Test Requester"
```

The agent loads this map at evaluation time. Lookup miss → predicate FAIL with `decision_on_fail: HumanReview` (intentionally lenient — we don't want testbed identity gaps to mask other rules).

To populate the `account_id`:

```bash
curl -u 'aquiroga@microsoft.com:<api-token>' \
  https://aq-r2d2.atlassian.net/rest/api/3/myself | jq .accountId
```

Paste into `identity-map.yaml`. Commit.

---

## Caveat 3 — Single Jira project, no project-key prefix discipline

### Problem

Real environments use project-key prefixes to indicate ticket class (`INC-` for incidents, `CHG-` for changes, `SR-` for service requests). The R001-ticket-id-format regex is designed to match any `[A-Z]+-\d+` format, so it accepts any prefix — but in production the agent could optionally enforce that certain PIM scopes only accept tickets from certain project prefixes (e.g. tenant-root scope requires a `SEC-` ticket).

### Production fix

Add a `scope_requires_ticket_prefix` predicate in Wave C alongside the real Scope Catalog (Zafin Table 2). Each scope row includes `acceptable_ticket_prefixes: [INC, CHG, SEC]`.

### Testbed workaround

None. The testbed accepts `SCRUM-` for everything. Document this gap in the Wave C handoff to Zafin.

---

## Caveat 4 — Jira account is a human user

### Problem

The jira-mcp container currently authenticates as `aquiroga@microsoft.com` (a real Microsoft employee account, not a service account). This means:

- All audit comments on SCRUM-22/23/24 etc. show "added by Arturo Quiroga"
- API token rotation requires Arturo's manual action
- If Arturo leaves Microsoft, the agent breaks

### Production fix

Atlassian "service account" pattern:

1. Create a new Atlassian Cloud user (e.g. `pim-recommender@zafin.com` — must be a real mailbox per Atlassian rules, but can be a shared monitored mailbox).
2. Generate an API token for that user.
3. Grant project roles: Browse Projects + Add Comments + Create Issues on the audit project; nothing else.
4. Store the token in Key Vault; jira-mcp reads it via Managed Identity.

### Testbed workaround

For the Wave B testbed, Arturo's API token continues to work but is stored as `JIRA_API_TOKEN` env var on the jira-mcp container. Acceptable for testbed; flag in handoff.

---

## Caveat 5 — Default SCRUM workflow

### Problem

The default workflow has only three states (To Do / In Progress / Done). Real change-management workflows have richer state machines (Submitted → CAB Review → Approved → Scheduled → In Progress → Verifying → Closed) where the *active* states are different from the *terminal* states.

The R001c-ticket-status-active block-list (`["Done", "Closed", "Cancelled", "Rejected", "Duplicate", "Resolved", "Won't Do"]`) is intentionally over-inclusive of common terminal states across multiple Jira workflow templates so that the testbed's three-state workflow is correctly handled.

### Production fix

Each partner customizes the block-list to match their workflow's terminal states. Done in Wave C as part of the per-tenant configuration handoff.

### Testbed workaround

Current block-list works against default SCRUM. No action needed for testbed.

---

## What Zafin needs to bring to the production deployment

When the PoC moves into Zafin's tenant, the following must be in place before cutover:

1. **Atlassian Access + Entra ID SSO** (Caveat 2). Without this, identity correlation falls back to the leniency mode and most R003 evaluations route to Human Review — defeating the automation gain.
2. **Real ticket type taxonomy** (Caveat 1) — either Jira Service Management or a customized Jira Software project with the six canonical types.
3. **Atlassian service account** (Caveat 4) with project-scoped permissions and Key Vault-stored API token.
4. **Per-scope ticket-prefix policy** (Caveat 3) provided as part of the Wave C Scope Catalog handoff.
5. **Workflow terminal-state catalog** (Caveat 5) for each Jira project the agent will read tickets from, provided as part of the Wave C configuration handoff.

Items 1–3 are independent of the rule pack and can be put in place before Wave C closes. Items 4–5 are deliverables of the Wave C handoff itself.

---

## Wave B fixture tickets (testbed)

To exercise R001..R003 end-to-end, four fixture tickets are needed in `aq-r2d2.atlassian.net` SCRUM project:

| Key | Purpose | Status | Type | Reporter | Created |
|---|---|---|---|---|---|
| (TBD) | Approve path | In Progress | Change Request (after Caveat 1A) | Arturo | today |
| (TBD) | R001c FAIL | Done | Change Request | Arturo | today |
| (TBD) | R003 FAIL | In Progress | Change Request | someone else | today |
| (TBD) | R002 FAIL | In Progress | Change Request | Arturo | 5 days ago |

Each gets a `trigger-pim-activation.ps1` invocation citing it as `-TicketNumber SCRUM-XX`. Captured runs become 17.md / 18.md / 19.md / 20.md in `SRE-AGENT-CHATS/`.

---
