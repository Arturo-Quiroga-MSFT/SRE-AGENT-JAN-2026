---
title: "Azure SRE Agent: AI Model Selection, Data Flows, and Provider Comparison"
description: "Technical reference covering what data is sent to the AI inference provider, how Anthropic operates as a Microsoft subprocessor, and guidance on switching to Azure OpenAI"
author: Arturo Quiroga
ms.date: 2026-04-02
ms.topic: reference
keywords: [azure-sre-agent, anthropic, claude, azure-openai, data-privacy, subprocessor]
---

## Background

Azure SRE Agent lets you choose between two AI model providers at the agent settings
level. The choice determines where inference happens, what compliance commitments apply,
and which AI safety guardrails are in scope.

This document captures the findings from direct research against the SRE Agent portal,
Microsoft's official docs, and Anthropic's published policies.

## How Model Selection Works

You configure the active provider in the SRE Agent portal:

1. Navigate to [sre.azure.com](https://sre.azure.com)
2. Select your agent resource
3. Go to **Settings** > **AI Model Provider**
4. View or change the active provider

The two options are:

- **Anthropic** (Claude Opus 4.6): default for most commercial regions (US, APAC, etc.)
- **Azure OpenAI**: default for EU, EFTA, and UK regions; the only option in government/sovereign clouds

Neither option requires changes to connectors, MCP servers, or sub-agent configuration.
The switch takes effect immediately.

### Regional defaults

| Region | Default Provider | Notes |
|---|---|---|
| Most commercial regions (US, APAC, etc.) | Anthropic | No data residency restrictions |
| EU, EFTA, and UK | Azure OpenAI | Anthropic available as opt-in |
| Government clouds (GCC, GCC High, DoD) | Azure OpenAI | Anthropic not available |

## What the SRE Agent Sends to the AI Provider

The SRE Agent itself discloses this when asked directly. The following data is included
in each inference call, regardless of which provider is active:

| Data Type | Description |
|---|---|
| **Your prompt/message** | The text submitted in the conversation |
| **Conversation history** | Prior messages in the current thread for context continuity |
| **Tool call inputs and outputs** | When the agent invokes tools (az CLI, Grafana/Loki queries, Jira API calls), both the request parameters and the results are included in the context sent for the next inference call |
| **System instructions** | The agent's configuration: system prompts, sub-agent instructions, skill directives, and any workspace context such as synthesized knowledge files and resource IDs |
| **Attached context** | Code references, file contents, or search results pulled into the session |

### What is NOT sent

- Raw Azure credentials or bearer tokens: the agent runtime handles authentication
  server-side via Managed Identity; tokens are not passed through the LLM context
- Data from previous, unrelated conversation threads (unless persisted in synthesized
  knowledge files that get loaded into context)

### Practical implication for workload telemetry

Because tool call inputs and outputs are included in the inference payload, any data
returned by tools ends up in the context sent to the AI provider. In a typical SRE
investigation, this includes:

- Loki/Grafana log query results (potentially containing application error messages,
  stack traces, and service names)
- Azure Monitor metrics and alert data
- Jira ticket contents
- Azure resource metadata returned by ARM/CLI calls

This is expected behavior for an AI agent to reason over evidence. Teams should be
aware that this operational telemetry is part of the inference payload.

## Anthropic as a Microsoft Subprocessor

When Anthropic is the active provider, it operates as a **Microsoft-contracted
subprocessor**, not as an independent third party receiving your data.

The legal chain is:

```
Your Organization
    → Microsoft (data controller, Azure SRE Agent)
        → Anthropic (subprocessor, acting under Microsoft's direction)
```

The governing documents are:

- [Microsoft Data Protection Addendum (DPA)](https://www.microsoft.com/licensing/docs/view/Microsoft-Products-and-Services-Data-Protection-Addendum-DPA):
  contractually binds Anthropic to data handling obligations
- [Microsoft Product Terms](https://www.microsoft.com/licensing/terms): apply to all
  Azure service usage
- [Microsoft Subprocessor List](https://aka.ms/subprocessor): Anthropic is listed as a
  named subprocessor under the enterprise agreement

### Contractual data handling guarantees (via Microsoft DPA)

- Anthropic processes data under Microsoft's direction and contractual safeguards
- Neither Microsoft nor Anthropic uses your data to train AI models
- Data is isolated by tenant and Azure subscription
- Technical and organizational security measures are in place

### What the Microsoft DPA does NOT cover

- **EU Data Boundary**: Anthropic is not covered by Microsoft's EU Data Boundary
  commitments. When Anthropic is active, data (prompts, responses, and resource
  analysis) may be processed in the United States, even if your SRE Agent is deployed
  in an EU region
- **Azure RAI guardrails**: Anthropic inference bypasses Azure Content Safety, Prompt
  Shields, and groundedness detection. Claude has its own built-in safety behaviors,
  but these are not the same as Azure's configurable content filtering layer

## Provider Comparison

| Capability | Anthropic (Claude Opus 4.6) | Azure OpenAI |
|---|---|---|
| Inference location | Anthropic infrastructure | Azure infrastructure |
| EU Data Boundary | Not covered | Covered |
| Government/sovereign clouds | Not available | Available |
| Microsoft DPA applies | Yes (as subprocessor) | Yes (natively) |
| No training on your data | Yes (contractual) | Yes (contractual) |
| Azure Content Safety / Prompt Shields | No | Yes |
| Azure RAI content filtering | No | Yes |
| Model capability (complex reasoning) | Claude Opus 4.6 (strong) | GPT-4o / o3 (strong) |

## Switching to Azure OpenAI

Switching provider keeps the rest of the agent configuration intact. No connector,
sub-agent, or knowledge file changes are needed.

1. Go to [sre.azure.com](https://sre.azure.com)
2. Select your agent
3. **Settings** > **AI Model Provider** > select **Azure OpenAI**
4. Save

With Azure OpenAI active, all inference stays within Azure and the full Azure
Responsible AI stack applies.

## Option: Claude on Azure-Hosted Infrastructure

If the business requirement is specifically to use Claude models while keeping all
inference within Azure, a separate path exists through **Azure AI Foundry**. Claude
models (including Opus 4.6, Sonnet 4.6, Haiku 4.5) are available as Global Standard
deployments in Foundry. When accessed via Foundry, inference runs within Azure
infrastructure and is subject to Azure's compliance framework.

This path requires building a custom agent using the Microsoft Agent Framework (MAF)
with the `AnthropicFoundryClient`. The Azure SRE Agent's built-in model provider
setting does not currently support pointing to a custom Foundry Claude deployment.

### Quota note

Claude models in Azure Foundry currently require an Enterprise or MCA-E subscription.
Standard pay-as-you-go subscriptions have a default quota of 0 TPM for Claude models.

References:

- [Deploy and use Claude models in Microsoft Foundry](https://learn.microsoft.com/azure/foundry/foundry-models/how-to/use-foundry-models-claude)
- [MAF Anthropic agent (Python)](https://learn.microsoft.com/agent-framework/agents/providers/anthropic)
- [MAF Anthropic agent (C#)](https://learn.microsoft.com/agent-framework/agents/providers/anthropic)
