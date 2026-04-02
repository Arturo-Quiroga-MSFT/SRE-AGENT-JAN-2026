---
title: "Anthropic Usage Policy and Privacy Policy: Enterprise API Customer Reference"
description: "Summary of Anthropic's AUP and Privacy Policy with the critical distinctions between consumer accounts and enterprise API customers processed under the Microsoft DPA"
author: Arturo Quiroga
ms.date: 2026-04-02
ms.topic: reference
keywords: [anthropic, usage-policy, privacy-policy, api, enterprise, microsoft-dpa]
---

## Overview

Anthropic publishes two primary legal documents relevant to API usage:

- [Usage Policy (AUP)](https://www.anthropic.com/legal/aup) (effective September 15, 2025):
  governs what you can build and what behaviors are prohibited
- [Privacy Policy](https://www.anthropic.com/legal/privacy) (effective January 12, 2026):
  governs how Anthropic collects, processes, and stores personal data

For teams using Claude through Azure SRE Agent, there is a critical distinction that
affects which of these policies applies.

## The Critical Distinction: Consumer vs. Enterprise/API

The Anthropic Privacy Policy explicitly scopes itself to consumer use:

> "This Privacy Policy does not apply where Anthropic acts as a data processor and
> processes personal data on behalf of commercial customers. In those cases, the
> commercial customer is the controller, and you can review their policies for more
> information about how they handle your personal data."

When Azure SRE Agent calls Anthropic:

- Anthropic is the **data processor** (executing inference on behalf of Microsoft)
- Microsoft is the **data controller** (the responsible party under the enterprise agreement)
- Your data is governed by the **Microsoft DPA**, not Anthropic's consumer Privacy Policy

This means the training opt-out and data retention terms in Anthropic's consumer policy
are not the document to cite for enterprise API usage. The guarantees come from the
Microsoft enterprise agreement and [Microsoft DPA](https://www.microsoft.com/licensing/docs/view/Microsoft-Products-and-Services-Data-Protection-Addendum-DPA).

## Anthropic's Usage Policy (AUP)

The AUP applies to all users, including API customers. It defines:

### Universal Usage Standards

Applies to all users and use cases. Prohibits:

- Illegal activity or violation of applicable laws
- Compromising critical infrastructure (power grids, water, healthcare systems)
- Compromising computer or network systems (unauthorized vulnerability discovery,
  malware creation, denial-of-service tools)
- Developing or designing weapons (biological, chemical, radiological, nuclear,
  or conventional weapons of mass harm)
- Inciting violence or hateful behavior
- Compromising privacy or identity rights (unauthorized collection of biometric,
  health, or confidential data)
- Generating child sexual abuse material
- Creating psychologically or emotionally harmful content (self-harm promotion,
  harassment, bullying)
- Creating or spreading misinformation
- Undermining democratic processes
- Criminal justice, censorship, or surveillance applications
- Fraudulent, abusive, or predatory practices
- Explicit sexual content

### High-Risk Use Case Requirements

For use cases in domains with elevated risk of harm, Anthropic requires:

- A qualified human professional reviews outputs before dissemination
- Disclosure to end users that AI was used to produce the content

High-risk domains include: legal guidance, healthcare decisions, insurance underwriting,
financial advice, employment and housing decisions, academic testing and admissions,
and professional journalistic content.

SRE and incident response use cases do not fall under these high-risk categories under
normal operating conditions.

### Additional Use Case Guidelines

- Consumer-facing chatbots must disclose AI involvement at the start of each session
- Agentic use cases remain subject to the full AUP
- MCP servers listed in Anthropic's Connector Directory must comply with the
  [Directory Policy](https://support.anthropic.com/en/articles/11697096-anthropic-mcp-directory-policy)

## Anthropic's Privacy Policy: What It Actually Says About Training

The consumer Privacy Policy does allow training on inputs and outputs by default, with
the following important caveats:

> "We may use your Inputs and Outputs to train our models and improve our Services,
> unless you opt out through your account settings."

However, this is the **consumer policy**. For enterprise API usage flowing through the
Microsoft DPA, the no-training guarantee is contractual and applies without an explicit
opt-out. This is documented in the
[Anthropic as a subprocessor](https://learn.microsoft.com/azure/sre-agent/anthropic-sub-processor)
page in Microsoft's docs:

> "Both Microsoft and Anthropic don't use your data to train AI models."

## What to Request from Microsoft for Compliance Review

If a formal compliance review of the Anthropic subprocessor relationship is needed,
the following documents are the authoritative sources:

1. [Microsoft Data Protection Addendum (DPA)](https://www.microsoft.com/licensing/docs/view/Microsoft-Products-and-Services-Data-Protection-Addendum-DPA):
   the primary contract governing data handling between Microsoft customers and Microsoft
   subprocessors including Anthropic

2. [Microsoft Subprocessor List (Service Trust Portal)](https://aka.ms/subprocessor):
   confirms Anthropic is listed as a named subprocessor under the Microsoft enterprise agreement

3. [Azure SRE Agent: Anthropic as a subprocessor](https://learn.microsoft.com/azure/sre-agent/anthropic-sub-processor):
   Microsoft's own documentation on the relationship, data handling, and regional defaults

4. [Data residency and privacy in Azure SRE Agent](https://learn.microsoft.com/azure/sre-agent/data-privacy):
   where data is stored and processed at the Azure layer

5. [Anthropic Trust and Security Portal](https://trust.anthropic.com/):
   Anthropic's security certifications, compliance documentation, and security controls

## Key Takeaways

- Anthropic's consumer Privacy Policy does NOT govern enterprise API usage through Azure
- The Microsoft DPA is the controlling document for data handling guarantees
- No-training guarantees and data isolation are contractual, not opt-in
- The AUP governs permissible use cases and applies to all API customers
- SRE and incident response automation is a permitted, non-high-risk use case under the AUP
