# PIM Enablement — Threat Model Note

> Purpose: confirm the agent never holds approval authority and document
> the residual risks that the design accepts.
>
> **May 4 2026 update (post live-test):** PIM access is now **hybrid**.
> ~90% of reads flow through the Microsoft-hosted MCP Server for Enterprise
> (delegated, read-only by current preview scope). The one Graph endpoint
> Enterprise MCP cannot reach today — `roleAssignmentScheduleRequests` — is
> served by a single-tool custom MCP (`pim-mcp`) using **app-only Graph auth
> via Managed Identity**. The custom MCP is read-only by construction (no
> write tool exists). Both paths reinforce the original "agent never
> approves" posture.
>
> **May 5 2026 update (live runtime finding):** Microsoft Graph **runtime**
> rejects `RoleAssignmentSchedule.Read.Directory` (both delegated AND
> application) for the LIST `roleAssignmentScheduleRequests` endpoint, even
> though the [official docs](https://learn.microsoft.com/en-us/graph/api/rbacapplication-list-roleassignmentschedulerequests?view=graph-rest-1.0&tabs=http#permissions)
> say `Read.Directory` is sufficient. The runtime error explicitly demands
> `RoleAssignmentSchedule.ReadWrite.Directory`. We therefore had to grant
> the **`ReadWrite.Directory` Graph application role** to the `pim-mcp` MI
> for the read use case to function. See `UPSTREAM_BUGS.md` in this folder.
> The MCP server itself remains read-only by construction (no write tool
> registered), but the *Entra-side permission grant* is now `ReadWrite`.
> This is documented as Residual Risk #4 below and must be raised with
> Zafin compliance before production rollout.

## Trust boundaries

```text
[Requester] --(self-service)--> [Entra PIM] <--(read, delegated)-- [Enterprise MCP (Microsoft-hosted)]
                                       ^                                          ^
                                       |                                          |
                                   [Approver]                              [Azure SRE Agent]
                                       |                              signed in as svc-pim-enablement-agent
                                       |                                          |
                                       |                              also calls (app-only)
                                       |                                          v
                                       |       [pim-mcp ACA] --(read, app)--> [Entra PIM]
                                       |       (7 read tools: list_pending_pim_requests,
                                       |        get_request_status, get_request_approver,
                                       |        list_active_role_assignments, get_user,
                                       |        get_role_definition, health)
                                       |       (Graph app roles: RoleAssignmentSchedule.{Read,ReadWrite}.Directory,
                                       |        User.Read.All, RoleManagement.Read.Directory,
                                       |        PrivilegedAccess.Read.AzureAD)
                                       v                                          |
                              (Approves in PIM portal)         (Posts Adaptive Card via Teams webhook)
                                                                                  |
                                                                                  v
                                                                      [Approver Teams channel]
```

The agent sits on the **read** side only on both paths. The approval action
is a separate flow performed by a human in the PIM portal, where Microsoft
already provides audit logging.

## What the agent CAN do

| Action | Mechanism | Risk control |
|---|---|---|
| Read pending PIM requests (`status eq 'PendingApproval'`) | **Custom `pim-mcp` Container App** → Graph (app-only via MI, 7 read tools) | MI granted `RoleAssignmentSchedule.ReadWrite.Directory` Graph app role (forced by Graph runtime — see top-of-file note) plus four narrow read scopes (`RoleAssignmentSchedule.Read.Directory`, `User.Read.All`, `RoleManagement.Read.Directory`, `PrivilegedAccess.Read.AzureAD`); the MCP server source contains no write tool, so the agent cannot exercise the write half of the scope; client-side `status == 'PendingApproval'` filter (Graph rejects `$filter` and `$orderby` on this collection) |
| Read PIM schedules / eligibilities / users / groups / licenses | Enterprise MCP → Graph (delegated, read-only scopes) | Service-account user has only `MCP.*Read.*` scopes; no write scopes granted |
| Read Jira tickets | Jira MCP (read) | Existing PoC pattern, scoped API token |
| Write Jira comments | Jira MCP (comment-only) | Audit-write only; cannot transition tickets |
| Post Teams messages | Incoming webhook URL | Webhook scoped to one channel; rotate quarterly |

## What the agent CANNOT do (by construction)

| Action | Why it can't |
|---|---|
| Approve a PIM request | Enterprise MCP server is read-only in current preview; **the custom `pim-mcp` server registers only seven read tools** (`list_pending_pim_requests`, `get_request_status`, `get_request_approver`, `list_active_role_assignments`, `get_user`, `get_role_definition`, `health`) — no write tool exists. (Note: the MI's Graph app role is `ReadWrite.Directory` because Graph runtime requires it for the LIST call, but the agent cannot reach a write code path.) |
| Deny a PIM request | Same |
| Modify a PIM eligibility | Service-account user has only read scopes; the MI **could** technically reach Graph write endpoints with its `ReadWrite.Directory` token, but the `pim-mcp` server registers no tool that would expose that capability. PR review on the server source is the control. |
| Activate roles for itself | Service account is PIM-eligible only for read-only roles (Reader, Monitoring Reader); MI has no PIM eligibilities |
| Modify Azure resources | No Azure RBAC write roles assigned to the agent MI or the service account |
| Send arbitrary Teams DMs | V1 webhook is channel-bound |

## STRIDE summary (high-level)

| Threat | Posture |
|---|---|
| Spoofing | Service account uses cert-based credential; no interactive password. Webhook URL stored as a secret in Container App config. MI uses managed credentials — no secret to leak. |
| Tampering | Bicep-deployed; immutable image tag in production. Validation rules in source-controlled YAML. `pim-mcp` source has no write code path; PR review enforced. |
| Repudiation | Two-layer audit: Microsoft Graph activity logs (filtered on Enterprise MCP `AppId = e8c77dc2-69b3-43f4-bc51-3213c9d915b4` for delegated calls, AND on the agent MI's `AppId` for app-only calls) + Jira comment per recommendation. |
| Information disclosure | Justification text redacted before posting. No PIM caching across runs. Microsoft-hosted Enterprise MCP enforces user privileges and granted scopes. `pim-mcp` returns only the fields explicitly `$select`ed. |
| Denial of service | 100 req/min/user MCP throttle is a hard ceiling on Enterprise MCP; agent backs off. `pim-mcp` polls at 60s interval. Degraded mode emits `REVIEW MANUALLY`. |
| Elevation of privilege | Agent has no write surface on PIM (neither path exposes a write tool). Cannot self-promote. Service account is not an approver. MI has no PIM eligibilities. |

## Residual risks accepted

1. **Webhook URL leak** would let an attacker post to the approver channel.
   Mitigation: rotate quarterly; treat as secret in Container App config.
2. **Rule table tampering** in repo would let a bad actor whitelist a role.
   Mitigation: PR review + branch protection on `validation-rules.yaml`.
3. **Service-account credential compromise.** Top risk introduced by the
   delegated-auth model on Enterprise MCP. Mitigation: cert-based auth,
   Conditional Access restricting sign-in to the agent's egress IPs,
   alerting on anomalous sign-ins, regular credential rotation.
4. **MI app-role over-grant (ELEVATED).** The `pim-mcp` MI holds the
   tenant-wide Graph app permission `RoleAssignmentSchedule.ReadWrite.Directory`.
   This was originally planned as `Read.Directory` only, but Graph runtime
   rejects the read-only variant for the LIST endpoint we depend on (see
   `UPSTREAM_BUGS.md`). The grant gives any code path holding the MI's token
   the *latent* ability to create/cancel PIM schedule requests at the
   directory scope. **Compensating controls:**
   - The `pim-mcp` server source registers exactly one read tool and one
     `health` tool; no write code path exists. PR review + branch protection
     on `mcp-servers/pim-mcp/**` is the primary control.
   - The MI is single-purpose (only attached to the `pim-mcp` Container App).
   - Container App ingress is restricted to the Azure SRE Agent connector subnet.
   - Container image is pinned by digest in production.
   - Microsoft Graph activity logs filtered on the MI's `AppId` will show any
     write attempt (none expected).
   - Retire the MI grant the moment Microsoft fixes the underlying scope
     gap on Graph (tracked in `UPSTREAM_BUGS.md`).

   **Banking-compliance impact:** must be raised with Zafin's identity
   governance team before production rollout. This is the single most
   important conversation to have arising from the live test.
5. **App-role propagation lag and flapping.** Newly-granted Graph
   application permissions can take 5–60 minutes (occasionally longer) to
   stabilize across Graph's resource-side claim cache. During that window
   the *same* MI request can return 200, 400, or 403 depending on which
   resource node serves it. Mitigation: deploy the MI grant as a
   pre-production step at least 1–2 hours before any demo; smoke-test
   continuously until five consecutive 200s are observed; document the
   behavior in the runbook so on-call doesn't chase a phantom auth bug.
6. **Approver complacency** — over-trusting the recommendation.
   Mitigation: card text emphasizes "human approval still required";
   approver training during rollout.
7. **Preview-status risk on both MCP paths.** Enterprise MCP is in preview;
   `pim-mcp` is custom code. Mitigation: pin Enterprise MCP behavior; pin
   `pim-mcp` image tag; smoke-test the day before any demo. Retire `pim-mcp`
   when Microsoft publishes the equivalent write scope on Enterprise MCP
   AND fixes the scope gap documented in `UPSTREAM_BUGS.md`.

## Open items

- [ ] PII redaction strategy for justification field — finalize before V1 demo.
- [ ] Log retention policy for the Jira audit comments — confirm with Zafin compliance.
- [ ] Decide whether Storage append-blob audit is required (vs Jira-only +
      Graph activity logs).
- [ ] Conditional Access policy template for the service-account user.
