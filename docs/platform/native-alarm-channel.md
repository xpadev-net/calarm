# Native Alarm MethodChannel

This document fixes the Dart/native contract for the wake alarm gateway.

- Channel name: `net.xpadev.calarm/native_alarm`
- Schema version: `1`
- Every request and response Map includes `schemaVersion: 1`.
- The stable logical reservation identity is `reservationId`. It is additive
  and defaults to `occurrenceId` in Dart, so older native implementations can
  ignore it while newer implementations use it as their durable idempotency
  key. Native responses may omit it during rollout; Dart then correlates the
  legacy row by `occurrenceId` and restores the requested `reservationId`.
- `getInventory` is an additive read method. Older native implementations may
  report `unavailable`; callers must not infer that the native inventory is
  empty from an unavailable or failed read.
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
  "requiresNotificationChannelSetup": false,
  "supportsTestAlarm": true,
  "supportsInventory": true
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
      "reservationId": "reservation-occ-1",
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
      "reservationId": "reservation-occ-1",
      "wakePlanId": "plan-1",
      "status": "success",
      "platformAlarmId": "platform-occ-1"
    },
    {
      "occurrenceId": "occ-2",
      "reservationId": "reservation-occ-2",
      "wakePlanId": "plan-1",
      "status": "failure",
      "failureReason": "osConstraint",
      "failureMessage": "Quota exceeded."
    }
  ]
}
```

The response must include one row per native result. Dart correlates rows back to the original request by `(occurrenceId, wakePlanId)`. Missing rows become per-occurrence `nativeError` failures. Extra rows or rows for the wrong wake plan are invalid.

Dart also rejects a batch that reuses any stable reservation, logical
occurrence, or non-null native platform identity. A native platform identity
must never be reported as belonging to two logical reservations.

`reservationId` is the stable logical identity that native implementations
must preserve across duplicate schedule calls, process restarts, and inventory
reads. A successful response should echo it. Omitting it is accepted only for
rolling compatibility with the original schema, and Dart treats the row as a
legacy response for the requested occurrence.

On method-level `PlatformException`, Dart converts the error to one failed `ScheduleOccurrenceResult` for each requested occurrence.

## `cancelOccurrences`

Request:

```json
{
  "schemaVersion": 1,
  "alarms": [
    {
      "occurrenceId": "occ-1",
      "reservationId": "reservation-occ-1",
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
      "reservationId": "reservation-occ-1",
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
      "reservationId": "reservation-occ-1",
      "platformAlarmId": "platform-occ-1"
    },
    {
      "occurrenceId": "occ-2",
      "reservationId": "reservation-occ-2",
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
      "reservationId": "reservation-occ-1",
      "platformAlarmId": "platform-occ-1",
      "status": "success"
    },
    {
      "occurrenceId": "occ-2",
      "reservationId": "reservation-occ-2",
      "platformAlarmId": "platform-occ-2",
      "status": "failure",
      "failureReason": "nativeError",
      "failureMessage": "Already gone."
    }
  ]
}
```

`cancelPlan` uses the same cancel row schema as `cancelOccurrences`. The only semantic difference is caller intent: the repository resolves all stored native alarm identities for a plan before crossing the native boundary.

## `getInventory`

Request:

```json
{
  "schemaVersion": 1
}
```

Success response:

```json
{
  "schemaVersion": 1,
  "reservations": [
    {
      "reservationId": "reservation-occ-1",
      "occurrenceId": "occ-1",
      "wakePlanId": "plan-1",
      "platformAlarmId": "platform-occ-1",
      "status": "scheduled"
    }
  ]
}
```

Inventory statuses are `scheduled`, `ringing`, `stopped`, and `unknown`.
Every row must contain non-empty stable, logical, and native identities. Dart
returns a failed `corrupt` inventory result for malformed rows or an
unsupported schema, and a failed `unavailable` result when an older native
binary does not expose the method.

Reconciliation is deliberately conservative:

- `missing`: an expected `reservationId` is absent from the native rows.
- `duplicate`: the same stable identity appears more than once in native rows
  or in the expected set, or distinct rows reuse a platform alarm or logical
  occurrence identity.
- `unknown`: a native row has a new stable identity for an occurrence Dart
  already knows, so it must not be adopted automatically.
- `extra`: a well-formed native row is unrelated to the expected set and must
  not be treated as a Flutter reservation.
- `corrupt`: a row is malformed or its occurrence/plan metadata conflicts with
  Dart's expected identity.
- `readFailure`: the inventory read itself was unavailable or failed; this is
  not evidence that any expected reservation is missing.

Any issue makes the reconciliation non-authoritative. Callers may display or
repair the issue, but must not convert it into a successful schedule/cancel
operation.

### Durable inventory authority and repair

Each reconciliation pass reads one native inventory snapshot and compares it
with the complete eligible Drift occurrence inventory. Native inventory is
authoritative only for native existence; Drift remains authoritative for plan
intent, occurrence timing, user suppression, and whether a reservation is
still desired.

For an authoritative snapshot:

- An active native row whose `(reservationId, occurrenceId, wakePlanId)` tuple
  exactly matches a canonical Drift occurrence is adopted, including replacing
  a stale `platformAlarmId`. This also closes schedule-success/lost-reply and
  post-result Drift-write windows after restart.
- Authoritative absence clears stale native identity. A future desired
  occurrence is rescheduled through its stable `reservationId`; a pending user
  disable becomes disabled; ambiguous forward-compatible state remains marked
  for recovery.
- An active native row with no occurrence row may be adopted only when its
  stable identity exactly names a canonical desired occurrence for a known
  plan. Other active rows for known plans are owned orphans and are cancelled
  with their complete exact identity.
- Rows for unknown plans and inactive native statuses are retained. An inactive
  row matching a known Drift identity blocks clearing or rescheduling that
  plan; it is not authoritative absence. Native stop and ringing selection
  remain a separate lifecycle reconciliation concern.

Unavailable reads, corrupt rows, duplicate identities, and conflicting tuples
make the snapshot non-authoritative. Such a pass performs no inventory-driven
adoption, clearing, or cancellation, returns `recoveryRequired` for affected
plans, and may still continue independent non-destructive scheduling work.
Persisted plan or occurrence rows that cannot be decoded likewise block repair
for their recorded plan and stable occurrence identities. They are retained as
authority evidence rather than filtered into apparent absence; matching native
rows must not be adopted or cancelled until the Drift corruption is resolved.
Identity conflicts block every decoded, raw, and native plan participant before
any affected scheduling or repair can run.
Repeated startup and resume passes must be serialized and idempotent; a failed
plan repair must not prevent later plans in the same pass from making safe
progress.

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
