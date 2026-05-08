# Prompt 06 — Security incident triage (Tier 4 only)

**Tier required:** 4 (`MCP.SecurityAlert.Read.All`, `MCP.SecurityIncident.Read.All`, `MCP.IdentityRiskyUser.Read.All`, `MCP.ServiceHealth.Read.All`)

**Tools expected:** `enterprise-mcp.microsoft_graph_get`

## Prompt

> I'm investigating a possible incident around the time `pim-requester@MngEnvMCAP094150.onmicrosoft.com` activated `Privileged Role Administrator` today. Using enterprise-mcp:
>
> 1. List any open Defender XDR incidents from the last 24 hours.
> 2. List any high-severity security alerts from the last 24 hours involving that user.
> 3. Tell me whether that user is currently flagged in Identity Protection (`riskyUsers`).
> 4. Check Microsoft 365 Service Health for any active issues affecting Entra ID or PIM in the last 24 hours.
>
> Then summarize: is there evidence this PIM activation correlates with a security signal, or does it look like a clean elevation?

## What success looks like

- Agent fans out to four Graph endpoints (`/security/incidents`, `/security/alerts_v2`, `/identityProtection/riskyUsers`, `/admin/serviceAnnouncement/healthOverviews`).
- Final answer is a short evidence-based verdict, not a JSON dump — e.g., *"No correlated security signal: 0 incidents, 0 alerts touching this UPN, user not in `riskyUsers`, no Entra/PIM service-health events. Activation appears clean."*
- For Zafin: this is the first-pass triage their on-call SRE does manually today, replaced by one prompt.

## Why this matters for Zafin

Per [`ZAFIN_GAP_ANALYSIS_MARCH_2026.md`](../../../partner-context/ZAFIN_GAP_ANALYSIS_MARCH_2026.md) §"Step 4 — SRE Analysis Agent" (*"analyzes debug bundle + live telemetry; proposes mitigation"*), the triage agent needs security-signal context, not just config state. Tier 4 closes that gap without standing up a Defender API client or a separate Sentinel workspace integration.

## Common failure modes

- **403 on `/security/incidents`** → tenant lacks Defender XDR licensing. Fall back to `/security/alerts_v2` only; note the limitation.
- **Empty results across the board** → genuinely a quiet tenant. Try the prompt again after triggering a known-test alert (e.g., simulate a risky sign-in).
- **`/admin/serviceAnnouncement/...` 403** → service-health requires `MCP.ServiceMessage.Read.All` *and* `MCP.ServiceHealth.Read.All` in some tenants. Re-run grant with both.
