# Enterprise MCP — VS Code Client Demo

> **Goal:** give a Zafin (or other partner) engineer a 10-minute path from
> nothing → talking to the Microsoft-hosted MCP server from VS Code Copilot
> Chat, asking PIM and identity questions in natural language, and seeing
> the **hybrid architecture** in action (Enterprise MCP + our gap-filler
> `pim-mcp` working together).
>
> **Status (2026-05-08):** scaffold complete; live walk-through pending.

---

## Why VS Code as the client?

| Reason | Detail |
|---|---|
| **First-class support** | Microsoft Learn lists VS Code / GH Copilot CLI as supported clients with a pre-registered VS Code client app — no app registration needed for the demo. |
| **Delegated OAuth works out-of-box** | VS Code's MCP support handles the auth-code flow + token refresh natively. No Foundry-wizard limitation to work around. |
| **Zero infra** | One `.vscode/mcp.json` entry plus a one-time scope grant. |
| **Partner already has it** | Zafin engineers use VS Code daily — lowest friction surface. |
| **Demo optics** | Copilot Chat reasoning over real Graph/PIM data live is more visceral than a curl response. |

The Foundry connector path for Enterprise MCP is still blocked by the OAuth-delegated wizard gap (testbed README "Day 2 roadblock removers" #3), so VS Code is genuinely the cleanest client today, not just a pedagogical choice.

---

## Prerequisites

Confirm before starting:

- [ ] **VS Code** ≥ 1.99 with MCP support enabled (`"chat.mcp.enabled": true`)
- [ ] **GitHub Copilot Chat** extension installed and signed in
- [ ] **PowerShell 7+** with `Microsoft.Entra.Beta` ≥ 1.0.13 installed
- [ ] **Tenant admin** willing to grant the one-time MCP scopes (or pre-arranged delegation)
- [ ] **Entra ID P2** license on the user account used to sign in (required for PIM data)
- [ ] **One-time tenant provisioning** already done per [`../docs/enterprise-mcp-setup.md`](../docs/enterprise-mcp-setup.md) §"One-time tenant provisioning" Step 1 (MCP Server SP exists in the tenant)

---

## Recommended scope set

We define **four tiers**. Tier 1 + 2 are the PIM-Enablement minimum. Tier 3 broadens the agent from PIM-only into general identity-aware SRE. Tier 4 adds security-signal context (Defender, Identity Protection, service health) that turns the same agent into a first-pass incident triager.

> **Verified live 2026-05-08:** all 17 scope names below are published and enabled on the MCP Server SP in tenant `MngEnvMCAP094150` (40 published scopes total). Run [`scripts/discover-mcp-scopes.ps1`](scripts/discover-mcp-scopes.ps1) to re-verify in any other tenant before granting.

### Tier 1 — PIM core (required for the testbed)

| Scope | Why we need it |
|---|---|
| `MCP.RoleManagement.Read.Directory` | Read role definitions ("what is `Privileged Role Administrator`?") |
| `MCP.RoleEligibilitySchedule.Read.Directory` | Read who is *eligible* to activate which role |
| `MCP.RoleAssignmentSchedule.Read.Directory` | Read currently *active* role holders + expiry timestamps |

### Tier 2 — Identity context (required for triage)

| Scope | Why we need it |
|---|---|
| `MCP.User.Read.All` | Resolve OIDs ↔ UPNs ↔ display names for the requester / approver |
| `MCP.GroupMember.Read.All` | "Is the requester in the approved-requesters group?" |
| `MCP.LicenseAssignment.Read.All` | Confirm Entra ID P2 is present (PIM precondition check) |
| `MCP.Organization.Read.All` | Tenant-level metadata + branding |

### Tier 3 — SRE / audit broadening (recommended for Zafin)

| Scope | Why it pays off |
|---|---|
| `MCP.AuditLog.Read.All` | Sign-in logs + directory audits — central to RCA ("did this user actually sign in around the incident time?") |
| `MCP.Group.Read.All` | Full group metadata (not just members) — useful for ownership / dynamic-membership reasoning |
| `MCP.Application.Read.All` | App registration / service principal context — needed for app-tier RCA ("which SP made this Graph call?") |
| `MCP.Policy.Read.All` | Conditional Access + auth-method policies — answers "why was this user blocked?" |
| `MCP.Device.Read.All` | Intune-managed device posture — answers "is the requester on a compliant device?" |

### Tier 4 — Security & Risk (incident triage)

| Scope | Why it pays off |
|---|---|
| `MCP.SecurityAlert.Read.All` | Defender alerts in agent context — direct RCA fuel for active incidents |
| `MCP.SecurityIncident.Read.All` | Defender XDR correlated incidents (alerts grouped by attack story) |
| `MCP.IdentityRiskyUser.Read.All` | Identity Protection "is this requester flagged risky?" |
| `MCP.ServiceHealth.Read.All` | "Is this an Azure-side outage before we escalate to the app team?" |

---

## Walkthrough (10 min)

### Step 1 — Discover live-published scopes (3 min)

```powershell
./scripts/discover-mcp-scopes.ps1
```

Outputs a table of all enabled, non-private published scopes on the MCP Server SP. Save the output — you'll cross-check Tier 3 names against it before granting.

### Step 2 — Grant scopes to the VS Code built-in client (2 min)

```powershell
./scripts/grant-vscode-mcp-scopes.ps1 -Tier 1,2,3,4
```

`-Tier 1,2` for PIM-only minimum; `-Tier 1,2,3` for SRE broadening; `-Tier 1,2,3,4` for the full security-aware set. The script uses `Grant-EntraBetaMCPServerPermission -ApplicationName VisualStudioCode` so no app registration is needed.

### Step 3 — Wire the MCP servers into VS Code (1 min)

Copy [`vscode/mcp.json`](vscode/mcp.json) into your workspace's `.vscode/mcp.json` (or merge with an existing one). Reload VS Code. Open Copilot Chat → Agent Mode → confirm both servers (`enterprise-mcp` and `pim-mcp`) appear in the tools picker.

The first call to `enterprise-mcp` triggers a browser sign-in; consent to the scopes.

### Step 4 — Verify (1 min)

```powershell
./scripts/verify-mcp-token.ps1
```

Acquires a token for `api://e8c77dc2-69b3-43f4-bc51-3213c9d915b4/.default` and pings the MCP endpoint to prove auth + transport.

### Step 5 — Run the demo prompts (3 min)

Open Copilot Chat (Agent Mode) and run the prompts in [`prompts/`](prompts/) in order:

| # | Prompt | Tools exercised | What it proves |
|---|---|---|---|
| 1 | [`01-list-eligible-roles.md`](prompts/01-list-eligible-roles.md) | `enterprise-mcp.microsoft_graph_get` | Tier 1 scopes work |
| 2 | [`02-active-assignments.md`](prompts/02-active-assignments.md) | same | Read-only PIM disposition path |
| 3 | [`03-role-policy.md`](prompts/03-role-policy.md) | same | Approval policy reasoning |
| 4 | [`04-hybrid-pending.md`](prompts/04-hybrid-pending.md) | `enterprise-mcp` *and* `pim-mcp.list_pending_pim_requests` | **Hybrid architecture in action** — the showpiece |
| 5 | [`05-signin-rca.md`](prompts/05-signin-rca.md) | `enterprise-mcp` (Tier 3) | SRE broadening — only works if Tier 3 granted |
| 6 | [`06-incident-triage.md`](prompts/06-incident-triage.md) | `enterprise-mcp` (Tier 4) | Security incident triage — only works if Tier 4 granted |

---

## What this demo is NOT

- **Not a write path.** Enterprise MCP is read-only in the current preview, by design. Writes (approve, deny, activate) stay in the PIM portal. This aligns with the banking-compliance posture documented in [`../README.md`](../README.md).
- **Not a Foundry-agent path.** This is a developer-facing tool for exploration and partner enablement. The production agent path is the SRE Agent `aq-main` configured per the parent testbed README.
- **Not a substitute for production identity hygiene.** The VS Code built-in client app is fine for an interactive engineer at the keyboard. Production unattended scenarios still need a service-account user (per [`../docs/enterprise-mcp-setup.md`](../docs/enterprise-mcp-setup.md) §"Per-environment configuration").

---

## Troubleshooting

See [`troubleshooting.md`](troubleshooting.md) for: 401 / scope not consented, "scope not published", token-cache poisoning, MFA loop, VS Code MCP server stuck "starting".

---

## Files in this folder

```
enterprise-mcp-client-demo/
├── README.md                         # This file
├── vscode/
│   └── mcp.json                      # Drop-in .vscode/mcp.json (Enterprise MCP + pim-mcp)
├── scripts/
│   ├── discover-mcp-scopes.ps1       # Lists all live-published MCP.* scopes
│   ├── grant-vscode-mcp-scopes.ps1   # Grants tiered scopes to the VS Code client app
│   └── verify-mcp-token.ps1          # Acquires token + pings endpoint
├── prompts/
│   ├── 01-list-eligible-roles.md
│   ├── 02-active-assignments.md
│   ├── 03-role-policy.md
│   ├── 04-hybrid-pending.md          # The hybrid showpiece
│   ├── 05-signin-rca.md              # Tier 3 only
│   └── 06-incident-triage.md         # Tier 4 only
└── troubleshooting.md
```
