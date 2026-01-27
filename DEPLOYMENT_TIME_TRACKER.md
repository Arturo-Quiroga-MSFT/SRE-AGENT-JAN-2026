# Deployment Time Tracker

Track actual time spent on each phase of the deployment.

## Quick Reference

| Phase | Estimated | Actual | Status | Notes |
|-------|-----------|--------|--------|-------|
| Prerequisites Check | 5 min | ___ min | ⬜ | Tools installed, accounts ready |
| Phase 1: Base Infra | 20-30 min | ___ min | ⬜ | `azd up` deployment |
| Phase 2: Loki | 10 min | ___ min | ⬜ | Including config & testing |
| Phase 3: Grafana | 15 min | ___ min | ⬜ | Data sources + service account |
| Phase 4: MCP Servers | 15 min | ___ min | ⬜ | Grafana + Jira MCP deployment |
| Phase 5: SRE Agent | 20 min | ___ min | ⬜ | Agent + sub-agent setup |
| Phase 6: Testing | 15 min | ___ min | ⬜ | End-to-end validation |
| Phase 7: Handoff | 30 min | ___ min | ⬜ | Documentation review |
| **TOTAL** | **~90 min** | **___ min** | ⬜ | |

## Detailed Phase Tracking

### Prerequisites (Target: 5 minutes)
**Start Time:** ___________  
**End Time:** ___________  
**Elapsed:** ___ minutes

- [ ] Azure CLI version check (< 1 min)
- [ ] Azure Developer CLI check (< 1 min)
- [ ] Docker running (< 1 min)
- [ ] Azure login (< 2 min)
- [ ] Jira API token ready (< 1 min)

**Issues Encountered:**
```
[Note any problems here]
```

---

### Phase 1: Base Infrastructure (Target: 20-30 minutes)
**Start Time:** ___________  
**End Time:** ___________  
**Elapsed:** ___ minutes

#### Sub-tasks
- [ ] Clone repo (< 1 min)
- [ ] `azd auth login` (< 2 min)
- [ ] `azd up` - provision (15-25 min)
  - Resource group creation: ___ min
  - Container Apps Environment: ___ min
  - Container Registry: ___ min
  - Grocery API build & deploy: ___ min
  - Web Frontend build & deploy: ___ min
  - Azure Managed Grafana: ___ min
- [ ] Verify resources (< 2 min)
- [ ] Capture env variables (< 1 min)

**Azure Resources Created:**
```
Resource Group: ___________________
Environment: ___________________
Container Registry: ___________________
API App: ___________________
Web App: ___________________
Grafana: ___________________
```

**Issues Encountered:**
```
[Note any problems here]
```

---

### Phase 2: Loki Deployment (Target: 10 minutes)
**Start Time:** ___________  
**End Time:** ___________  
**Elapsed:** ___ minutes

#### Sub-tasks
- [ ] Run `./deploy-loki.sh` (6-8 min)
  - Container creation: ___ min
  - Startup time: ___ min
- [ ] Verify Loki running (< 1 min)
- [ ] Configure API logs (< 1 min)
- [ ] Test Loki endpoint (< 1 min)

**Loki URL:** ___________________

**Issues Encountered:**
```
[Note any problems here]
```

---

### Phase 3: Grafana Configuration (Target: 15 minutes)
**Start Time:** ___________  
**End Time:** ___________  
**Elapsed:** ___ minutes

#### Sub-tasks
- [ ] Get Grafana URL (< 1 min)
- [ ] Open Grafana UI (< 1 min)
- [ ] Add Loki data source (3-5 min)
  - Configuration: ___ min
  - Test & save: ___ min
- [ ] Create service account (3-5 min)
  - Account creation: ___ min
  - Token generation: ___ min
- [ ] Test Loki queries (2-3 min)

**Grafana URL:** ___________________  
**Service Account Token:** glsa_____... (saved securely)

**Issues Encountered:**
```
[Note any problems here]
```

---

### Phase 4: MCP Servers Deployment (Target: 15 minutes)
**Start Time:** ___________  
**End Time:** ___________  
**Elapsed:** ___ minutes

#### Sub-tasks
- [ ] Prepare Jira credentials (< 1 min)
- [ ] Run `./deploy-mcp-servers.sh` (10-12 min)
  - Grafana MCP deployment: ___ min
  - Grafana MCP startup: ___ min
  - Jira MCP deployment: ___ min
  - Jira MCP startup: ___ min
- [ ] Test endpoints (2-3 min)
  - Grafana MCP test: ___ min
  - Jira MCP test: ___ min

**MCP Endpoints:**
```
Grafana MCP: ___________________
Jira MCP: ___________________
```

**Issues Encountered:**
```
[Note any problems here]
```

---

### Phase 5: SRE Agent Setup (Target: 20 minutes)
**Start Time:** ___________  
**End Time:** ___________  
**Elapsed:** ___ minutes

#### Main Agent Creation
- [ ] Open SRE Agent portal (< 1 min)
- [ ] Create agent (8-10 min)
  - Form fill: ___ min
  - Resource group selection: ___ min
  - Deployment wait: ___ min
- [ ] Assign permissions (2-3 min)
  - Get principal ID: ___ min
  - Role assignment: ___ min

**Agent Details:**
```
Agent Name: ___________________
Resource Group: ___________________
Principal ID: ___________________
```

#### Sub-Agent Configuration
- [ ] Create sub-agent (1 min)
- [ ] Upload knowledge file (1 min)
- [ ] Add Grafana MCP tool (2-3 min)
  - Configuration: ___ min
  - Test connection: ___ min
- [ ] Add Jira MCP tool (2-3 min)
  - Configuration: ___ min
  - Test connection: ___ min
- [ ] Configure instructions (2-3 min)

**Issues Encountered:**
```
[Note any problems here]
```

---

### Phase 6: End-to-End Testing (Target: 15 minutes)
**Start Time:** ___________  
**End Time:** ___________  
**Elapsed:** ___ minutes

#### Trigger Incident
- [ ] Get API URL (< 1 min)
- [ ] Trigger rate limit (< 1 min)
- [ ] Verify logs in Grafana (2-3 min)

#### Agent Investigation
- [ ] Invoke agent with prompt (< 1 min)
- [ ] Wait for agent response (5-8 min)
  - Read knowledge file: ___ sec
  - Query Loki: ___ sec
  - Analyze results: ___ sec
  - Create Jira ticket: ___ sec
  - **Total agent response time:** ___ min ___ sec
- [ ] Verify Jira ticket created (2-3 min)

**Agent Performance Metrics:**
```
Total response time: ___ min ___ sec
Queries executed: ___
Tokens used (approx): ___
Jira ticket ID: ___
```

**Test Results:**
- [ ] ✅ Agent read knowledge file
- [ ] ✅ Agent queried Loki via Grafana MCP
- [ ] ✅ Agent identified error pattern
- [ ] ✅ Agent created Jira ticket
- [ ] ✅ Ticket contains RCA
- [ ] ✅ Ticket contains remediation steps

**Issues Encountered:**
```
[Note any problems here]
```

---

### Phase 7: Partner Handoff (Target: 30 minutes)
**Start Time:** ___________  
**End Time:** ___________  
**Elapsed:** ___ minutes

#### Documentation Review
- [ ] Walkthrough README (5 min)
- [ ] Review PARTNER_POC_GUIDE (10 min)
- [ ] Show scenario examples (5 min)

#### Live Demonstration
- [ ] Show MCP architecture (3 min)
- [ ] Query logs in Grafana (2 min)
- [ ] Modify knowledge file (2 min)
- [ ] Test agent with different prompt (3 min)

**Partner Questions/Feedback:**
```
[Note questions and answers here]
```

---

## Summary & Lessons Learned

### Total Time Breakdown
```
Prerequisites:       ___ min
Phase 1 (Infra):    ___ min
Phase 2 (Loki):     ___ min
Phase 3 (Grafana):  ___ min
Phase 4 (MCP):      ___ min
Phase 5 (Agent):    ___ min
Phase 6 (Testing):  ___ min
Phase 7 (Handoff):  ___ min
────────────────────────────
TOTAL:              ___ min (___ hours)
```

### What Went Well
```
1. 
2. 
3. 
```

### What Took Longer Than Expected
```
1. 
2. 
3. 
```

### Recommendations for Next Time
```
1. 
2. 
3. 
```

### Issues & Resolutions
```
Issue 1: 
Resolution: 

Issue 2: 
Resolution: 

Issue 3: 
Resolution: 
```

---

## Agent Performance Tracking

### Test Scenario 1: Rate Limit Investigation
**Prompt:** _[Copy exact prompt used]_

**Agent Response Time:** ___ min ___ sec

**Actions Taken:**
1. Read knowledge file: ___ sec
2. Query Loki (attempt 1): ___ sec
3. Query Loki (attempt 2): ___ sec (if applicable)
4. Analyze results: ___ sec
5. Create Jira ticket: ___ sec

**Token Usage (if visible):** ~___ tokens

**Quality Assessment:**
- Accuracy: ⭐⭐⭐⭐⭐ (rate 1-5)
- Relevance: ⭐⭐⭐⭐⭐
- Completeness: ⭐⭐⭐⭐⭐
- Jira ticket quality: ⭐⭐⭐⭐⭐

**Notes:**
```
[Observations about agent behavior]
```

---

### Test Scenario 2: [Custom Scenario]
**Prompt:** _[Copy exact prompt used]_

**Agent Response Time:** ___ min ___ sec

**Actions Taken:**
1. 
2. 
3. 

**Token Usage (if visible):** ~___ tokens

**Quality Assessment:**
- Accuracy: ⭐⭐⭐⭐⭐ (rate 1-5)
- Relevance: ⭐⭐⭐⭐⭐
- Completeness: ⭐⭐⭐⭐⭐

**Notes:**
```
[Observations about agent behavior]
```

---

## Deployment Checklist Progress

**Overall Completion:** ____%

- Prerequisites: [ ] Complete
- Phase 1: [ ] Complete
- Phase 2: [ ] Complete
- Phase 3: [ ] Complete
- Phase 4: [ ] Complete
- Phase 5: [ ] Complete
- Phase 6: [ ] Complete
- Phase 7: [ ] Complete

**Deployment Status:** 🔴 Not Started | 🟡 In Progress | 🟢 Complete

**Date Started:** ___________  
**Date Completed:** ___________

---

**Completed By:** ___________________  
**Reviewed By:** ___________________  
**Partner Sign-off:** ___________________
