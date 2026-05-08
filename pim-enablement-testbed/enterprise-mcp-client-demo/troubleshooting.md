# Enterprise MCP Client Demo — Troubleshooting

## "Invalid scopes (not available on resource)"

**Cause:** scope name doesn't match what the MCP Server SP currently publishes. Microsoft adds and renames scopes during preview.

**Fix:**

```powershell
./scripts/discover-mcp-scopes.ps1
```

Compare its output to `$Tier1`/`$Tier2`/`$Tier3` in `grant-vscode-mcp-scopes.ps1`. Edit the array(s) to match exactly, then re-run the grant.

---

## 401 / consent prompt loops

**Cause:** scopes were granted to a different client app (e.g. a custom registration) but VS Code is signing in as its built-in client.

**Fix:** confirm grants are on `VisualStudioCode`:

```powershell
Get-EntraBetaMCPServerPermission -ApplicationName 'VisualStudioCode'
```

If empty, re-run `grant-vscode-mcp-scopes.ps1`.

---

## VS Code MCP server stuck "Starting"

**Symptoms:** the `enterprise-mcp` or `pim-mcp` entry in Copilot Chat's tools picker shows "Starting…" forever.

**Fixes (try in order):**

1. **Reload window** (`Cmd+Shift+P` → `Developer: Reload Window`).
2. **Check VS Code MCP output channel** (`View → Output → MCP`).
3. **Verify URL reachability** outside VS Code: `curl -I https://mcp.svc.cloud.microsoft/enterprise` (expect 4xx, not connection refused).
4. **For pim-mcp**: cold start can take 10+ seconds (per Layer 5 latency capture). Wait, then retry.

---

## "PIM data not visible — license required"

**Cause:** signed-in user lacks Entra ID P2.

**Fix:** assign P2 (or sign in as a user that has it). Verify with:

> Using enterprise-mcp, show me the licenses assigned to `<my-upn>`.

(Requires Tier 2 `MCP.LicenseAssignment.Read.All`.)

---

## MFA / Conditional Access loop

**Cause:** the tenant's CA policy requires interactive MFA and VS Code's silent token cache can't satisfy it.

**Fix:** sign out of VS Code's account (`Accounts` icon, bottom-left), sign back in, complete MFA, re-issue the prompt.

---

## Hybrid prompt (`04-hybrid-pending.md`) doesn't fall back to pim-mcp

**Cause:** the agent gave up after Enterprise MCP's permission error instead of trying the alternative.

**Fix:** re-prompt with explicit fallback hint:

> If enterprise-mcp can't serve this read, use `pim-mcp.list_pending_pim_requests` instead. Both servers are wired in this workspace.

Long-term: encode the fallback into a workspace `.github/copilot-instructions.md` so it's automatic.

---

## Token-cache poisoning ("works after reload, fails an hour later")

**Cause:** delegated tokens cached in the OS keychain (macOS) can outlive scope changes — especially after re-running `grant-vscode-mcp-scopes.ps1` to add Tier 3.

**Fix (macOS):** Keychain Access → search `microsoft` → delete entries for `login.microsoftonline.com` related to VS Code → reload VS Code → sign in fresh.

---

## "I want to revoke everything"

```powershell
$names = @(
    'MCP.RoleManagement.Read.Directory',
    'MCP.RoleEligibilitySchedule.Read.Directory',
    'MCP.RoleAssignmentSchedule.Read.Directory',
    'MCP.User.Read.All',
    'MCP.GroupMember.Read.All',
    'MCP.LicenseAssignment.Read.All',
    'MCP.Organization.Read.All',
    'MCP.AuditLog.Read.All',
    'MCP.Group.Read.All',
    'MCP.Application.Read.All',
    'MCP.Policy.Read.All',
    'MCP.Device.Read.All'
)
Revoke-EntraBetaMCPServerPermission -ApplicationName 'VisualStudioCode' -Scopes $names
```
