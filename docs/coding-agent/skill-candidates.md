# Harness Migration Candidates

Purpose:
- Stage cross-repository improvements discovered during target-repository work.
- These are not active repo rules.
- These should be picked up by a later harness-maintenance PR/issue.

## Candidates

### HMC-20260710-orchestration-worker-completion-reconciliation

- Status: staged
- Category: orchestration
- Proposed home: `plugins/coding-agent-orchestration-harness/skills/orchestration-harness/SKILL.md`
- Generalized rule:
  An orchestrator must reconcile durable worker completion events and current PR heads before ending a turn that launched or resumed bounded workers; startup liveness alone is not sufficient.
- Trigger:
  One or more background workers were launched or resumed and are expected to finish within the current orchestration window.
- Evidence from this repo:
  Workers for PRs #38, #39, and #40 completed and emitted merge-ready reports, but parent turns reported them as merely active or stopped because the reports were not consumed until repeated user corrections.
- Why this generalizes:
  Background worker messaging can fail independently of worker execution, and transient TUI/process state does not guarantee that the orchestrator will observe completion without an explicit reconciliation gate.
- Suggested change:
  Extend the worker startup/async lifecycle guidance with a turn-closing completion reconciliation: read durable thread events and PR heads once after bounded work should finish; process `task_complete` immediately, and use heartbeat automation for work that will outlive the turn.
- Draft: none
