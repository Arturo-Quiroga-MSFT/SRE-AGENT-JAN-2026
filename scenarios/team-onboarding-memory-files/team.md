## Team

### Microsoft (PSA Team)
- **Arturo Quiroga** — Partner Solutions Architect, repo owner, primary author of PoC docs/architecture/testbed
- **Deepthi Chelupati** — Original author of grocery-sre-demo (base application)
- **Ankit** — PSA team, helps Arturo with Azure AI services

### Zafin (Partner)
- **Zoya** — Tasked with making SRE Agent work for Zafin's organization
- **Jijo** — Tasked with making SRE Agent work for Zafin's organization
- **George Mathew** — Zafin stakeholder, goal: "a few hundred users" before public reference

## Engagement Model
- Weekly working sessions with the partner (Zafin)
- Multiple scenarios being proved out for the partner engagement
- Current focus: **team onboarding when connecting the agent to a GitHub repo** (Use Case #2 from Zafin)
- Long-term goal: Build trust through human-in-the-loop → eventually T1 autonomous runbook execution
- **Next meeting (week of April 6, 2026):** Zafin to share current state, blockers, what help they need, how they want to empower their engineers with the onboarding scenario, and more details about their codebase

## Scenarios Being Proved Out
1. **Rate limit incident response** (429 from supplier API) — working, demonstrated
2. **Service degradation detection** (5xx, CPU/memory) — documented, ready to demo
3. **Team onboarding via GitHub repo connection** — current focus, in progress now
4. **ServiceNow integration** — scenario documented

## Project Purpose
Azure SRE Agent PoC — demonstrating SRE Agent capabilities to partners/customers. Dual purpose:
1. Partner demos and scenario validation
2. Finding bugs and pushing improvements upstream (see BUG_REPORT_FOR_UPSTREAM.md)

## Known Issues
- Jira MCP connector: recurring API token auth failures (blocks ticket creation)
- Knowledge base files: sometimes not visible in UI (known platform bug as of April 2026)
- Repository connector: can stay in "Pending" state (known indexing issue)
