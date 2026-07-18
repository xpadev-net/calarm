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

### 2026-07-08 - Treat Debug Leads As Hypotheses

- tags: validation/verification, assumptions/interpretation, ci, delegation
- symptom: A follow-up task for a Baseline CI failure was initially worded as a timezone/date-assumption investigation after the user suggested timezone was worth checking.
- root cause: The orchestration prompt turned a plausible debugging lead into overly narrow framing before evidence established the root cause.
- fix: Reword the active plan and automation so timezone/current-date behavior is only one candidate cause alongside repeat/skip logic, clock seeding, CI environment, and calendar-date conversion.
- prevention: When a user suggests a possible root cause for a failing check, preserve it as a hypothesis unless they explicitly say it is the confirmed cause; worker prompts should require evidence before narrowing the fix.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-08 - Launch Implementation Workers With Requested Model

- tags: delegation, workflow/process, assumptions/interpretation
- symptom: A retry implementation worker was launched without explicitly setting the user's requested model/reasoning defaults.
- root cause: The orchestration retry focused on recovering from repeated worker startup failures and reused default thread settings instead of carrying forward the user preference for implementation-worker model selection.
- fix: Treat implementation-worker creation and implementation-bearing follow-up prompts as requiring `gpt-5.5` with medium reasoning unless the user says otherwise.
- prevention: Before creating or steering a Codex thread/worktree worker that may implement product code, check the active plan/user preferences for model/reasoning and pass them explicitly to `create_thread` or `send_message_to_thread`.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-07 - Use Codex Threads for Plan Workers

- tags: delegation, workflow/process, scope-owns
- symptom: Parent-plan execution delegated Wave 9 implementation to multi-agent subagents, but the user required workers to run as Codex threads instead.
- root cause: The orchestration request said worker, and the runtime had subagent tooling available, so delegation defaulted to subagents instead of preserving the task-pr-orchestrator thread/worktree model.
- fix: Shut down the subagents and switch future parent-plan implementation delegation to Codex thread/worktree workers.
- prevention: For this repository's parent implementation plan, treat "worker" as a Codex thread/worktree worker by default; use multi-agent subagents only for bounded review/research sidecars when explicitly requested or when they do not replace task workers.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-06 - Create Missing Owned Paths

- tags: workflow/process, scope-owns, assumptions/interpretation
- symptom: A worker stopped as blocked because delegated owned files did not exist on the base branch.
- root cause: The task ownership contract was interpreted as requiring preexisting files instead of allowing new file creation inside owned paths.
- fix: Continue implementation by creating the missing service and test files under the delegated owned paths.
- prevention: Before reporting blocked on a missing path, check whether the active task owns that path and whether the requested implementation naturally includes creating it; only block if creation would exceed ownership or a required dependency is missing.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-06 - Keep Failed Native Alarm IDs Discoverable

- tags: review, validation, state-transitions
- symptom: Review found that failed schedule/cancel paths could persist platform-backed occurrences as terminal failures, making native alarm IDs invisible to later retry cancellation queries.
- root cause: Failure status was treated as a terminal app state even when a native platform alarm identity still existed and needed lifecycle cleanup.
- fix: Keep platform-backed failed schedule/cancel rows in cancellable scheduled/ringing states, avoid soft delete on cancel failure, and add regression tests for retry-discoverability.
- prevention: In native alarm lifecycle work, any persisted `platformAlarmId` must remain reachable by the repository path used for future cancellation until the service has observed a successful cancel.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-06 - Orchestrator Must Review Before Merge

- tags: workflow/process, review, validation
- symptom: A worker PR merge was handled primarily from worker report, checks, hook evidence, and metadata inspection without explicitly calling out an orchestrator-owned review pass that could produce findings and return the PR to the worker.
- root cause: The merge gate evidence checklist was treated as sufficient unless checks failed, while the user expects the orchestrator to perform an active final review before merge and block on any in-scope findings.
- fix: Before merging any worker PR, perform and record an orchestrator-owned review of the PR diff against task acceptance, ownership boundaries, validation evidence, and runtime/deferred-risk wording.
- prevention: Merge checklist now includes an explicit "orchestrator review findings" decision: if findings exist, do not merge; send concrete follow-up to the worker and wait for a new head SHA, refreshed validation, and hook evidence.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-06 - Close Completed Wave Plans and Review Wave Codebase

- tags: workflow/process, planning, review, validation
- symptom: Completed wave plan files remained under `docs/coding-agent/plans/active/`, and Wave 8 lacked an explicit whole-codebase review-and-fix closeout after the scheduling/native/calendar implementation wave.
- root cause: Wave merge bookkeeping focused on task PR state and ledger evidence, but plan lifecycle movement and wave-level integrated review were not encoded as mandatory closeout steps.
- fix: Move completed wave plans to `docs/coding-agent/plans/completed/`, update parent links, and add a Wave 8 whole-codebase review/fix loop after implementation and native smoke tasks.
- prevention: Before declaring a wave complete, verify its plan file has moved out of `active/`; for Wave 8 and similar integration-heavy waves, require an orchestrator/reviewer codebase-wide review loop with follow-up fixes until no in-scope findings remain.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-06 - Push Orchestrator Ledger Commits Promptly

- tags: workflow/process, delegation
- symptom: Orchestrator ledger updates were committed locally, but the operating default did not explicitly require prompt push after local commits.
- root cause: The task-pr orchestration loop records ledger evidence, but local commit/push hygiene for parent-thread ledger-only changes was not encoded as a durable habit.
- fix: Treat orchestrator-owned ledger diffs as commit-and-push work whenever the user asks for persistent parent-thread bookkeeping.
- prevention: Before ending an orchestrator turn with committed ledger changes, check `git status --short --branch`; if the branch is ahead and there is no active reason to hold the commit locally, push it and report the commit/push state.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-06 - Add Baseline CI Before Specialized CI

- tags: ci, validation, planning
- symptom: Near-device simulator/emulator CI planning existed before ordinary PR CI was explicitly planned.
- root cause: The plan focused on deferred native runtime risk and did not separately encode baseline formatting, analyzer/lint, and unit-test automation.
- fix: Added a Wave 7 baseline GitHub Actions CI task and release-readiness checks, while keeping Wave 8 native smoke CI separate.
- prevention: When adding specialized CI, first confirm whether ordinary baseline CI exists and add or preserve format, lint/analyzer, and unit-test checks as an independent validation path.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-06 - Run Worker Hook After Review

- tags: workflow/process, review, validation
- symptom: Worker instructions could be read as allowing `gh-review-hook` evidence before final worker self-review or independent review completion.
- root cause: The PR lifecycle required hook exit 0, but did not always spell out the ordering that review fixes must be complete before the worker worktree reruns the hook.
- fix: Make worker validation require a final `rtk gh-review-hook <PR_NUMBER>` run from the worker worktree after self-review, independent review, and any review-driven fixes are complete.
- prevention: For merge-ready worker reports, require the reported hook evidence to be from the final reviewed head SHA; if review findings produced follow-up commits, the worker must rerun the hook before handoff.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-08 - Prove Acceptance Before No-Diff Stop

- tags: validation/verification, assumptions/interpretation, workflow/process
- symptom: A worker stopped with a no-diff conclusion even though Task_3 user-facing settings health checks and test-alarm UI were not implemented on `master`.
- root cause: Existing platform contract and QA checklist rows were mistaken for full acceptance coverage without re-reading the concrete UI path and proving each acceptance item in the running app surface.
- fix: Resume the task, inspect the settings presentation path, and implement missing user-facing health warnings and test-alarm flow.
- prevention: Before ending a delegated implementation task as already satisfied, map every acceptance bullet to concrete files/tests/UI behavior; absence of that proof means continue investigation instead of stopping.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-08 - Keep Follow-Up Refresh Failures Separate

- tags: review, validation, state-transitions
- symptom: Merge-gate review found a settings test-alarm success could be overwritten as a native scheduling failure when the follow-up capability refresh threw.
- root cause: The controller wrapped the scheduling side effect and a non-authoritative refresh in the same `try` block, so a later read failure changed the meaning of an already-created native alarm.
- fix: Make the native scheduling result authoritative, catch capability refresh failures separately, and retain the previous capability when refresh fails.
- prevention: For native side effects followed by status refreshes, tests must cover "side effect succeeds, refresh fails" and assert the user-visible result still reflects the side effect.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-08 - Disable Overlapping Health Actions

- tags: review, validation, state-transitions, ui
- symptom: Review found the settings "Check again" action stayed enabled while a test alarm was being scheduled, allowing overlapping refreshes to write stale alarm-health state.
- root cause: The UI only checked Riverpod loading state and did not model controller-level in-flight actions as one shared busy state.
- fix: Add explicit busy flags for refresh, permission, and test-alarm scheduling; disable readiness actions while any health action is in flight; preserve the latest controller state when async operations complete.
- prevention: For controller actions that share state, tests and UI review must verify overlapping action paths cannot overwrite newer user-visible results.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-08 - Return Non-Merge-Ready PRs To Workers

- tags: workflow/process, validation/verification, delegation, review
- symptom: The orchestrator held PR #26 at a user-decision point after determining it was not merge-ready because parent-owned `gh-review-hook` had not exited 0.
- root cause: A missing merge-gate artifact was treated as an external exception decision before first returning the non-merge-ready state to the owning worker for another bounded attempt or a precise blocker report.
- fix: Send the PR back to the owning Codex thread/worktree worker with concrete missing evidence and require either a refreshed merge-ready report or an exact blocker; keep parent-thread product code untouched.
- prevention: Before asking the user to approve a hook/validation exception, check whether an active owning worker can still address or precisely classify the missing merge-readiness evidence. If yes, send it back to the worker instead of pausing on user decision.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-10 - Prove Worker Liveness Beyond TUI Animation

- tags: workflow/process, validation/verification, delegation, tooling/environment
- symptom: The orchestrator reported two resumed workers as active after observing only the Codex TUI `Working` animation; both worker turns later stopped, and one completed report was not consumed.
- root cause: A transient terminal-rendering signal and surviving wrapper process were treated as authoritative worker liveness instead of checking new thread events, repository/PR progress, and a completed worker report.
- fix: Reconcile each worker from session event logs and current PR state, merge Task_1 from its completed report, and restart only workers that genuinely require more work.
- prevention: Before reporting a worker as active, require at least one post-resume durable signal: a new session event describing concrete work, a new branch/PR head, a running validation command, or an explicit active status from the thread API. TUI animation and process existence alone never prove progress; completion reports must be consumed before attempting another resume.
- promotion: Harness migration candidate concept: add a durable-liveness evidence gate to worker startup stability checks; staged as a repo-local lesson because this task does not authorize bundled harness edits.

### 2026-07-10 - Consume Worker Completion Before Ending Orchestration Turn

- tags: workflow/process, validation/verification, delegation
- symptom: After adding a durable startup-liveness check, the orchestrator still ended the turn while both workers later produced merge-ready completion reports that were not consumed until the user reported them stopped again.
- root cause: Startup stability was treated as sufficient closeout evidence; there was no turn-closing reconciliation of new `task_complete` events and PR heads before reporting workers as merely active.
- fix: Read both worker histories, consume their merge-ready reports, run orchestrator gates, merge PRs #40 and #39, and archive both sessions in the same turn.
- prevention: Before ending an orchestration turn that launched or resumed short bounded workers, perform one completion reconciliation after the expected validation window; if a worker has completed, process its report rather than describing it as active. For longer work, require a heartbeat/automation instead of relying on an orphaned TUI process.
- promotion: Staged as `HMC-20260710-orchestration-worker-completion-reconciliation` in `docs/coding-agent/skill-candidates.md` because the failure repeated and generalizes across repositories.

### 2026-07-11 - Use Codex Threads For Task PR Workers

- tags: workflow/process, delegation, assumptions/interpretation, tooling/environment
- symptom: The orchestrator launched Task_6 and Task_7 with `codex exec` CLI processes even though task-pr orchestration workers are expected to be user-visible Codex threads.
- root cause: Missing thread-management tools in the active tool surface was treated as permission to substitute a resumable CLI session without first preserving the requested worker lifecycle semantics.
- fix: Stop and archive both CLI sessions, verify their worktrees are clean and no PR exists, and return the ledger to a truthful thread-dispatch-waiting state.
- prevention: Before every task-pr worker start or replacement, require an available `create_thread` capability and create a user-visible thread with the requested model/reasoning level. If thread tooling is unavailable, report that concrete blocker; never substitute `codex exec`, a terminal process, or an internal subagent.
- promotion: Repo-local orchestration lesson; consider a harness dispatch preflight requiring the thread capability before worker branch/worktree creation.

### 2026-07-11 - Review Persisted Identity And Active Reservation State

- tags: review, state-transitions, idempotency, validation
- symptom: Independent review found that a process-local create-session counter could reuse a persisted plan ID after restart, and that any future occurrence with a platform ID was treated as reusable even when its status was failed, cancelled, expired, or ringing.
- root cause: The first implementation treated in-process uniqueness as durable identity and used native-ID presence without checking the AlarmOccurrence state invariant; the ringing branch also coerced fired metadata into an invalid scheduled state.
- fix: Use secure random session identities with avoidance of IDs already supplied from persisted plans; reuse only scheduled/ringing occurrences; preserve ringing status and firedAt; add regression tests for independent sessions, inactive statuses, skipped targets, and ringing rows.
- prevention: During idempotency review, require both a persisted-state collision analysis and an exhaustive status/metadata matrix for every dedupe predicate before reporting review-ready.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-15 - Make Calendar Presentation Controls Explicit

- tags: assumptions/interpretation, ui-e2e, planning
- symptom: The first calendar-first layout retained an unwanted empty-week message, used a right-side drawer, and left the calendar fixed to seven days with a fixed vertical scale.
- root cause: The broad Google Calendar-inspired request established hierarchy but did not yet specify drawer direction, empty-state treatment, day-range switching, or time-axis density controls.
- fix: Treat the follow-up as explicit acceptance criteria: suppress the empty-week message, use a left drawer, add bounded two-finger pinch zoom without zoom buttons, and support seven-day/three-day switching.
- prevention: For future calendar layout work, include drawer side, empty-state copy, visible-day range, exact zoom gesture/controls, vertical density, and state persistence in the research and acceptance checklist before implementation; do not substitute button controls when the interaction method matters.
- promotion: Repo-local lesson only; these are product-specific presentation defaults rather than a cross-repository harness rule.

### 2026-07-15 - Arbitrate Multi-Pointer Gestures Across Nested Scroll Axes

- tags: review, ui-e2e, validation/verification, state-transitions
- symptom: The first pinch implementation disabled the inner vertical scroll but left the parent horizontal `PageView` active, and terminal pointer paths could retain stale focal state.
- root cause: Gesture ownership and cleanup were checked inside the immediate calendar page rather than across the full nested scroll hierarchy and every pointer up/cancel path.
- fix: Share active two-pointer state with the parent pager, suspend both scroll axes during pinch, restore them after release/cancel, and clear transaction-only focal state while preserving independently consumable pending scroll work.
- prevention: For multi-pointer gestures nested inside scrollables, review and test every ancestor/descendant axis, diagonal movement, release, cancellation, post-gesture single-pointer recovery, and stale transaction state.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-15 - Stage Calendar Creation In Context Before Editing Details

- tags: assumptions/interpretation, ui-e2e, state-transitions, planning
- symptom: Tapping an empty calendar slot immediately opened a creation modal, while the desired Google Calendar-style flow keeps a provisional event visible and adjustable on the calendar first.
- root cause: The original interaction modeled slot selection as a direct transition into form editing rather than a staged draft with spatial start/end adjustment.
- fix: Introduce a transient on-calendar draft block with resize handles and explicit save/cancel controls before invoking persistence or detailed editing.
- prevention: For calendar creation flows, define whether selection creates an inline draft or opens a form, how time range adjustment works, when persistence occurs, and how cancel/back/gesture conflicts discard the draft.
- promotion: Repo-local lesson only; this is a product interaction default rather than a harness-wide rule.

### 2026-07-15 - Validate Calendar Draft Geometry With Real Pointers And Time

- tags: review, ui-e2e, validation/verification, state-transitions
- symptom: Callback-level tests passed while a normal draft had almost no body drag area, edge dragging could hide it off-page, and Save validity stayed stale as wall-clock time passed.
- root cause: Validation covered logical transitions without exercising actual hit geometry at supported zooms, visible-range boundaries, or autonomous timer/lifecycle changes.
- fix: Separate body and handle hit surfaces, clamp movement to the visible range, refresh deadline state by timer and lifecycle resume, and add delayed double-Save protection tests.
- prevention: Calendar manipulation acceptance must first resize to the exact minimum duration, then dispatch raw pointers against a distinct body point and every handle at default/minimum zoom; it must also test both edges in every day mode, advance time without parent rebuilds, exercise lifecycle resume, and verify one save call under delayed double taps.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-15 - Gate Alarm-Dependent UI On Startup Readiness

- tags: assumptions/interpretation, validation/verification, ui-e2e, state-transitions
- symptom: Users could reach calendar creation and only discover missing Android alarm permission after Save failed, producing a late and confusing error path.
- root cause: Native alarm capability was treated as settings health information and a scheduling-time failure instead of an application-entry prerequisite for alarm-dependent workflows.
- fix: Check required alarm capability during startup and show a full-screen permission/readiness gate with a clear system-settings action and retry until the requirement is satisfied.
- prevention: For platform capabilities required by the app's primary action, define the startup gate, denied/unsupported/error states, lifecycle-resume recheck, and downstream defensive error mapping before implementing the feature UI.
- promotion: Repo-local lesson only; this is a product/platform readiness policy rather than a harness-wide rule.

### 2026-07-15 - Make Concurrent Capability Checks Latest-Wins

- tags: review, state-transitions, validation/verification, concurrency
- symptom: Independent review found that overlapping alarm-capability checks could complete out of order, allowing an older ready result to overwrite a newer missing-permission result and reopen the home screen.
- root cause: Capability revisions counted successful responses but did not establish which in-flight request was authoritative.
- fix: Add a latest-wins generation authority across refresh, permission, and test-alarm capability operations, and ignore stale successes and failures.
- prevention: For lifecycle-sensitive capability state, define result authority separately from revision numbering and test reverse completion for success, missing-capability, and failure outcomes.
- promotion: Repo-local lesson only for now; no rule suite exists in this repository.

### 2026-07-15 - Inspect Wake-Plan Fan-Out Before Live Alarm Tests

- tags: validation/verification, assumptions/interpretation, state-transitions, safety
- symptom: A device test framed as creating one alarm saved one hour-long Wake Plan, which expanded at the configured five-minute interval into 13 native alarm occurrences.
- root cause: The validation plan treated a persisted Wake Plan and a native alarm occurrence as the same unit without checking interval fan-out before the live device mutation.
- fix: Limit delivery to the first occurrence, immediately delete the plan after stopping it, and verify the remaining native occurrences are cancelled and permissions restored.
- prevention: Before any live alarm E2E, record the plan duration and interval, calculate the exact occurrence count, choose a duration that produces one occurrence when the UI permits, and define cleanup against both the persisted plan and every native occurrence.
- promotion: Repo-local validation lesson; no repository rule suite exists.

### 2026-07-15 - Give Clock-Driven UI An Explicit Refresh Source

- tags: assumptions/interpretation, ui-e2e, state-transitions, lifecycle
- symptom: The calendar's red current-time line moved only when unrelated state happened to rebuild the widget, so it could remain stale while the app stayed open or after reopening it.
- root cause: The UI sampled an injected clock during build but had no timer or lifecycle event that made time passage observable; now-only rebuilds also reused initial-scroll logic.
- fix: Own a foreground-only minute-boundary refresh in the calendar, refresh immediately on resume, cancel it outside the foreground and on dispose, and decouple now repainting from initial scroll positioning.
- prevention: Any wall-clock-driven visual must define its update cadence, foreground/background behavior, resume catch-up, disposal cleanup, and viewport-preservation tests instead of relying on incidental rebuilds.
- promotion: Repo-local UI lifecycle lesson; no repository rule suite exists.

### 2026-07-15 - Reclaim Regenerable Flutter Output Before Large Suites

- tags: tooling/environment, validation/verification, troubleshooting
- symptom: Focused tests passed, but the full Flutter suite repeatedly stopped before assertions because the macOS temporary/data volume lacked space for compiled dill artifacts.
- root cause: The workspace retained 2.1GB of fully regenerable Flutter build output while free space had fallen to roughly 200MB.
- fix: Preserve source and user state, run `flutter clean` to remove only regenerable build output, then rerun the full suite with concurrency limited to one.
- prevention: Before large Flutter validation on a constrained volume, check free space; when it is below 1GB, prefer removing regenerable build output and reducing test concurrency over deleting source, caches with unclear ownership, or user data.
- promotion: Repo-local troubleshooting lesson; consider migrating to shared Flutter workspace troubleshooting guidance if repeated.

### 2026-07-15 - Match Timer Regression Evidence To Every Preserved State

- tags: review, validation/verification, ui-e2e, lifecycle
- symptom: The first minute-refresh implementation passed focused and full suites, but its new tests directly proved only page and vertical-offset retention, leaving the promised zoom/draft retention and several lifecycle branches unproven.
- root cause: Existing unrelated zoom/draft tests and implementation inspection were treated as sufficient evidence for behavior during a timer-driven now rebuild.
- fix: Add explicit regression cases that hold a real draft and non-default zoom across now updates, exercise inactive/hidden/detached cancellation, and detect duplicate ticks after repeated resume.
- prevention: When acceptance names preserved UI states or lifecycle branches, the focused regression matrix must exercise each state in the changed event path; broad-suite coverage is supplementary, not a substitute.
- promotion: Repo-local UI review lesson; no repository rule suite exists.

### 2026-07-16 - End Gestures At A Stable Owner When Children Can Be Re-Keyed

- tags: review, ui-e2e, state-transitions, lifecycle
- symptom: Dragging an inline calendar draft across a day boundary replaced its day-keyed child before pointer-up, leaving the parent page in manipulation mode and vertical scrolling disabled.
- root cause: Gesture-end cleanup was owned only by a child whose identity changes during the gesture, while the existing test immediately started a second handle gesture that accidentally cleared the stuck state.
- fix: Clear manipulation state from the stable page-level pointer-up/cancel path and verify a one-finger vertical scroll immediately after the cross-day body drag.
- prevention: When an active gesture can change the keyed identity of its child, terminate shared gesture state at a stable ancestor and make the very next unrelated gesture the regression assertion so later cleanup cannot mask the defect.
- promotion: Repo-local UI interaction lesson; no repository rule suite exists.

### 2026-07-16 - Combine Runtime And Global Notification Readiness

- tags: review, validation/verification, platform-contract, permissions
- symptom: Alarm readiness treated Android 8–12 as notification-ready unconditionally and Android 13+ as ready when the runtime permission was granted, even if the user disabled notifications for the entire app.
- root cause: The permission model covered `POST_NOTIFICATIONS` and channel importance but omitted `NotificationManager.areNotificationsEnabled()` as an independent global gate and remediation path.
- fix: Require both the API-appropriate runtime permission and global app notification enablement, and route globally disabled apps to notification settings with a safe fallback.
- prevention: Android notification readiness matrices must separately test runtime permission, app-level notification enablement, and channel enablement for every supported API branch.
- promotion: Repo-local Android permission lesson; no repository rule suite exists.

### 2026-07-16 - Remove Stable Device Identifiers Before Publishing Evidence

- tags: review, validation/verification, privacy, publication
- symptom: A completed validation plan intended for a public PR contained the physical device's stable ADB serial in commands and progress logs.
- root cause: The publication privacy sweep focused on local filesystem paths and tokens but did not include device identifiers recorded in durable validation evidence.
- fix: Replace the serial with a model description or `<device-id>` placeholder and re-scan every newly published plan, closeout, and lesson file.
- prevention: Pre-commit privacy sweeps for device-validation work must include ADB serials and other stable hardware identifiers in addition to home paths, usernames, tokens, and keys.
- promotion: Repo-local publication lesson; consider a shared privacy-sweep update if this recurs.

### 2026-07-16 - Scope Gradle Test Filters To The Owning Module

- tags: validation/verification, gradle, android, tooling/environment
- symptom: A focused Android JVM test command failed because the root aggregate task forwarded `--tests` to a dependent module that contained no matching test.
- root cause: A class filter was applied to the multi-project `testDebugUnitTest` aggregate instead of the Android app module that owns the test class.
- fix: Run filtered JVM tests through `:app:testDebugUnitTest --tests ...`, and reserve the root aggregate task for unfiltered full-suite validation.
- prevention: In a Gradle multi-project build, target the owning module whenever a test-class filter is used so unrelated modules do not fail on zero matches.
- promotion: Repo-local Android validation lesson; consider shared Gradle guidance if repeated.

### 2026-07-16 - Close Every Call Site When Adding A Fallback Helper

- tags: review, platform-contract, fallback, android
- symptom: A notification-settings fallback helper was added, but two existing permission-remediation branches still launched the same settings intent directly and could fail on an OEM without a matching activity.
- root cause: The first repair validated the new global-notification path without searching every call site of the intent factory and direct `startActivity` invocation.
- fix: Route all notification-settings launches through the common fallback helper and add a regression for an unresolved settings intent.
- prevention: When centralizing fallback behavior, search both the original intent factory and its side-effect call to prove that no direct call site bypasses the helper.
- promotion: Repo-local platform review lesson; consider shared fallback guidance if repeated.

### 2026-07-16 - Keep Gesture Session State Until The Gesture Ends

- tags: review, ui-e2e, lifecycle, state-transitions
- symptom: A multi-frame pinch applied its pending scroll after the first move and cleared the focal coordinate while both pointers were still down, so the next move could force-unwrap null.
- root cause: Per-frame pending-scroll cleanup also cleared gesture-session state even though later pointer events still depended on it.
- fix: Clear the pending offset after each frame but retain the focal coordinate while pinching; reset it only when the gesture ends or a non-pinch external update completes.
- prevention: Separate frame-scoped state from gesture-scoped state, and test multi-event gestures with a rendered frame between successive moves.
- promotion: Repo-local UI interaction lesson; consider shared gesture guidance if repeated.

### 2026-07-16 - Persist Ringing Only After At Least One Delivery Path Succeeds

- tags: review, event-driven, fallback, state-transitions, android
- symptom: An alarm occurrence was marked ringing before delivery, and all notification, screen, and vibration failures were swallowed, leaving an unreachable ringing row.
- root cause: Fallback isolation tracked attempts but did not aggregate whether any delivery path actually succeeded before retaining the durable ringing state.
- fix: Attempt every enabled fallback independently, return aggregate delivery success, and remove the fired native row when every path fails while retaining it after any success.
- prevention: For event delivery with multiple fallbacks, test both all-failed and partial-success outcomes and tie durable state to aggregate delivery success rather than dispatch initiation.
- promotion: Repo-local event-delivery lesson; consider shared event-driven guidance if repeated.

### 2026-07-16 - Preserve An Interval Anchor And Duration Separately Across DST

- tags: review, time-boundaries, state-transitions, validation/verification
- symptom: Reconstructing both draft endpoints at the same wall-clock times after a calendar-day move changed elapsed duration across DST and could push a valid three-hour draft beyond its constructor limit.
- root cause: Wall-clock preservation was applied independently to both endpoints without identifying the authoritative anchor or separately preserving the interval-duration invariant.
- fix: Move the start as the calendar-day wall-clock anchor, derive the end from the original elapsed duration, and test both spring-forward and fall-back transition intervals in an explicit DST timezone.
- prevention: For interval movement across date or timezone boundaries, define the wall-clock anchor and elapsed-duration invariant independently, then test both DST directions including maximum-duration values.
- promotion: Repo-local time-boundary lesson; consider shared date/time guidance if repeated.

### 2026-07-16 - Keep Focus Identity Stable Across Keyboard-Driven Re-Keying

- tags: review, accessibility, ui-e2e, lifecycle
- symptom: A keyboard day-move changed a draft segment key, disposed the State-owned FocusNode, and prevented a second arrow-key or screen-reader action without reselecting the draft.
- root cause: Focus ownership followed a visual day segment whose identity changes during the accessible action instead of the logical draft role.
- fix: Key focus-bearing draft controls by stable draft and semantic role, and verify consecutive cross-day keyboard actions without another tap.
- prevention: Any accessibility or keyboard action that can move a control between rendered segments must preserve logical focus identity across the resulting rebuild.
- promotion: Repo-local accessibility lesson; consider shared Flutter focus guidance if repeated.

### 2026-07-16 - Restart Reviewers That Stop Producing Durable Progress

- tags: workflow/process, delegation, review, validation/verification
- symptom: An exact-head independent reviewer remained marked running for an extended period without a completion report or other durable progress, while the orchestration loop continued to describe the review as active.
- root cause: Runtime agent status was treated as sufficient liveness evidence after dispatch, without a bounded follow-up check for reviewer output.
- fix: Interrupt the stalled reviewer and launch a fresh read-only reviewer against the same immutable head and base.
- prevention: For bounded independent reviews, require a durable progress or completion signal within the next monitoring window; after one silent extended interval, inspect once, interrupt if still silent, and restart against the exact unchanged SHA rather than repeatedly reporting it as active.
- promotion: Repo-local orchestration lesson; related to the existing worker-liveness and completion-reconciliation lessons, with reviewer-specific restart handling.

### 2026-07-16 - Freeze The Base During Exact-Head Review

- tags: workflow/process, review, validation/verification, git
- symptom: A replacement exact-head review was started and then immediately made stale by pushing an orchestrator-owned lessons commit to the PR base branch.
- root cause: Mandatory lesson persistence was handled after reviewer dispatch instead of completing parent-owned base mutations before fixing the review SHA/base pair.
- fix: Stop the now-stale reviewer, finish the parent documentation commit, integrate the final base into the worker branch normally, and then launch a fresh exact-head review.
- prevention: Before dispatching any exact-head reviewer, complete or defer every known parent-owned base-branch mutation and record the immutable head/base pair; do not push the base again until the review gate completes.
- promotion: Repo-local orchestration lesson; candidate for a shared exact-head review preflight if repeated elsewhere.
### 2026-07-18 - Prefix Every Shell Pipeline Segment With RTK

- tags: workflow/process, tooling/environment, validation/verification, rtk
- symptom: An orchestrator search command prefixed the primary `grep` invocation with `rtk` but left the trailing `head` pipeline segment unprefixed, violating the repository's every-segment RTK rule.
- root cause: The command review checked only the first executable and did not tokenize the full shell pipeline before execution.
- fix: Treat each pipeline, conditional, and command-chain segment as an independent command and require an explicit `rtk` prefix (using `rtk proxy` where no specialized filter applies).
- prevention: Before every shell call, scan separators (`|`, `&&`, `||`, `;`) and verify that the executable immediately following each separator begins with `rtk`; include this check in orchestrator preflight and closeout.
- promotion: Repo-local command-execution guardrail; consider a shared shell-command validator if this recurs across repositories.

### 2026-07-18 - Confirm Pre-Release Compatibility Before Preserving Migration Complexity

- tags: assumptions/interpretation, scope/ownership, architecture/design, workflow/process
- symptom: Review and remediation work treated legacy native mirror/journal formats and installed-state migration as constraints even though the product is still in development and the user does not require backward compatibility.
- root cause: Compatibility was inferred from defensive migration guidance instead of being established as an explicit product requirement for the current release stage.
- fix: Record the user's no-backward-compatibility decision, permit a current-schema-only native-state design within Task_12 ownership, and keep platform atomicity and current-schema recovery as separate correctness gates.
- prevention: Before adding or retaining migration/legacy-format complexity in a pre-release product, confirm whether compatibility is required; when it is not, remove that constraint explicitly without using it to waive current-state correctness or expand ownership.
- promotion: Repo-local pre-release design rule; consider shared architecture guidance if the same assumption recurs across projects.
