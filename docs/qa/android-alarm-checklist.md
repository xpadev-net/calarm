# Android Alarm Bridge QA Checklist

Runtime approval status: BLOCKED for release until real Android API 36 device/runtime evidence is captured. Wave 8 implementation evidence below does not approve Android runtime behavior.

| Case | Status | Evidence / blocker |
|---|---|---|
| MethodChannel schemaVersion 1 connects to `net.xpadev.calarm/native_alarm` | PASS | Kotlin `AndroidAlarmBridge` is registered from `MainActivity` and validates `schemaVersion: 1`. |
| Capability lookup reports exact alarm setting | PASS | `getCapability` calls `AlarmManager.canScheduleExactAlarms()` on Android 12+ and returns `requiresExactAlarmPermission`. |
| Capability lookup reports notification setting | PASS | `getCapability` checks `POST_NOTIFICATIONS` on Android 13+ and returns `requiresNotificationPermission`. |
| Capability lookup reports full-screen intent setting | PASS | `getCapability` checks `NotificationManager.canUseFullScreenIntent()` on Android 14+ and returns `requiresFullScreenIntentPermission`. |
| Schedule multiple concrete occurrences | BLOCKED | Implementation schedules each occurrence with `AlarmManager.setAlarmClock`, but no Android API 36 runtime/device is available in this worker environment to verify delivery. |
| Return platformAlarmId per scheduled occurrence | PASS | Successful schedule rows return deterministic `android:{wakePlanId}:{occurrenceId}` identities. |
| Cancel a single occurrence by stored platformAlarmId | BLOCKED | Implementation cancels the matching `PendingIntent` and removes native mirror state, but no Android API 36 runtime/device is available to verify OS alarm removal. |
| Cancel all resolved occurrences for a plan | BLOCKED | `cancelPlan` uses the same resolved occurrence/platform identity rows as `cancelOccurrences`; no Android API 36 runtime/device is available to verify OS alarm removal. |
| Schedule a test alarm | BLOCKED | Implementation maps `fireAfterMillis` to a native one-off alarm, but no Android API 36 runtime/device is available to verify delivery. |
| Alarm receiver notification and full-screen stop UI fallback | BLOCKED | `AlarmReceiver` posts a high-priority alarm notification with full-screen `AlarmStopActivity`; no Android API 36 runtime/device is available to verify lock-screen behavior. |
| Reboot/package-replace/direct-boot restore | BLOCKED | `BootReceiver` is direct-boot aware and restores future alarms from the device-protected native mirror after boot, locked boot, and package replacement when exact alarms are allowed. No Android API 36 runtime/device is available to verify reboot restore. |
| Exact-alarm permission re-grant restore | PASS | `BootReceiver` handles `ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED`; the synchronized restore path re-arms each stable PendingIntent identity idempotently after permission is restored. |
| Corrupt/expired mirror cleanup | PASS | Restore removes malformed, mismatched, and expired device-protected mirror rows without scheduling them. |
| Runtime permission request flow | BLOCKED | `requestPermissionIfNeeded` opens exact-alarm settings, the Android 14+ app-specific full-screen settings action with package URI and app-details fallback, or notification/channel settings where needed. No Android API 36 device/runtime is available to verify user flow or post-return status. |
| Settings inline warning for denied/missing Android alarm readiness | PASS | `rtk flutter test test/features/settings test/core/platform` covers exact alarm, notification, full-screen intent, and notification-channel warnings in the settings path. |
| Android exact alarm permission-denial runtime warning | BLOCKED | Dart/UI path has widget coverage, but no Android API 36 device/runtime is available to revoke exact alarm permission and verify the live capability response. |
| Android notification permission-denial runtime warning | BLOCKED | Dart/UI path has widget coverage, but no Android API 36 device/runtime is available to revoke notification permission and verify the live capability response. |
| Android full-screen intent OS-setting runtime warning | BLOCKED | Dart/UI path has widget coverage, but no Android API 36 device/runtime is available to revoke full-screen intent access and verify the live capability response. |
| Android notification channel OS-setting runtime warning | BLOCKED | Native capability now checks the wake alarm notification channel, but no Android API 36 device/runtime is available to disable the channel and verify the live warning. |
| Android 1-minute test alarm settings action | BLOCKED | Widget/controller tests verify `fireAfter: Duration(minutes: 1)` and failure preservation, but no Android API 36 runtime/device is available to verify delivery. |

Implementation limits recorded:

- Native mirror state is stored in device-protected app `SharedPreferences`; clearing app data removes restore state.
- Restore only re-arms alarms whose stored `scheduledAtMillis` is still in the future.
- If exact alarm permission is revoked at boot, restore exits without rescheduling; capability lookup surfaces the missing permission.
- Locked boot reads only the device-protected mirror and does not require credential-protected app storage to be unlocked.
- Duplicate boot, package-replace, and permission-state broadcasts reuse the same stable PendingIntent identities and do not create duplicate alarms.
- Full-screen UI is a minimal native fallback for Wave 8 and does not yet integrate Flutter alarm dismissal state.
