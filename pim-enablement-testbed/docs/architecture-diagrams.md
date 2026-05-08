# Architecture diagrams — PIM Enablement testbed

> Visual companion to [`README.md`](../README.md). All diagrams reflect state as of **2026-05-08** (v0.6.1, Layers 1–5 green, Step 9 green, Step 10 deferred).

Diagrams in this file:

1. [System context — hybrid MCP topology](#1-system-context--hybrid-mcp-topology)
2. [Runtime request flow — agent reasoning loop](#2-runtime-request-flow--agent-reasoning-loop)
3. [Tool surface — Enterprise MCP vs `pim-mcp` coverage](#3-tool-surface--enterprise-mcp-vs-pim-mcp-coverage)
4. [VS Code partner-enablement demo — scope tiers](#4-vs-code-partner-enablement-demo--scope-tiers)
5. [Repository layout](#5-repository-layout)
6. [Validation status — by layer](#6-validation-status--by-layer)

---

## 1. System context — hybrid MCP topology

How the SRE agent talks to Microsoft Graph, where each MCP server fits, and which auth model each leg uses.

```mermaid
flowchart LR
    subgraph Tenant["Entra tenant<br/>MngEnvMCAP094150"]
        User([Approver / SRE user])
        Graph[(Microsoft Graph<br/>v1.0)]
        PIM[(PIM endpoints<br/>roleManagement/*)]
    end

    subgraph Foundry["Microsoft Foundry"]
        Agent["SRE Agent <b>aq-main</b><br/>(80-tool budget)"]
    end

    subgraph MS["Microsoft-managed"]
        EntMCP["Enterprise MCP server<br/>mcp.svc.cloud.microsoft/enterprise<br/><i>3 generic tools, delegated only</i>"]
    end

    subgraph ACA["Azure Container Apps (eastus2)"]
        PimMCP["pim-mcp 0.6.1<br/>FastMCP streamable-http /mcp<br/><i>7 tools, app-only via MI</i>"]
        MI[/User-assigned<br/>Managed Identity/]
    end

    subgraph Jira["Atlassian Cloud"]
        JiraMCP["jira-mcp"]
        SCRUM[(Jira project<br/>SCRUM)]
    end

    subgraph Obs["Observability"]
        GrafMCP["grafana-mcp"]
    end

    User -->|approves in portal| PIM
    Agent -->|hybrid: ~90% reads| EntMCP
    Agent -->|gap-filler:<br/>PendingApproval| PimMCP
    Agent -->|write-back<br/>audit trail| JiraMCP
    Agent -->|metrics / logs| GrafMCP

    EntMCP -->|delegated<br/>OBO| Graph
    PimMCP -->|app-only<br/>+ IMDS bypass_cache| MI
    MI -->|RoleAssignmentSchedule.<br/>ReadWrite.Directory| Graph
    Graph --> PIM
    JiraMCP --> SCRUM

    classDef ms fill:#0078d4,color:#fff,stroke:#005a9e
    classDef ours fill:#2e7d32,color:#fff,stroke:#1b5e20
    classDef gap fill:#c62828,color:#fff,stroke:#8e0000
    class EntMCP,Foundry,Agent,Graph,PIM ms
    class PimMCP,MI,ACA ours
```

**Read it as:** Microsoft-blue boxes are managed for us; green boxes are what we own and operate; the red `pim-mcp` exists *only* because the `roleAssignmentScheduleRequests` endpoint requires `ReadWrite` delegated permission that Enterprise MCP doesn't publish in preview ([UPSTREAM_BUGS.md BUG-001](UPSTREAM_BUGS.md)).

---

## 2. Runtime request flow — agent reasoning loop

End-to-end of the showpiece scenario: *"Are there any pending PIM requests right now? If so, recommend approve / deny and write the audit trail."*

```mermaid
sequenceDiagram
    autonumber
    actor Op as Approver
    participant FA as Foundry Agent (aq-main)
    participant EM as Enterprise MCP
    participant PM as pim-mcp (ACA)
    participant GR as Microsoft Graph
    participant JM as jira-mcp
    participant J as Jira (SCRUM)

    Op->>FA: "List pending PIM requests + recommend"
    FA->>PM: list_pending_pim_requests()
    PM->>GR: GET /roleManagement/directory/<br/>roleAssignmentScheduleRequests<br/>?$filter=status eq 'PendingApproval'
    GR-->>PM: 1 request (GUID, requester, role, justification)
    PM-->>FA: structured JSON

    FA->>EM: microsoft_graph_get(/users/{id})
    EM->>GR: GET /users/{id}
    GR-->>EM: displayName, dept, mgr
    EM-->>FA: user context

    FA->>EM: microsoft_graph_get(/roleDefinitions/{id})
    EM->>GR: GET /roleDefinitions/{id}
    GR-->>EM: role scope + privileged flag
    EM-->>FA: role context

    Note over FA: Apply validation-rules.yaml<br/>(R001–R007) → verdict + confidence

    FA->>JM: create issue + comment
    JM->>J: POST /issue, POST /comment, POST /remotelink
    J-->>JM: SCRUM-16 created
    JM-->>FA: ticket key

    FA-->>Op: Recommendation (approve, 0.92)<br/>+ Jira link

    Op->>GR: Approve in PIM portal
    Note over FA,J: Step 7c: agent re-checks status,<br/>captures approver identity,<br/>appends final audit comment to SCRUM-16
```

---

## 3. Tool surface — Enterprise MCP vs `pim-mcp` coverage

Where each PIM concept is reachable from. This is the picture that justifies the hybrid design.

```mermaid
flowchart TB
    subgraph Concepts["PIM concepts the agent needs"]
        c1[Eligibility schedules]
        c2[Active assignments]
        c3[Role definitions]
        c4[Users / org context]
        c5[<b>PendingApproval requests</b>]
        c6[Approver identity]
        c7[Audit trail / Jira]
    end

    subgraph EntMCP["via Enterprise MCP<br/>(delegated, Read.* only)"]
        e1[microsoft_graph_get]
        e2[microsoft_graph_<br/>suggest_queries]
        e3[microsoft_graph_<br/>list_properties]
    end

    subgraph PimMCP["via pim-mcp<br/>(app-only, MI)"]
        p1[list_pending_pim_requests]
        p2[get_request_status]
        p3[get_request_approver]
        p4[list_active_role_assignments]
        p5[get_user]
        p6[get_role_definition]
        p7[health]
    end

    subgraph JiraMCP["via jira-mcp"]
        j1[create / comment / remotelink]
    end

    c1 --> e1
    c2 --> e1
    c2 --> p4
    c3 --> e1
    c3 --> p6
    c4 --> e1
    c4 --> p5
    c5 -.->|❌ 403| e1
    c5 ==>|✅ only path| p1
    c6 --> p3
    c6 --> p2
    c7 --> j1

    classDef gap stroke:#c62828,stroke-width:3px,color:#c62828
    class c5,p1 gap
```

**Legend:** dotted red = blocked by upstream gap; thick green-routed arrow = the only working path. Everything else has either Enterprise MCP coverage, redundant `pim-mcp` coverage, or both.

---

## 4. VS Code partner-enablement demo — scope tiers

How [`enterprise-mcp-client-demo/`](../enterprise-mcp-client-demo/) layers MCP client scopes from "PIM read-only" up to "security-aware SRE". Each tier is opt-in via `grant-vscode-mcp-scopes.ps1 -Tier 1,2,3,4`.

```mermaid
flowchart LR
    subgraph T1["Tier 1 — PIM core (3 scopes)"]
        t1a[RoleManagement.Read.Directory]
        t1b[RoleEligibilitySchedule.Read.Directory]
        t1c[RoleAssignmentSchedule.Read.Directory]
    end

    subgraph T2["Tier 2 — identity context (4)"]
        t2a[User.Read.All]
        t2b[GroupMember.Read.All]
        t2c[LicenseAssignment.Read.All]
        t2d[Organization.Read.All]
    end

    subgraph T3["Tier 3 — SRE broadening (5)"]
        t3a[AuditLog.Read.All]
        t3b[Group.Read.All]
        t3c[Application.Read.All]
        t3d[Policy.Read.All]
        t3e[Device.Read.All]
    end

    subgraph T4["Tier 4 — security & risk (4)"]
        t4a[SecurityAlert.Read.All]
        t4b[SecurityIncident.Read.All]
        t4c[IdentityRiskyUser.Read.All]
        t4d[ServiceHealth.Read.All]
    end

    subgraph Prompts["Demo prompts"]
        p1[01 List eligible roles]
        p2[02 Active assignments]
        p3[03 Pending requests<br/><i>via pim-mcp fallback</i>]
        p4[04 Hybrid showpiece]
        p5[05 Audit-trail SRE]
        p6[06 Incident triage]
    end

    T1 --> p1
    T1 --> p2
    T1 -.->|gap| p3
    T1 --> p4
    T2 --> p4
    T3 --> p5
    T4 --> p6
```

---

## 5. Repository layout

The pieces that make up the testbed and how they relate.

```mermaid
flowchart TB
    Root["pim-enablement-testbed/"]
    Root --> RM[README.md<br/><i>top-level status</i>]
    Root --> Plan[test-plan-May-5-2026.md]
    Root --> Res[test-results-May-5-2026.md]

    Root --> MCPS["mcp-servers/<br/>pim-mcp/"]
    MCPS --> SRC[src/server.py<br/><i>FastMCP, 7 tools</i>]
    MCPS --> Df[Dockerfile]

    Root --> Inf["infra/"]
    Inf --> Bicep[pim-mcp-aca.bicep<br/><i>ACA + MI + RBAC</i>]

    Root --> Scripts["scripts/"]
    Scripts --> Trig[trigger-pim-activation.ps1]
    Scripts --> Cfg[configure-pim-approval.ps1]

    Root --> Agent["agent/"]
    Agent --> Rules[validation-rules.yaml<br/><i>R001–R007</i>]

    Root --> Demo["enterprise-mcp-client-demo/"]
    Demo --> DemoRM[README.md]
    Demo --> Vscode[vscode/mcp.json]
    Demo --> DemoScripts[scripts/<br/>discover · grant · verify]
    Demo --> DemoPrompts[prompts/01–06]
    Demo --> Trouble[troubleshooting.md]

    Root --> Docs["docs/"]
    Docs --> EntSetup[enterprise-mcp-setup.md]
    Docs --> ToolsRef[pim-tools-via-enterprise-mcp.md]
    Docs --> Bugs[UPSTREAM_BUGS.md]
    Docs --> Threat[threat-model.md]
    Docs --> DeployRB[deployment-runbook.md]
    Docs --> DemoSc[demo-script.md]
    Docs --> Diag[<b>architecture-diagrams.md</b><br/><i>← you are here</i>]

    classDef here fill:#fff59d,stroke:#f57f17,color:#000
    class Diag here
```

---

## 6. Validation status — by layer

State machine of what's proven, what's deferred, and what's optional.

```mermaid
stateDiagram-v2
    [*] --> L1
    L1: Layer 1 — gap-filler infra<br/>pim-mcp 0.6.1 on ACA · 7 tools · MI
    L2: Layer 2 — Graph plumbing<br/>test users · eligibility · approval policy
    L12: Layer 1↔2 chain<br/>PendingApproval reachable
    L3: Layer 3 — Foundry wiring<br/>pim-mcp + jira-mcp + grafana-mcp
    L4: Layer 4 — agent reasoning<br/>R001–R007 · prompts 5a/5b/6/8
    L5: Layer 5 — latency loop<br/>warm p95 6.25s · cold 10.5s
    S7: Step 7 — full approver flow<br/>approve → status flip → audit
    S9: Step 9 — Jira write-back<br/>SCRUM-16 two-comment trail
    S10: Step 10 — Foundry trace ⏸<br/><i>deferred (optional)</i>

    L1 --> L2: ✅
    L2 --> L12: ✅
    L12 --> L3: ✅
    L3 --> L4: ✅
    L4 --> L5: ✅*
    L4 --> S7: ✅
    S7 --> S9: ✅
    S9 --> S10: ⏸
    S10 --> [*]: not required for Zafin<br/>(audit need met by Jira trail)
```

`✅*` = passes for warm path; cold-start above 5s threshold — mitigation is `min-replicas=1` for the demo.

---

## Maintenance

When updating these diagrams:

- Keep the [README.md](../README.md) `## Current state` table and the [Validation status](#6-validation-status--by-layer) state machine in sync.
- When `pim-mcp` adds or removes a tool, update both the [Tool surface](#3-tool-surface--enterprise-mcp-vs-pim-mcp-coverage) flowchart and the [System context](#1-system-context--hybrid-mcp-topology) tool count.
- New scope tiers go in section 4 and must also be reflected in [`enterprise-mcp-client-demo/scripts/grant-vscode-mcp-scopes.ps1`](../enterprise-mcp-client-demo/scripts/grant-vscode-mcp-scopes.ps1).

Render check: GitHub renders Mermaid natively in markdown; VS Code preview needs the built-in Markdown Preview Mermaid Support (enabled by default in 1.85+).
