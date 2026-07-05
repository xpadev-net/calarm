# Native Alarm MethodChannel

This document fixes the Dart/native contract for the wake alarm gateway.

- Channel name: `net.xpadev.calarm/native_alarm`
- Schema version: `1`
- Every request and response Map includes `schemaVersion: 1`.
- Native implementations must not schedule production alarms from this document alone; Wave 8 owns production native scheduling.
- `cancelPlan` receives repository-resolved occurrence/platform alarm identities. Native code must not receive only a logical `wakePlanId` and must not query Flutter persistence.

## Common Enums

Permission status strings:

- `unknown`
- `notDetermined`
- `authorized`
- `denied`
- `restricted`
- `unavailable`

Permission request status strings:

- `granted`
- `denied`
- `unavailable`

Schedule result status strings:

- `success`
- `permissionMissing`
- `osConstraint`
- `partialFailure`
- `failure`

Schedule occurrence status strings:

- `success`
- `failure`

Schedule failure reason strings:

- `permissionMissing`
- `osConstraint`
- `invalidRequest`
- `nativeError`
- `unavailable`
- `unknown`

Cancel result status strings:

- `success`
- `partialFailure`
- `failure`

Cancel alarm status strings:

- `success`
- `failure`

Cancel failure reason strings:

- `missingPlatformAlarmId`
- `invalidRequest`
- `nativeError`
- `unavailable`
- `unknown`

Native `PlatformException.code` values may use lower camel case or upper snake case. Dart maps unknown native error codes to `nativeError`.

## `getCapability`

Request:

```json
{
  "schemaVersion": 1
}
```

Response:

```json
{
  "schemaVersion": 1,
  "permissionStatus": "authorized",
  "canScheduleAlarms": true,
  "canRequestPermission": true,
  "maxPendingAlarms": 64,
  "requiresExactAlarmPermission": false,
  "requiresNotificationPermission": false,
  "requiresFullScreenIntentPermission": false,
  "supportsTestAlarm": true
}
```

`maxPendingAlarms` is nullable. Optional boolean capability fields default to `false` on the Dart side when absent except `supportsTestAlarm`, which defaults to `true` to match the domain contract. Native responses should still send every boolean explicitly.

## `requestPermissionIfNeeded`

Request:

```json
{
  "schemaVersion": 1
}
```

Response:

```json
{
  "schemaVersion": 1,
  "status": "granted",
  "permissionStatus": "authorized"
}
```

## `scheduleOccurrences`

Request:

```json
{
  "schemaVersion": 1,
  "occurrences": [
    {
      "occurrenceId": "occ-1",
      "wakePlanId": "plan-1",
      "scheduledAt": "2026-07-06T21:00:00.000Z",
      "targetAt": "2026-07-06T22:00:00.000Z",
      "indexInPlan": 0,
      "totalInPlan": 2,
      "soundId": "default",
      "vibrationEnabled": true
    }
  ]
}
```

`scheduledAt` and `targetAt` are UTC ISO-8601 strings.

Response:

```json
{
  "schemaVersion": 1,
  "occurrences": [
    {
      "occurrenceId": "occ-1",
      "wakePlanId": "plan-1",
      "status": "success",
      "platformAlarmId": "platform-occ-1"
    },
    {
      "occurrenceId": "occ-2",
      "wakePlanId": "plan-1",
      "status": "failure",
      "failureReason": "osConstraint",
      "failureMessage": "Quota exceeded."
    }
  ]
}
```

The response must include one row per native result. Dart correlates rows back to the original request by `(occurrenceId, wakePlanId)`. Missing rows become per-occurrence `nativeError` failures. Extra rows or rows for the wrong wake plan are invalid.

On method-level `PlatformException`, Dart converts the error to one failed `ScheduleOccurrenceResult` for each requested occurrence.

## `cancelOccurrences`

Request:

```json
{
  "schemaVersion": 1,
  "alarms": [
    {
      "occurrenceId": "occ-1",
      "platformAlarmId": "platform-occ-1"
    }
  ]
}
```

Response:

```json
{
  "schemaVersion": 1,
  "alarms": [
    {
      "occurrenceId": "occ-1",
      "platformAlarmId": "platform-occ-1",
      "status": "success"
    }
  ]
}
```

Dart correlates cancel rows by `(occurrenceId, platformAlarmId)`. The `platformAlarmId` is required and must be the stored identity returned by a previous successful or recoverable schedule result.

On method-level `PlatformException`, Dart converts the error to one failed `CancelAlarmResult` for each requested alarm.

## `cancelPlan`

Request:

```json
{
  "schemaVersion": 1,
  "alarms": [
    {
      "occurrenceId": "occ-1",
      "platformAlarmId": "platform-occ-1"
    },
    {
      "occurrenceId": "occ-2",
      "platformAlarmId": "platform-occ-2"
    }
  ]
}
```

Response:

```json
{
  "schemaVersion": 1,
  "alarms": [
    {
      "occurrenceId": "occ-1",
      "platformAlarmId": "platform-occ-1",
      "status": "success"
    },
    {
      "occurrenceId": "occ-2",
      "platformAlarmId": "platform-occ-2",
      "status": "failure",
      "failureReason": "nativeError",
      "failureMessage": "Already gone."
    }
  ]
}
```

`cancelPlan` uses the same cancel row schema as `cancelOccurrences`. The only semantic difference is caller intent: the repository resolves all stored native alarm identities for a plan before crossing the native boundary.

## `scheduleTestAlarm`

Request:

```json
{
  "schemaVersion": 1,
  "fireAfterMillis": 60000,
  "soundId": "default",
  "vibrationEnabled": true
}
```

Success response:

```json
{
  "schemaVersion": 1,
  "status": "success",
  "platformAlarmId": "test-platform-id"
}
```

Failure response:

```json
{
  "schemaVersion": 1,
  "status": "failure",
  "failureReason": "unavailable",
  "failureMessage": "Test alarms are not supported."
}
```

On method-level `PlatformException`, Dart converts the error to a failed `TestAlarmScheduleResult`.
