# Prompt 05 — Sign-in RCA (Tier 3 only)

**Tier required:** 3 (`MCP.AuditLog.Read.All`) — verify name with `discover-mcp-scopes.ps1` first

**Tools expected:** `enterprise-mcp.microsoft_graph_get`

## Prompt

> Using enterprise-mcp, show me all sign-in attempts by `pim-requester@MngEnvMCAP094150.onmicrosoft.com` in the last 24 hours. For each, show the timestamp, IP address, app, conditional access result, MFA result, and final status. Highlight any failed sign-ins.

## What success looks like

- Agent queries `/auditLogs/signIns?$filter=...`.
- Returns a table sorted by timestamp.
- For Zafin: this is the kind of answer their SRE today gets by querying Log Analytics manually — one prompt replaces that.

## Why this matters for Zafin

Per [`ZAFIN_GAP_ANALYSIS_MARCH_2026.md`](../../../partner-context/ZAFIN_GAP_ANALYSIS_MARCH_2026.md) §"Step 2b — Application Context Agent", incident triage needs identity context (release version, dependency health, *who was active*). Sign-in logs are the core of that. Tier 3 unlocks it without standing up a separate Log Analytics workspace.

## Common failure modes

- **403 Forbidden** → Tier 3 scope name is wrong for this tenant. Re-run `discover-mcp-scopes.ps1` and edit `grant-vscode-mcp-scopes.ps1` `$Tier3` array.
- **Empty result** → user simply hasn't signed in. Try `pim-approver` instead, or any user known to be active.
