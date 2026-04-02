---
title: "AI Governance: Model Selection and Data Handling in Azure SRE Agent"
description: "Research and findings on AI model providers, data flows, and compliance considerations for Azure SRE Agent deployments"
author: Arturo Quiroga
ms.date: 2026-04-02
ms.topic: reference
keywords: [azure-sre-agent, anthropic, claude, data-privacy, compliance, ai-governance]
---

## Overview

Azure SRE Agent supports two AI model providers to power its investigation, incident
response, and operational automation capabilities: Anthropic (Claude models) and
Azure OpenAI. This directory documents research findings on how model selection
affects data flows, compliance posture, and available AI guardrails.

Understanding these distinctions matters for any team operating the SRE Agent with
sensitive workload telemetry, proprietary log data, or strict data residency
requirements.

## Contents

| File | Description |
|---|---|
| [model-data-handling.md](model-data-handling.md) | What data is sent to the AI provider, how Anthropic operates as a Microsoft subprocessor, and comparison of the two provider options |
| [anthropic-usage-policy.md](anthropic-usage-policy.md) | Summary of Anthropic's Usage Policy (AUP) and Privacy Policy for API customers, with the key distinctions for enterprise usage |

## Key Findings at a Glance

Azure SRE Agent routes inference through either Anthropic or Azure OpenAI depending on
configuration. For most commercial regions, Anthropic (Claude Opus 4.6) is the default.

When Anthropic is active:

- Inference happens in Anthropic's infrastructure, not within Azure
- Data flows: prompts, conversation history, tool call inputs/outputs, system instructions,
  and any attached context are all sent to Anthropic for each inference call
- Azure credentials and bearer tokens are NOT included in the inference payload
- Anthropic operates as a Microsoft-contracted subprocessor under the Microsoft DPA
- Data is not used to train Anthropic models (contractual guarantee via Microsoft enterprise agreement)

When Azure OpenAI is active:

- All inference stays within Azure infrastructure
- Azure RAI guardrails (Prompt Shields, content filtering, groundedness detection) apply natively
- EU Data Boundary commitments are met
- The Microsoft DPA fully covers all data processing

## References

- [Anthropic as a subprocessor in Azure SRE Agent](https://learn.microsoft.com/azure/sre-agent/anthropic-sub-processor)
- [Data residency and privacy in Azure SRE Agent](https://learn.microsoft.com/azure/sre-agent/data-privacy)
- [Azure SRE Agent FAQ](https://learn.microsoft.com/azure/sre-agent/faq)
- [Microsoft Data Protection Addendum (DPA)](https://www.microsoft.com/licensing/docs/view/Microsoft-Products-and-Services-Data-Protection-Addendum-DPA)
- [Microsoft Subprocessor List (Service Trust Portal)](https://aka.ms/subprocessor)
- [Anthropic Usage Policy](https://www.anthropic.com/legal/aup)
- [Anthropic Privacy Policy](https://www.anthropic.com/legal/privacy)
