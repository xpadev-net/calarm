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
| Device model | pending |
| Device identifier or QA label | pending |
| OS version | pending |
| Build version / commit | pending |
| Build configuration | pending |
| Alarm API under test | AlarmKit |
| Alarm permission state | pending |
| Notification permission state | pending |
| Sound / silent mode setting | pending |
| Focus / Do Not Disturb setting | pending |
| Lock state during test | pending |
| App state during test | pending |
| Network state, if relevant | pending |
| Evidence artifact directory | docs/qa/artifacts/ |
| Notes | pending |

### iOS Verification Cases

| ID | Case | Procedure | Expected result | Actual result | Result | Evidence artifact path | Follow-up |
|---|---|---|---|---|---|---|---|
| ios-01 | 1-minute alarm | Schedule one test alarm for 1 minute from now on a real device. | Alarm fires at the scheduled time and can be dismissed with only the current alarm stopped. | pending | pending | pending | pending |
| ios-02 | Short-interval 3 alarms | Schedule three alarms at short test intervals for the same Wake Plan. Dismiss the first alarm. | All three alarms fire in order; dismissing one does not cancel the remaining alarms. | pending | pending | pending | pending |
| ios-03 | 5-minute interval, 13-equivalent alarms | Schedule a 60-minute Wake Plan with 5-minute interval, or a documented time-compressed equivalent if real-time verification is deferred. | Thirteen occurrences can be reserved and each expected occurrence fires or is represented by approved platform recurrence semantics. | pending | pending | pending | pending |
| ios-04 | Individual cancel | Schedule at least three future occurrences, cancel one middle occurrence, then wait through the sequence. | The canceled occurrence does not fire; non-canceled future occurrences still fire. | pending | pending | pending | pending |
| ios-05 | Plan cancel | Schedule a Wake Plan with multiple future occurrences, then cancel the plan. | No future occurrence for that Wake Plan fires after cancellation. | pending | pending | pending | pending |
| ios-06 | Locked device | Schedule an alarm, lock the device before the due time, and keep the device locked until delivery. | Alarm is visible/audible in the lock-state behavior expected for the API and can be dismissed. | pending | pending | pending | pending |
| ios-07 | Terminated app | Schedule an alarm, fully terminate the app, then wait until the scheduled time. | Alarm fires without the app being foregrounded manually. | pending | pending | pending | pending |
| ios-08 | Permission denied | Deny alarm and/or notification permission, then attempt scheduling and delivery. | App detects the denied state, scheduling does not silently succeed, and the user-facing state can explain the blocker. | pending | pending | pending | pending |
| ios-09 | Silent / Focus mode | Enable Silent mode and the Focus / Do Not Disturb condition under test, schedule an alarm, then wait until delivery. | Alarm delivery behavior is recorded as acceptable or release-blocking for the stated mode; failures have a user-facing mitigation or block release. | pending | pending | pending | pending |

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
| Multiple same-plan alarms | pending | pending | pending | pending |
| Dismiss one, future alarms remain | pending | pending | pending | pending |
| Individual occurrence cancel | pending | pending | pending | pending |
| Whole-plan cancel | pending | pending | pending | pending |
| Locked-device delivery | pending | pending | pending | pending |
| Terminated-app delivery | pending | pending | pending | pending |
| Permission-denied handling | pending | pending | pending | pending |
| Silent / Focus behavior | pending | not applicable | pending | pending |
| Reboot restore behavior | not applicable | pending | pending | pending |
| Real-device coverage | pending | pending | pending | pending |

## Failure Decision Points

Record a decision here for every `fail` or release-blocking `pending` result.

| Decision point | Trigger | Options | Decision | Owner | Follow-up |
|---|---|---|---|---|---|
| Rolling reservation | A platform cannot reserve all future repeating occurrences reliably, or recurrence cannot express skip/cancel semantics. | Use a rolling reservation window; reduce native reservation horizon; block MVP until solved. | pending | pending | pending |
| OS recurrence | Native weekly or relative recurrence cannot preserve Wake Plan semantics, especially next-skip and individual cancel. | Avoid OS recurrence and schedule concrete occurrences; use OS recurrence only for approved simple cases; block recurrence MVP. | pending | pending | pending |
| Omitted features | A feature such as 3-minute intervals, custom sound, silent/Focus bypass, reboot restore, or native fallback is not feasible in MVP scope. | Mark omitted from MVP; move to post-MVP; platform-limit the MVP; block release if core alarm reliability is affected. | pending | pending | pending |
| MVP delay / release blocking | Any core path cannot be verified on a real device: scheduling, firing, dismiss-one-keeps-future, edit/delete cancel, lock state, terminated app, or permission warning. | Delay MVP; run another spike; platform-limit only with explicit product decision; redesign alarm strategy. | pending | pending | pending |

## Release Readiness Criteria

Mark each item `pass`, `fail`, `pending`, or `not applicable`.

| Criterion | iOS | Android | Release impact |
|---|---|---|---|
| 1-minute real-device alarm verified. | pending | pending | Blocks MVP for that platform. |
| Short-interval three-alarm sequence verified. | pending | pending | Blocks MVP if dismissing one cancels future alarms. |
| 13-equivalent schedule verified or explicitly approved with documented equivalent evidence. | pending | pending | Blocks 60-minute / 5-minute default if unverified. |
| Individual cancel verified. | pending | pending | Blocks edit and occurrence-level repair flows if unverified. |
| Whole-plan cancel verified. | pending | pending | Blocks delete/edit MVP if unverified. |
| Locked-device delivery verified. | pending | pending | Blocks alarm reliability claim if unverified. |
| Terminated-app delivery verified. | pending | pending | Blocks alarm reliability claim if unverified. |
| Permission-denied state detected and explainable. | pending | pending | Blocks release if denied permissions can fail silently. |
| Silent / Focus behavior verified or documented with release-blocking mitigation. | pending | not applicable | Blocks iOS reliability claim if unverified. |
| Reboot restore verified or documented with release-blocking mitigation. | not applicable | pending | Blocks Android alarm reliability claim if unverified. |
| Simulator/emulator-only evidence is not used as approval. | pending | pending | Blocks approval until real-device evidence exists. |

## Evidence Log

Append one row per run or artifact.

| Timestamp | Platform | Case ID | Device / OS | Artifact path | Result | Notes |
|---|---|---|---|---|---|
| pending | pending | pending | pending | pending | pending | pending |

## Final Spike Recommendation

- iOS recommendation: pending
- Android recommendation: pending
- Platform-limited MVP recommendation, if any: pending
- Required changes before implementation: pending
- Out-of-scope follow-up issues: pending
