# Native Alarm Feasibility Spike Evidence

- Status: pending
- Owner: pending
- Last updated: pending
- Decision status: pending

Use this document as the single evidence record for native alarm feasibility.
Do not leave unknown values blank; write `pending`, `not tested`, or `not applicable`.

Artifact paths should use:

```text
docs/qa/artifacts/<wave>-<platform>-<flow>-<YYYYMMDD-HHMM>.<ext>
```

## Result Legend

| Value | Meaning |
|---|---|
| pending | Not verified yet or blocked on device/access/setup. |
| pass | Verified on the stated device and OS condition. |
| fail | Verified and did not meet the expected result. |
| not applicable | The case does not apply to this platform or configuration. |

## Scope

This spike verifies whether the MVP can schedule and deliver native alarms for
the Wake Plan model:

- 1-minute test alarm.
- Multiple alarms in the same Wake Plan.
- 60-minute window with 5-minute interval, equivalent to 13 alarms.
- Dismissing one alarm without canceling future alarms.
- Canceling an individual occurrence.
- Canceling a whole Wake Plan.
- Delivery while the device is locked.
- Delivery while the app is terminated.
- Behavior when alarm or notification permission is denied.
- iOS Silent / Focus behavior.
- Android reboot restore behavior.

Simulator or emulator results may be recorded, but they do not approve MVP
feasibility. Real-device verification is required for release-blocking cases.

## iOS Evidence

### iOS Environment

| Field | Value |
|---|---|
| Device model | blocked: no real iOS device discovered by `xcrun devicectl list devices`; available simulators are iOS 18.0 only |
| Device identifier or QA label | blocked: no iOS 26+ real device or compatible simulator/runtime available |
| OS version | blocked for runtime validation; local SDK is iOS 26.5 via Xcode 26.6, but simulator runtime is iOS 18.0 |
| Build version / commit | `79ac0480c15a577edb7c2f38268686b7fdb393b6` at spike investigation time |
| Build configuration | no iOS app target exists in this repository yet; API surface typechecked directly against iPhoneOS 26.5 SDK |
| Alarm API under test | AlarmKit |
| Alarm permission state | blocked: `AlarmManager.authorizationState` and `requestAuthorization()` typecheck, but authorization cannot be requested without an iOS 26+ runtime/device |
| Notification permission state | not tested; AlarmKit runtime/notification behavior requires iOS 26+ device validation |
| Sound / silent mode setting | blocked: no real device available to toggle or observe Silent mode behavior |
| Focus / Do Not Disturb setting | blocked: no real device available to toggle or observe Focus behavior |
| Lock state during test | blocked: no iOS 26+ real device available for lock-screen validation |
| App state during test | blocked: no iOS 26+ real device available for foreground/background/terminated validation |
| Network state, if relevant | not applicable for local AlarmKit API surface investigation; runtime cases not tested |
| Evidence artifact directory | docs/qa/artifacts/ |
| Notes | Xcode 26.6 / iPhoneOS 26.5 SDK exposes `AlarmManager.schedule(id:configuration:)`, `cancel(id:)`, `stop(id:)`, `alarms`, `authorizationState`, `requestAuthorization()`, `Alarm.Schedule.fixed(Date)`, and `Alarm.Schedule.relative(..., repeats: .weekly([...])`. A direct `swiftc -typecheck` probe against the iPhoneOS 26.5 SDK passed. Runtime delivery, limit, dismissal, lock-screen, terminated-app, Silent, and Focus behavior remain blocked. |

### iOS Verification Cases

| ID | Case | Procedure | Expected result | Actual result | Result | Evidence artifact path | Follow-up |
|---|---|---|---|---|---|---|---|
| ios-01 | 1-minute alarm | Schedule one test alarm for 1 minute from now on a real device. | Alarm fires at the scheduled time and can be dismissed with only the current alarm stopped. | blocked: no iOS 26+ real device or compatible runtime available. Local SDK typecheck confirms fixed one-shot schedules can be represented with `Alarm.Schedule.fixed(Date)` and scheduled through `AlarmManager.schedule(id:configuration:)`, but no alarm was scheduled or delivered. | pending | not applicable (no runtime artifact) | Run on iOS 26+ real device; record authorization prompt, scheduled ID, delivery time, dismissal behavior, and cleanup. |
| ios-02 | Short-interval 3 alarms | Schedule three alarms at short test intervals for the same Wake Plan. Dismiss the first alarm. | All three alarms fire in order; dismissing one does not cancel the remaining alarms. | blocked: no iOS 26+ runtime. API surface supports separate UUID-backed `Alarm.ID` values, `stop(id:)`, `cancel(id:)`, and `alarms`, so independent occurrence modeling appears API-feasible, but future-alarm survival after dismiss was not tested. | pending | not applicable (no runtime artifact) | Schedule three concrete AlarmKit alarms on device; dismiss the first with stop intent; verify remaining IDs stay in `AlarmManager.alarms` and fire. |
| ios-03 | 5-minute interval, 13-equivalent alarms | Schedule a 60-minute Wake Plan with 5-minute interval, or a documented time-compressed equivalent if real-time verification is deferred. | Thirteen occurrences can be reserved and each expected occurrence fires or is represented by approved platform recurrence semantics. | blocked: no iOS 26+ runtime. SDK exposes `AlarmManager.AlarmError.maximumLimitReached`, so reservation limits must be measured; no evidence yet that 13 simultaneous alarms are accepted or delivered. | pending | not applicable (no runtime artifact) | On device, attempt 13 fixed alarms using distinct IDs for one plan; record accepted count, any `maximumLimitReached` error, delivery sequence, and cleanup. |
| ios-04 | Individual cancel | Schedule at least three future occurrences, cancel one middle occurrence, then wait through the sequence. | The canceled occurrence does not fire; non-canceled future occurrences still fire. | blocked: no iOS 26+ runtime. Local typecheck confirms `Alarm.ID == Foundation.UUID` and `AlarmManager.cancel(id:)` exists, so platformAlarmId-equivalent individual cancel can be modeled as one UUID per occurrence, but runtime cancel semantics were not verified. | pending | not applicable (no runtime artifact) | On device, cancel one middle occurrence by UUID; verify canceled occurrence is absent and neighboring alarms still fire. |
| ios-05 | Plan cancel | Schedule a Wake Plan with multiple future occurrences, then cancel the plan. | No future occurrence for that Wake Plan fires after cancellation. | blocked: no iOS 26+ runtime. API has per-ID cancel only in the inspected surface; plan cancel should be implemented by storing all occurrence UUIDs for the Wake Plan and iterating `cancel(id:)`, but this was not runtime-tested. | pending | not applicable (no runtime artifact) | On device, schedule multiple IDs for one plan, cancel all IDs, verify `AlarmManager.alarms` no longer contains them and none fire. |
| ios-06 | Locked device | Schedule an alarm, lock the device before the due time, and keep the device locked until delivery. | Alarm is visible/audible in the lock-state behavior expected for the API and can be dismissed. | blocked: no iOS 26+ real device available. Simulator-only evidence would not approve this case, and the available simulator runtime is iOS 18.0. | pending | not applicable (no runtime artifact) | Validate on a physical iOS 26+ device; capture lock-screen behavior and dismissal result. |
| ios-07 | Terminated app | Schedule an alarm, fully terminate the app, then wait until the scheduled time. | Alarm fires without the app being foregrounded manually. | blocked: no iOS 26+ real device available and no iOS app target exists to install/terminate. | pending | not applicable (no runtime artifact) | Add/run minimal iOS AlarmKit probe app or production iOS target on device; schedule, terminate app, record delivery and cleanup. |
| ios-08 | Permission denied | Deny alarm and/or notification permission, then attempt scheduling and delivery. | App detects the denied state, scheduling does not silently succeed, and the user-facing state can explain the blocker. | blocked: no iOS 26+ runtime. SDK confirms `AuthorizationState` values `notDetermined`, `denied`, and `authorized`, plus `requestAuthorization()`, but denied-state scheduling behavior was not tested. | pending | not applicable (no runtime artifact) | On device, deny AlarmKit authorization and verify scheduling error/state mapping; separately record notification permission interaction if any. |
| ios-09 | Silent / Focus mode | Enable Silent mode and the Focus / Do Not Disturb condition under test, schedule an alarm, then wait until delivery. | Alarm delivery behavior is recorded as acceptable or release-blocking for the stated mode; failures have a user-facing mitigation or block release. | blocked: no iOS 26+ real device available to toggle hardware/software Silent mode or Focus and observe delivery. | pending | not applicable (no runtime artifact) | On device, run Silent-only, Focus-only, and Silent+Focus cases; record audible/vibration/visual behavior and release impact. |

### iOS Local API Feasibility Notes

- Authorization: API surface supports `AlarmManager.authorizationState`, `requestAuthorization()`, and states `notDetermined`, `denied`, and `authorized`; runtime prompt and denied scheduling behavior are not tested.
- Identifiers: `Alarm.ID` is `Foundation.UUID`, which is suitable for a platformAlarmId-equivalent per `AlarmOccurrence`.
- Individual cancel: `AlarmManager.cancel(id:)` typechecks for a single UUID; runtime cancel and non-canceled future delivery remain blocked.
- Plan cancel: no plan-level cancel was found in the inspected SDK surface; store all occurrence UUIDs for a Wake Plan and cancel them individually unless later runtime/API evidence shows a grouped API.
- Scheduling model: fixed one-shot alarms are representable as `Alarm.Schedule.fixed(Date)`. Weekly recurrence is representable as `Alarm.Schedule.relative(..., repeats: .weekly([...]))`; recurrence has `weekly([...])` and `never` cases in the inspected SDK surface.
- Next-skip decision: the inspected recurrence API does not expose exception dates or "skip next occurrence" semantics. Decision-quality local evidence therefore favors rolling concrete occurrence reservation for MVP next-skip semantics, pending real-device validation of reservation limits and delivery reliability.
- Reservation limit: `AlarmManager.AlarmError.maximumLimitReached` exists, so the 13-equivalent Wake Plan must be measured on device before approval.
- Cleanup: no test alarms were created in this environment; cleanup result is not applicable.

## Android Evidence

### Android Environment

| Field | Value |
|---|---|
| Device model | pending |
| Device identifier or QA label | pending |
| OS version / API level | pending |
| Build version / commit | pending |
| Build configuration | pending |
| Alarm API under test | AlarmManager / exact alarm / full-screen notification |
| Exact alarm permission state | pending |
| Notification permission state | pending |
| Full-screen notification setting | pending |
| Sound / silent mode setting | pending |
| Battery saver / optimization setting | pending |
| Lock state during test | pending |
| App state during test | pending |
| Reboot state, if relevant | pending |
| Evidence artifact directory | docs/qa/artifacts/ |
| Notes | pending |

### Android Verification Cases

| ID | Case | Procedure | Expected result | Actual result | Result | Evidence artifact path | Follow-up |
|---|---|---|---|---|---|---|---|
| android-01 | 1-minute alarm | Schedule one test alarm for 1 minute from now on a real device. | Alarm fires at the scheduled time and can be dismissed with only the current alarm stopped. | pending | pending | pending | pending |
| android-02 | Short-interval 3 alarms | Schedule three alarms at short test intervals for the same Wake Plan. Dismiss the first alarm. | All three alarms fire in order; dismissing one does not cancel the remaining alarms. | pending | pending | pending | pending |
| android-03 | 5-minute interval, 13-equivalent alarms | Schedule a 60-minute Wake Plan with 5-minute interval, or a documented time-compressed equivalent if real-time verification is deferred. | Thirteen occurrences can be reserved and each expected occurrence fires or is represented by approved platform recurrence semantics. | pending | pending | pending | pending |
| android-04 | Individual cancel | Schedule at least three future occurrences, cancel one middle occurrence, then wait through the sequence. | The canceled occurrence does not fire; non-canceled future occurrences still fire. | pending | pending | pending | pending |
| android-05 | Plan cancel | Schedule a Wake Plan with multiple future occurrences, then cancel the plan. | No future occurrence for that Wake Plan fires after cancellation. | pending | pending | pending | pending |
| android-06 | Locked device | Schedule an alarm, lock the device before the due time, and keep the device locked until delivery. | Alarm is visible/audible in the lock-state behavior expected for the API and can be dismissed. | pending | pending | pending | pending |
| android-07 | Terminated app | Schedule an alarm, fully terminate the app, then wait until the scheduled time. | Alarm fires without the app being foregrounded manually; native fallback is available if Flutter startup fails. | pending | pending | pending | pending |
| android-08 | Permission denied | Deny exact alarm and/or notification permission, then attempt scheduling and delivery. | App detects the denied state, scheduling does not silently succeed, and the user-facing state can explain the blocker. | pending | pending | pending | pending |
| android-09 | Reboot restore | Schedule future alarms, reboot the device before delivery, unlock as required by the test setup, then wait through the scheduled time. | Required future alarms are restored after reboot or the restore limitation is recorded as release-blocking. | pending | pending | pending | pending |

## Cross-Platform Comparison

| Topic | iOS finding | Android finding | MVP impact | Follow-up |
|---|---|---|---|---|
| Multiple same-plan alarms | blocked pending real-device test; API can model multiple UUID-backed alarms, but 13-count limit/delivery is unverified | pending | pending for iOS until device evidence exists | Test 3 and 13 concrete AlarmKit alarms on iOS 26+ real device. |
| Dismiss one, future alarms remain | blocked pending runtime dismissal test; independent IDs make the model plausible | pending | pending for iOS until dismiss-one behavior is verified | Stop/dismiss first alarm on device and verify future IDs remain scheduled and fire. |
| Individual occurrence cancel | API-feasible by per-occurrence UUID and `cancel(id:)`; runtime result blocked | pending | pending for iOS until cancel sequence is verified | Cancel one middle occurrence on device and verify neighboring deliveries. |
| Whole-plan cancel | API-feasible by iterating stored occurrence UUIDs; no grouped plan cancel found in inspected SDK surface | pending | pending for iOS until no-future-delivery is verified | Cancel all UUIDs for a plan on device and verify none fire. |
| Locked-device delivery | blocked: requires iOS 26+ real device | pending | pending for iOS; blocks reliability claim | Run lock-screen delivery test on device. |
| Terminated-app delivery | blocked: requires iOS 26+ real device and an installable iOS target/probe | pending | pending for iOS; blocks reliability claim | Run terminated-app delivery test on device. |
| Permission-denied handling | API surface exposes authorization states, but denied scheduling behavior is untested | pending | pending for iOS; blocks silent-failure risk assessment | Deny AlarmKit authorization on device and record scheduling behavior. |
| Silent / Focus behavior | blocked: requires iOS 26+ real device | not applicable | pending for iOS; blocks reliability claim | Run Silent and Focus cases on device. |
| Reboot restore behavior | not applicable | pending | pending | pending |
| Real-device coverage | blocked: no iOS 26+ real device or compatible runtime available in worker environment | pending | iOS MVP approval blocked | Provide iOS 26+ real device/compatible runtime and rerun all iOS cases. |

## Failure Decision Points

Record a decision here for every `fail` or release-blocking `pending` result.

| Decision point | Trigger | Options | Decision | Owner | Follow-up |
|---|---|---|---|---|---|
| Rolling reservation | A platform cannot reserve all future repeating occurrences reliably, or recurrence cannot express skip/cancel semantics. | Use a rolling reservation window; reduce native reservation horizon; block MVP until solved. | iOS local API evidence favors rolling concrete occurrence reservation because inspected AlarmKit recurrence exposes weekly/never but no exception-date or next-skip API; final decision pending 13-alarm device limit test. | iOS spike owner / Wave 3 implementer | Measure 13 concrete alarms and recurring plan behavior on iOS 26+ real device. |
| OS recurrence | Native weekly or relative recurrence cannot preserve Wake Plan semantics, especially next-skip and individual cancel. | Avoid OS recurrence and schedule concrete occurrences; use OS recurrence only for approved simple cases; block recurrence MVP. | For iOS MVP next-skip, avoid relying solely on OS recurrence unless later evidence finds exception semantics; schedule concrete occurrences for the next reservation horizon. | iOS spike owner / Wave 3 implementer | Confirm whether AlarmKit recurrence can be mixed with per-occurrence cancel without breaking future weeks. |
| Omitted features | A feature such as 3-minute intervals, custom sound, silent/Focus bypass, reboot restore, or native fallback is not feasible in MVP scope. | Mark omitted from MVP; move to post-MVP; platform-limit the MVP; block release if core alarm reliability is affected. | iOS Silent/Focus behavior and custom sound remain unverified; no omission decision can be approved without device evidence. | iOS spike owner | Run Silent/Focus and sound behavior tests on iOS 26+ real device. |
| MVP delay / release blocking | Any core path cannot be verified on a real device: scheduling, firing, dismiss-one-keeps-future, edit/delete cancel, lock state, terminated app, or permission warning. | Delay MVP; run another spike; platform-limit only with explicit product decision; redesign alarm strategy. | iOS release remains blocked: no real-device evidence for scheduling, delivery, dismiss-one-keeps-future, cancel, locked, terminated, denied permission, Silent, or Focus cases. | Product / Orchestrator | Provide iOS 26+ real device or compatible runtime and rerun this spike before approving iOS MVP alarm reliability. |

## Release Readiness Criteria

Mark each item `pass`, `fail`, `pending`, or `not applicable`.

| Criterion | iOS | Android | Release impact |
|---|---|---|---|
| 1-minute real-device alarm verified. | pending: blocked by no iOS 26+ real device/compatible runtime | pending | Blocks MVP for that platform. |
| Short-interval three-alarm sequence verified. | pending: blocked by no iOS 26+ real device/compatible runtime | pending | Blocks MVP if dismissing one cancels future alarms. |
| 13-equivalent schedule verified or explicitly approved with documented equivalent evidence. | pending: API limit/delivery unverified; `maximumLimitReached` exists | pending | Blocks 60-minute / 5-minute default if unverified. |
| Individual cancel verified. | pending: API typechecks, runtime behavior blocked | pending | Blocks edit and occurrence-level repair flows if unverified. |
| Whole-plan cancel verified. | pending: per-ID cancel model typechecks, runtime behavior blocked | pending | Blocks delete/edit MVP if unverified. |
| Locked-device delivery verified. | pending: blocked by no iOS 26+ real device | pending | Blocks alarm reliability claim if unverified. |
| Terminated-app delivery verified. | pending: blocked by no iOS 26+ real device and no installable iOS target | pending | Blocks alarm reliability claim if unverified. |
| Permission-denied state detected and explainable. | pending: authorization states typecheck, denied behavior blocked | pending | Blocks release if denied permissions can fail silently. |
| Silent / Focus behavior verified or documented with release-blocking mitigation. | pending: blocked by no iOS 26+ real device | not applicable | Blocks iOS reliability claim if unverified. |
| Reboot restore verified or documented with release-blocking mitigation. | not applicable | pending | Blocks Android alarm reliability claim if unverified. |
| Simulator/emulator-only evidence is not used as approval. | pass: no simulator evidence was used as iOS approval | pending | Blocks approval until real-device evidence exists. |

## Evidence Log

Append one row per run or artifact.

| Timestamp | Platform | Case ID | Device / OS | Artifact path | Result | Notes |
|---|---|---|---|---|---|---|
| 2026-07-06 | iOS | environment | Local Mac / Xcode 26.6 / iPhoneOS 26.5 SDK; no real device; simulator runtime iOS 18.0 only | command evidence only; no file artifact | pending | `xcrun devicectl list devices` found no devices. `xcrun simctl list runtimes available` showed only iOS 18.0. |
| 2026-07-06 | iOS | api-surface | Local Mac / Xcode 26.6 / iPhoneOS 26.5 SDK | command evidence only; no file artifact | pending | `swiftc -target arm64-apple-ios26.0 -sdk iPhoneOS26.5.sdk -typecheck` passed for authorization, fixed schedule, weekly relative recurrence, UUID IDs, cancel, stop, and alarms list. No runtime scheduling was performed. |

## Final Spike Recommendation

- iOS recommendation: blocked for MVP approval until an iOS 26+ real device or compatible runtime validates delivery and lifecycle behavior. Local API evidence supports proceeding with a rolling concrete occurrence design for the next implementation spike, but not release approval.
- Android recommendation: pending
- Platform-limited MVP recommendation, if any: pending
- Required changes before implementation: for iOS, provide an installable minimal AlarmKit probe or production iOS target on an iOS 26+ real device; schedule concrete UUID-backed occurrences; store all UUIDs per Wake Plan for individual and plan cancel; avoid relying solely on weekly recurrence for next-skip until exception semantics are proven.
- Out-of-scope follow-up issues: pending
