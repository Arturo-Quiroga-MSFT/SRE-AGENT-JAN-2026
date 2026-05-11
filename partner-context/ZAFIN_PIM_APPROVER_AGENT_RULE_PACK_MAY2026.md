# Zafin — PIM Approver Agent: Deterministic Rule Pack

> **Source:** `PIM_Approver_Agent_Deterministic_Rule_Pack.docx` shared by Zafin (IAM/PIM Agent Experience – Security & Compliance), 2026-05-11.
> **Imported by:** Arturo Quiroga, PSA — converted to Markdown for the testbed.
> **Repo location of testbed implementation:** [`pim-enablement-testbed/`](../pim-enablement-testbed/)
> **Current testbed rules (subset):** [`pim-enablement-testbed/agent/validation-rules.yaml`](../pim-enablement-testbed/agent/validation-rules.yaml) (R001–R008 only)

---

## 1. Purpose

This rule pack defines deterministic guardrails for the IAM/PIM Agent to evaluate Azure PIM requests and provide a recommendation to the human approver.

**The agent must not approve PIM requests directly.** It must evaluate the request, generate a decision recommendation, provide evidence, and guide the human approver to approve or reject in Azure PIM.

This model supports Zafin access control principles:

- Formal authorization
- Least privilege
- Need-to-know and need-to-use
- Ticket-backed access
- Time-bound privileged access
- Segregation of duties (SoD)
- MFA enforcement
- Privileged access logging and auditability
- Exception handling through appropriate approval channels

**Policy basis:** Zafin Access Control Policy `IS_POL_GLB_005` — requires controlled access, formal authorization, least privilege, PIM-managed privileged users, MFA, time-bound access, ticket-backed provisioning, audit logging, and SoD.

---

## 2. Core Operating Principle

The agent must produce only one of the following outcomes:

| Decision | Meaning | Human Action |
|---|---|---|
| **Approve** | Request is compliant as submitted | Human approver may approve in Azure PIM |
| **Reject with Remarks** | Request is non-compliant or must be resubmitted with corrected information | Human approver rejects in Azure PIM using agent-provided remarks |
| **Human Review Needed** | Request is ambiguous, high-risk, exceptional, or outside deterministic rules | Human approver performs manual review or escalates |
| *Open PIM Request* | Convenience action only | Opens the Azure PIM request screen |

---

## 3. Golden Rule

> Anything **not explicitly allowed** by the deterministic rules must be classified as **Human Review Needed**.

The agent must not infer approval where required evidence is missing, ambiguous, stale, or inconsistent.

---

## 4. Data Inputs Required

| Input | Source |
|---|---|
| PIM requester | Azure PIM / Entra ID |
| Requested role | Azure PIM |
| Requested scope | Azure PIM |
| Requested duration | Azure PIM |
| PIM justification | Azure PIM |
| Ticket ID | PIM justification or structured PIM field |
| Ticket status/details | Jira |
| Requester group membership | Entra ID |
| Requester team/function | Entra ID / HR / team mapping |
| MFA status | Entra ID / Conditional Access |
| Account status | Entra ID |
| Role allowlist | Agent reference table |
| Subscription/scope catalog | Agent reference table |
| Ticket validation rules | Agent reference table |
| High-risk role catalog | Agent reference table |
| Optional risk signals | Entra ID, Sentinel, Defender, audit logs |

---

## 5. Mandatory Reference Tables

The agent must not rely only on free-text interpretation. It must evaluate PIM requests against the following four reference tables.

### Table 1 — Role Allowlist

Defines which teams/functions are allowed to request which privileged roles, at what scope, in which environments, and for how long.

| Team / Function | Role | Risk | Allowed Scope | Environment | Default Duration | Max Duration | Human Review Required | Required Approver |
|---|---|---|---|---|---|---|---|---|
| Cloud Ops | Reader | Low | Subscription / RG | Prod / Non-prod | 2 hrs | 4 hrs | No | Cloud Ops |
| Cloud Ops | Contributor | Medium | RG / Subscription | Prod | 1 hr | 2 hrs | No, if all checks pass | Cloud Ops |
| Cloud Ops | Owner | Critical | Subscription | Any | N/A | N/A | Yes | Cloud Ops Director / Asset Owner |
| SRE | Monitoring Reader | Low | Subscription / RG | Prod / Non-prod | 2 hrs | 4 hrs | No | SRE / Cloud Ops |
| SRE | VM Contributor | Medium | RG / Resource | Prod / Non-prod | 1 hr | 2 hrs | No, if all checks pass | SRE / Cloud Ops |
| ETG | User Administrator | Medium | Tenant | Internal | 1 hr | 1 hr | Yes | ETG |
| ETG | Global Administrator | Critical | Tenant | Any | N/A | N/A | Yes | CISO |
| SecOps | Security Reader | Low | Tenant / Subscription | Any | 2 hrs | 4 hrs | No | SecOps |
| SecOps | Security Administrator | High | Tenant / Subscription | Any | N/A | N/A | Yes | CISO / SecOps |

> *Note (from Zafin): "We should be able to update this table."*

### Table 2 — Subscription / Scope Catalog

Defines which teams are allowed to request access to each Azure subscription, environment, resource group, or resource scope.

| Subscription / Scope Type | Authorized Teams | Low Risk Max | Medium Risk Max | High Risk Handling | Exception Approver |
|---|---|---|---|---|---|
| Non-prod internal | Cloud Ops, SRE, Engineering | 8 hrs | 4 hrs | Human Review Needed | Cloud Ops Director |
| Production internal | Cloud Ops, SRE | 4 hrs | 2 hrs | Human Review Needed | Asset Owner / Cloud Ops Director |
| Client-connected production | Cloud Ops, SRE | 2 hrs | 2 hrs | Human Review Needed | Asset Owner / SVP Cloud / CISO if security-sensitive |
| Identity tenant | ETG, SecOps | 2 hrs | 1 hr | Human Review Needed | CISO / ETG Director |
| Security / audit subscription | SecOps, Cloud Ops | 4 hrs | 2 hrs | Human Review Needed | CISO / SecOps Lead |
| Shared platform subscription | Cloud Ops, SRE | 4 hrs | 2 hrs | Human Review Needed | Platform Owner |

**Per-row fields:** Subscription Name, Subscription ID, Scope Type (Subscription/RG/Resource), Environment, Client Connected (Y/N), Business Owner, Technical Owner, Authorized Teams, Allowed Roles, Low Risk Max Duration, Medium Risk Max Duration, High Risk Handling, Exception Approver.

### Table 3 — Ticket Validation Rules

| Ticket Type | Valid Status | Required Evidence | Validity Window | Approval Required |
|---|---|---|---|---|
| Incident | Open, In Progress, Monitoring | Impacted system, severity, business impact, assignee/team | While active + 7 days | No, unless high-risk role |
| Change | Approved, Implementing, Scheduled | Change window, environment, impacted scope, approver | Until change window closes | Yes |
| Service Request | Open, In Progress, Approved | Business reason, requested system/scope, requester/owner | 14 days | Manager/owner approval if prod |
| Deployment Task | Open, In Progress, Approved | Release/change link, deployment window, environment | Deployment window only | Yes for production |
| Problem | Open, In Progress | Investigation scope, impacted service, assignee/team | 30 days with recent update | No, unless prod/high-risk |
| Security Exception | Approved | Exception ID, approver, expiry date, compensating controls | Until expiry | Director+ / CISO as applicable |

**Invalid statuses** (universal): Done, Closed, Cancelled, Rejected, Duplicate.

### Table 4 — High-Risk Role Catalog

Privileged roles that must not be approved through standard deterministic approval, even when other checks pass.

| Role | Risk | Reason | Standard Decision | Required Approver | Additional Controls |
|---|---|---|---|---|---|
| Owner | Critical | Full control including RBAC delegation | Human Review Needed | Asset Owner / Cloud Ops Director | Two-person rule, monitoring |
| User Access Administrator | Critical | Can grant access to others | Human Review Needed | CISO / Cloud Ops Director | Two-person rule |
| Global Administrator | Critical | Tenant-wide control | Human Review Needed | CISO | Two-person rule, post-review |
| Privileged Role Administrator | Critical | Can manage privileged roles | Human Review Needed | CISO | Two-person rule |
| Conditional Access Administrator | Critical | Can alter access controls | Human Review Needed | CISO / SecOps | Security review |
| Security Administrator | High | Can modify security settings | Human Review Needed | CISO / SecOps | Monitoring |
| Key Vault Administrator | High | Can manage secrets and keys | Human Review Needed | Asset Owner / SecOps | Post-review |
| Billing Administrator | High | Financial/account-level impact | Human Review Needed | Finance / Cloud Ops | Review |
| Compliance Administrator | High | Can access compliance/audit controls | Human Review Needed | CISO / Compliance | Audit review |

---

## 6. Deterministic Validation Rules

The agent must evaluate the following rules **in order**.

### 6.1 Required Field Validation

| Rule ID | Area | Rule | Pass | Fail | Decision |
|---|---|---|---|---|---|
| PIM-001 | Required fields | Request must include requester, role, scope, duration, justification, ticket ID, environment | All fields present | One or more missing | Human Review Needed |
| PIM-002 | Requester identity | Must be individually assigned named user | Named active user account | Shared, generic, disabled, terminated, orphaned, unclear | Reject with Remarks |
| PIM-003 | Justification | Must contain meaningful business reason | Explains task and need for privilege | Generic ("need access", "support") or blank | Reject with Remarks |
| PIM-004 | Environment | Must be identifiable | Prod/non-prod/client/internal/security/identity/platform identified | Missing or ambiguous | Human Review Needed |

### 6.2 Ticket Validation

| Rule ID | Area | Rule | Pass | Fail | Decision |
|---|---|---|---|---|---|
| PIM-005 | Ticket reference | Must contain valid ticket ID | Present in expected format | No ticket ID | Reject with Remarks |
| PIM-006 | Ticket existence | Must exist in Jira | Resolves successfully | Not found | Reject with Remarks |
| PIM-007 | Ticket status | Must be active | Valid per Table 3 | Done, Closed, Cancelled, Rejected, Duplicate | Reject with Remarks |
| PIM-008 | Ticket type | Must be valid for privileged access | Incident, Change, SR, Deployment Task, Problem, Security Exception | Epic-only, doc task, backlog placeholder, unclear | Human Review Needed |
| PIM-009 | Ticket freshness | Must be within validity window | Created/updated within threshold | Stale, no recent update | Human Review Needed |
| PIM-010 | Ticket documentation | Must document the access need | System, environment, task, business reason, scope | Missing meaningful detail | Reject with Remarks |
| PIM-011 | Ticket approval | Must have required approval where applicable | Approval exists | Required approval missing | Human Review Needed |
| PIM-012 | Change window | Change/deployment PIM must fit within approved window | Within window | Outside window | Reject with Remarks |

### 6.3 Requester Authorization Validation

| Rule ID | Area | Rule | Pass | Fail | Decision |
|---|---|---|---|---|---|
| PIM-013 | Requester-ticket relationship | Requester must be related to the ticket | Reporter, assignee, named implementer, on-call engineer, assigned team member | No relationship | Reject with Remarks |
| PIM-014 | Team authorization | Must belong to authorized team/group | In approved Entra group/team mapping | Not in authorized group | Reject with Remarks |
| PIM-015 | Contractor/vendor status | Elevated access requires valid work authorization | Active approved work/ticket evidence | No valid authorization | Human Review Needed |
| PIM-016 | Employment/account status | Account must be active | Active | Disabled, terminated, suspended, stale, orphaned | Reject with Remarks |

### 6.4 Role Validation

| Rule ID | Area | Rule | Pass | Fail | Decision |
|---|---|---|---|---|---|
| PIM-017 | Role allowlist | Role must be allowed for requester team/function | In Role Allowlist for team | Not allowed | Reject with Remarks |
| PIM-018 | Role risk | High-risk and critical roles must be reviewed manually | Low or medium risk | High or critical | Human Review Needed |
| PIM-019 | Role appropriateness | Role must align to task in ticket | Task reasonably requires role | Role exceeds task need | Human Review Needed |
| PIM-020 | RBAC principle | Role must follow least privilege | Minimum required | Broader where narrower exists | Human Review Needed |

### 6.5 Scope Validation

| Rule ID | Area | Rule | Pass | Fail | Decision |
|---|---|---|---|---|---|
| PIM-021 | Scope catalog | Scope must exist in catalog | Found in catalog | Unknown/uncatalogued | Human Review Needed |
| PIM-022 | Scope authorization | Requester team must be authorized | Listed as authorized | Not authorized | Reject with Remarks |
| PIM-023 | Scope-ticket match | PIM scope must match ticket scope | Ticket references same subscription/RG/resource/system/client/env | Mismatch | Reject with Remarks |
| PIM-024 | Scope minimization | Must be narrowest practical scope | Resource/RG used where appropriate | Subscription requested when RG/resource suffices | Human Review Needed |
| PIM-025 | Production/client scope | Requires explicit evidence | Ticket identifies prod/client + business need | Evidence missing/unclear | Human Review Needed |
| PIM-026 | Tenant-level scope | Requires manual review | Not tenant-level | Tenant-wide/identity-wide | Human Review Needed |
| PIM-027 | Management group/root scope | Requires manual review | Not MG/root | MG or root | Human Review Needed |

### 6.6 Segregation of Duties Validation

| Rule ID | Area | Rule | Pass | Fail | Decision |
|---|---|---|---|---|---|
| PIM-033 | Self-approval risk | Requester must not approve own access/change | No self-approval path | Requester is ticket/change/PIM approver for own request | Human Review Needed |
| PIM-034 | Requester/approver/implementer separation | Duties should be segregated | Separated | Same person can request, approve, implement | Human Review Needed |
| PIM-035 | Audit/log control conflict | Must not gain access to change own audit logs | No conflict | Access allows modifying/disabling audit/logging | Human Review Needed |
| PIM-036 | RBAC delegation conflict | Must not gain ability to grant further access without elevated review | No delegation conflict | Role allows granting access to others | Human Review Needed |

### 6.7 Break-Glass and Emergency Validation

| Rule ID | Area | Rule | Pass | Fail | Decision |
|---|---|---|---|---|---|
| PIM-037 | Break-glass indicator | Emergency requests require manual review | Standard request | Outage, cyber incident, PIM unavailable, identity failure, urgent emergency, break-glass keywords | Human Review Needed |
| PIM-038 | Break-glass ticket | Must have incident/change evidence | Evidence exists | No emergency evidence | Human Review Needed |
| PIM-039 | Break-glass approval | CISO/delegate or appropriate emergency approval | Approval evidence or immediate CIA protection rationale | Neither | Human Review Needed |
| PIM-040 | Post-event review | Requires post-event review/RCA flag | Review flag created | No review tracking | Human Review Needed |

### 6.8 Pattern and Abuse Detection

| Rule ID | Area | Rule | Pass | Fail | Decision |
|---|---|---|---|---|---|
| PIM-041 | Repeated requests | Beyond threshold must be reviewed | Within normal threshold | Same role/scope beyond threshold | Human Review Needed |
| PIM-042 | Prior denials | Recent denials must be considered | No relevant recent denial | Same/similar request recently denied | Human Review Needed |
| PIM-043 | Odd-hours request | Unusual timing may require review | Normal or justified on-call/incident | Odd-hours with no incident/on-call evidence | Human Review Needed |
| PIM-044 | Rare role request | Rare/unusual roles require review | Commonly used by team | Rarely requested by user/team | Human Review Needed |

---

## 7. Duration Framework

Duration must be evaluated deterministically using the **strictest applicable limit**.

### 7.1 Duration Calculation

```text
allowed_duration = min(
  role_max_duration,
  subscription_scope_max_duration,
  ticket_type_max_duration,
  change_window_remaining_duration
)
```

If any required duration input is missing or ambiguous → **Human Review Needed**.

### 7.2 Duration Rules

| Rule ID | Rule | Logic | Decision |
|---|---|---|---|
| DUR-001 | Duration required | If requested duration is missing | Human Review Needed |
| DUR-002 | Time-bound | If duration is indefinite/open-ended | Reject with Remarks |
| DUR-003 | Role max | If requested > role max | Reject with Remarks |
| DUR-004 | Subscription/scope max | If requested > scope max | Reject with Remarks |
| DUR-005 | Ticket type max | If requested > ticket type max | Reject with Remarks |
| DUR-006 | Change window | If requested > change window | Reject with Remarks |
| DUR-007 | High-risk role | If high-risk role requested | Human Review Needed |
| DUR-008 | Break-glass | If emergency/break-glass | Human Review Needed |
| DUR-009 | Compliant | If requested ≤ allowed_duration | Continue / Approve if all checks pass |

### 7.3 Example Duration Matrix

| Environment | Risk | Example Roles | Max Duration |
|---|---|---|---|
| Non-prod / internal | Low | Reader, Log Analytics Reader | 8 hrs |
| Non-prod / internal | Medium | Contributor, VM Contributor, AKS Cluster User | 4 hrs |
| Non-prod / internal | High | Owner, UAA, Key Vault Admin | Human Review |
| Production / internal | Low | Reader, Monitoring Reader, Log Analytics Reader | 4 hrs |
| Production / internal | Medium | Contributor, VM Contributor, AKS Contributor | 2 hrs |
| Production / internal | High | Owner, UAA, Security Admin | Human Review |
| Client-hosted / client-connected | Low | Reader, Monitoring Reader | 2 hrs |
| Client-hosted / client-connected | Medium | Contributor, VM Contributor, AKS Contributor | 2 hrs |
| Client-hosted / client-connected | High | Owner, UAA, Key Vault Admin, Security Admin | Human Review |
| Identity / tenant-level | Low | Directory Reader, Reports Reader | 2 hrs |
| Identity / tenant-level | Medium | Groups Administrator, User Administrator | 1 hr |
| Identity / tenant-level | High | Global Administrator, Privileged Role Administrator, Conditional Access Administrator | Human Review |
| Security tooling / audit / Sentinel | Low | Security Reader | 4 hrs |
| Security tooling / audit / Sentinel | Medium | Sentinel Contributor, Security Operator | 2 hrs |
| Security tooling / audit / Sentinel | High | Security Administrator, Compliance Administrator | Human Review |

---

## 8. Final Decision Matrix

| Condition | Final Recommendation |
|---|---|
| All checks pass; ticket valid+active; requester authorized; role allowed; scope allowed & matches ticket; MFA passed; no SoD; duration within max | **Approve** |
| Ticket invalid, missing, closed, cancelled, stale w/o valid update, missing required evidence, or not linked to requester | **Reject with Remarks** |
| Role not allowed for requester team/function | **Reject with Remarks** |
| Scope not allowed or doesn't match ticket | **Reject with Remarks** |
| Duration exceeds role/scope/ticket/change-window maximum | **Reject with Remarks** |
| MFA, account status, or basic identity control fails | **Reject with Remarks** |
| High-risk role, break-glass, SoD conflict, prod/client ambiguity, tenant-level ambiguity, exception case, repeated unusual pattern, anything not covered | **Human Review Needed** |

---

## 9. Decision Algorithm

1. Validate required request fields. *Missing → Human Review Needed.*
2. Validate requester account. *Shared/generic/disabled/terminated/orphaned → Reject with Remarks.*
3. Validate Jira ticket. *Missing/invalid/closed/cancelled/rejected/undocumented → Reject with Remarks.*
4. Validate ticket freshness and type. *Stale/invalid/ambiguous → Human Review Needed.*
5. Validate requester relationship to ticket. *Not reporter/assignee/implementer/on-call/team member → Reject with Remarks.*
6. Validate requester team/group authorization. *Not in authorized group → Reject with Remarks.*
7. Validate requested role against Role Allowlist. *Not allowed → Reject with Remarks. High-risk/critical → Human Review Needed.*
8. Validate requested scope against Subscription/Scope Catalog. *Not found → Human Review Needed. Team not authorized → Reject. Scope mismatch → Reject. Broader than ticket → Human Review Needed.*
9. Validate SoD. *End-to-end self-approval path → Human Review Needed.*
10. Check break-glass/emergency indicators. *Detected → Human Review Needed.*
11. Calculate `allowed_duration = min(role max, scope max, ticket type max, change window)`.
12. Validate requested duration. *> allowed → Reject. ≤ allowed → continue.*
13. All deterministic checks pass → **Approve**.
14. No deterministic rule applies → **Human Review Needed**.

---

## 10. Teams Approver Card

### 10.1 Approver Card Fields

| Field | Value |
|---|---|
| Requester | `<requester>` |
| Requester Team | `<team>` |
| Requested Role | `<role>` |
| Requested Scope | `<scope>` |
| Environment | `<environment>` |
| Requested Duration | `<duration>` |
| Allowed Duration | `<calculated allowed duration>` |
| Ticket | `<Jira ticket>` |
| Ticket Status | `<ticket status>` |
| Risk Level | `<low / medium / high / critical>` |
| Agent Recommendation | `<Approve / Reject with Remarks / Human Review Needed>` |

### 10.2 Validation Summary

Each of the following must be reported as **Pass / Fail / Review**:

- Required fields present
- Ticket exists
- Ticket active
- Ticket documentation sufficient
- Requester linked to ticket
- Requester authorized group
- Role allowed
- Scope allowed
- Scope matches ticket
- Duration compliant
- MFA satisfied
- Account active/named
- SoD conflict
- High-risk role *(Yes/No)*
- Break-glass indicator *(Yes/No)*

---

## 14. Audit and Evidence Requirements

The agent must retain evidence supporting each recommendation:

- PIM request payload
- Jira ticket snapshot
- Role allowlist result
- Scope catalog result
- Duration calculation
- MFA/account status result
- SoD result
- Recommendation rationale
- Teams message sent to approver
- Requester notification (if sent)
- Human decision outcome

---

## 15. Human Review Triggers

Classify as **Human Review Needed** if any of the following are true:

- Required fields are ambiguous rather than clearly missing
- Ticket type is not clearly valid or invalid
- Ticket is stale but may still represent valid work
- Production or client-connected environment is unclear
- Scope is broader than the ticket but may be justified
- Requested role is high-risk or critical
- Request involves tenant-level, management-group, or root scope
- Request involves break-glass or emergency access
- SoD conflict is detected
- User/sign-in risk is medium or high
- Contractor/vendor access requires elevated review
- Request appears unusual compared with historical patterns
- Rule table does not explicitly cover the scenario
- Exception approval may be required
- Evidence conflicts across PIM, Jira, Entra, or catalog data

---

## 16. Hard Reject Triggers

Classify as **Reject with Remarks** if any of the following are true:

- No ticket reference is provided
- Ticket does not exist
- Ticket is closed, cancelled, rejected, duplicate, or done
- Ticket lacks meaningful business justification
- Requester is not linked to the ticket
- Requester is not in an authorized group/team
- Requested role is not allowed for requester team/function
- Requested scope is not authorized for requester team/function
- Requested scope clearly does not match the ticket
- Requested duration exceeds allowed duration
- MFA is not enabled or not satisfied
- Account is disabled, terminated, generic, shared, or orphaned
- Change/deployment request is outside approved change window
- Ticket approval is required but clearly absent
- PIM request uses a closed or stale ticket with no valid update

---

## 17. Approval Triggers

Recommend **Approve** only when **all** of the following are true:

- All required fields are present
- Requester is a valid named active user
- Ticket exists, is active, valid type, within validity window
- Ticket contains sufficient business justification
- Requester is linked to the ticket
- Requester belongs to an authorized group/team
- Requested role is allowed for requester team/function
- Requested role is not high-risk or critical
- Requested scope is listed in the scope catalog
- Requester team is authorized for the scope
- Requested scope matches the ticket
- Requested scope is not broader than required
- Requested duration is within calculated allowed duration
- MFA is enabled and satisfied
- Conditional Access/account status checks pass
- No SoD conflict is detected
- No break-glass/emergency pattern is detected
- No exception is required
- No unresolved ambiguity exists

---

## 18. Implementation Notes

### 18.1 Agent Behavior

The agent should be **deterministic-first** and **AI-assisted-second**.

**Allowed AI use:**

- Summarizing the ticket
- Extracting scope/environment from ticket text
- Explaining recommendation rationale
- Drafting Teams messages
- Drafting rejection remarks

**Not allowed AI use:**

- Overriding deterministic rules
- Approving based on confidence alone
- Ignoring missing evidence
- Inferring authorization without catalog/group evidence
- Treating high-risk exceptions as normal approvals

### 18.2 Configuration (must be changeable without code changes)

Valid Jira project keys · valid ticket statuses · invalid ticket statuses · valid ticket types · ticket freshness thresholds · Role Allowlist · Scope Catalog · duration limits · High-Risk Role Catalog · Human Review triggers · Hard Reject triggers · approver groups · requester notification templates · rejection remarks.

---

## 19. Recommended Initial Thresholds

| Control | Recommended Initial Threshold |
|---|---|
| Incident ticket validity | While active + 7 days |
| Change ticket validity | Until implementation window closes |
| Service request validity | 14 days |
| Deployment task validity | Deployment window only |
| Problem ticket validity | 30 days with recent update |
| Security exception validity | Until approved expiry |
| Repeated same role/scope threshold | More than 3 requests in 24 hours **or** 5 in 7 days |
| Odd-hours review | Outside requester normal region / business / on-call window |
| High-risk role | Always Human Review Needed |
| Tenant-level scope | Always Human Review Needed |
| Break-glass | Always Human Review Needed |

---

## 20. Final Operating Model

1. Read the Azure PIM request.
2. Extract requester, role, scope, duration, justification, ticket ID.
3. Validate the ticket in Jira.
4. Validate requester relationship to the ticket.
5. Validate requester group/team authorization.
6. Validate role against Role Allowlist.
7. Validate scope against Subscription/Scope Catalog.
8. Validate duration using the strictest applicable duration limit.
9. Validate MFA, account status, and risk signals.
10. Check for SoD conflicts.
11. Check for high-risk role, prod ambiguity, client-environment ambiguity, or break-glass.
12. Generate one of three recommendations: **Approve / Reject with Remarks / Human Review Needed**.
13. Send Teams card to approver with PIM deep link.
14. If rejection recommended, optionally send Teams message to requester with corrective action.
15. Store full audit record.
16. Capture human approver final decision where possible.

---

## 21. Summary (Zafin's stated goals)

The deterministic PIM rule pack ensures privileged access is:

- Explicitly authorized
- Linked to a valid business ticket
- Bound to the requester role and team
- Limited to the minimum necessary scope
- Limited to the minimum necessary duration
- Protected by MFA and Conditional Access
- Reviewed for SoD conflicts
- Escalated when high-risk, ambiguous, or exceptional
- Fully auditable

**Agent default posture:**

> Approve only when explicitly permitted. Reject when clearly non-compliant. Route to Human Review when ambiguous, high-risk, or not covered.

---

## Mapping to current testbed (Arturo's notes — 2026-05-11)

Our [`validation-rules.yaml`](../pim-enablement-testbed/agent/validation-rules.yaml) currently implements 8 rules (R001–R008). Mapping to Zafin's pack:

| Testbed | Zafin equivalent | Gap |
|---|---|---|
| R001 ticket-exists | PIM-005 + PIM-006 + PIM-007 | Need explicit `Reject` (not `REVIEW`) on missing/closed |
| R002 ticket-recent | PIM-009 | OK, needs per-ticket-type validity windows from Table 3 |
| R003 requester-assignee | PIM-013 | Need expansion: reporter / assignee / on-call / team member |
| R004 group-membership | PIM-014 | OK (✓ live PASS via `get_user_group_memberships`) |
| R005 role-allowlist | PIM-017 + Table 1 | Replace `PLACEHOLDER` with Zafin's Table 1 |
| R006 scope-allowlist | PIM-021 + PIM-022 + Table 2 | Replace `PLACEHOLDER-sub-id` with Zafin's Table 2 |
| R007 duration-cap | DUR-001 through DUR-006 | Needs `min(...)` calculation across all four limits |
| R008 activation-frequency | PIM-041 | Threshold currently `3/24h`; Zafin recommends `3/24h OR 5/7d` |
| *(missing)* | PIM-001 to PIM-004 | Required-field / requester-identity / justification / environment |
| *(missing)* | PIM-008 ticket type | Need ticket-type allowlist |
| *(missing)* | PIM-018 role risk | High-risk → always Human Review |
| *(missing)* | PIM-025 to PIM-027 scope sensitivity | Prod/client/tenant/MG/root → always Human Review |
| *(missing)* | PIM-033 to PIM-036 SoD | Need Entra group/role overlap analysis |
| *(missing)* | PIM-037 to PIM-040 break-glass | Keyword detection in justification |
| *(missing)* | PIM-042 prior denials | Need history-scan extension |
| *(missing)* | MFA / Conditional Access check | Need pim-mcp tool for `signInActivity` + CA state |

**Verdict vocabulary upgrade required:** our testbed emits `ELIGIBLE / NOT ELIGIBLE / REVIEW MANUALLY`. Zafin uses `Approve / Reject with Remarks / Human Review Needed`. We should adopt Zafin's vocabulary verbatim before next demo.

**Next Wave 2/3 work tagged by this doc:**

- Wave 2 pim-mcp tools: `get_pim_policy`, `get_role_eligibility_schedule`, `list_role_assignments_for_role` — partially address PIM-019/PIM-020/PIM-024.
- New tools needed: Entra `signInActivity` reader (MFA/CA), Entra group conflict scanner (SoD).
- `validation-rules.yaml` schema extension: add `decision: Approve|Reject|HumanReview` per rule (currently only `result: PASS/FAIL`).
