# Lessons Log (Coding Agent)

Purpose:
- capture recurring mistakes and the prevention mechanism
- enable "read once, don't repeat" improvements

## How to use
- Append a new entry after any user correction or significant miss.
- Keep entries short and actionable.
- Promote repeated/high-severity lessons into repo rules, harness migration candidates, troubleshooting notes, or accepted residual-risk records.

## Tags (recommended)
- planning
- validation
- delegation
- review
- ui-e2e
- tooling
- ci
- scope-owns

## Entries

### 2026-07-06 - Add Baseline CI Before Specialized CI
- tags: ci, validation, planning
- symptom: Near-device simulator/emulator CI planning existed before ordinary PR CI was explicitly planned.
- root cause: The plan focused on deferred native runtime risk and did not separately encode baseline formatting, analyzer/lint, and unit-test automation.
- fix: Added a Wave 7 baseline GitHub Actions CI task and release-readiness checks, while keeping Wave 8 native smoke CI separate.
- prevention: When adding specialized CI, first confirm whether ordinary baseline CI exists and add or preserve format, lint/analyzer, and unit-test checks as an independent validation path.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.
