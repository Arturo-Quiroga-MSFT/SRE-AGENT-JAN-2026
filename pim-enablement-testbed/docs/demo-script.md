# PIM Enablement — Demo Script

> Mid-June 2026 internal demo · End-of-June customer demo
> ~10 minutes total

## Setup (do once before demo)

1. Deploy infra: `azd up` (or `az deployment sub create -f infra/main.bicep`).
2. Grant Graph perms to the agent MI: `pwsh scripts/grant-graph-perms.ps1` (TODO).
3. Seed test users + groups: `pwsh scripts/seed-test-users.ps1`.
4. Configure Azure SRE Agent with `agent/knowledge.md` and the three MCP endpoints.
5. Validate end-to-end with `scripts/verify-deployment.sh`.

## Demo flow

### Scene 1 — Set the stage (1 min)

> "Zafin's SREs activate privileged access multiple times a day. Approvers
> manually validate ticket exists, requester is on-call, role/scope is in
> the allow-list. We'll let an agent do the validation work. The human
> still approves in PIM."

Show the Teams approver channel (empty).

### Scene 2 — Happy path (3 min)

1. Run `scripts/trigger-pim-request.sh` with a properly-formed request.
2. Within 60 seconds, an Adaptive Card appears in the approver channel.
3. Walk through the card:
   - Requester + role + scope + ticket
   - Validation checklist — all green
   - Verdict: `ELIGIBLE` · Confidence: `High` · Recommended: `Approve`
4. Open the Jira ticket — show the audit comment.
5. Click "Open in PIM Portal" and approve. **The human is still in the loop.**

### Scene 3 — Failure path A: ticket not found (2 min)

1. Trigger with `TICKET_NUMBER=INC-DOES-NOT-EXIST`.
2. Card shows R001 failed — terminal hard rule.
3. Verdict: `NOT ELIGIBLE` · Recommended: `Deny`.
4. Show how the rationale points to the missing ticket.

### Scene 4 — Failure path B: requester not in on-call group (2 min)

1. Trigger from a user not in any approved group.
2. Card shows R001–R003 pass, R004 fails.
3. Verdict: `NOT ELIGIBLE` · Recommended: `Deny`.

### Scene 5 — Failure path C: degraded inputs (1 min)

1. Stop the Jira MCP container.
2. Trigger an activation.
3. Card shows `REVIEW MANUALLY` with the failure reason.
4. Show that the Jira audit comment still appears (best-effort) noting
   the degraded state.

### Scene 6 — Wrap (1 min)

- Recap the compliance posture: agent never approves; final action stays
  in the PIM portal.
- Show the validation rule file — Zafin owns the content, we own the engine.
- Tease V2: Graph change notifications, per-user attribution via
  `chats/messages`, optional Storage append-blob audit.

## Talking points to keep ready

- "Why polling for V1?" — De-risk the schedule. Webhook integration is
  scope-confirmable but slower to land.
- "Why webhook for Teams V1?" — Lowest friction. V2 moves to per-user
  attribution.
- "Where do the rules come from?" — Zafin policy. We supply the schema
  and engine; they supply the content.
- "Can the agent ever escalate to writes?" — Not in this design. The
  PIM MCP server has no write tools. By construction.
