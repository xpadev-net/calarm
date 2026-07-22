package dev.xpa.calarm

import android.app.AlarmManager
import android.app.Application
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Vibrator
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.time.Instant
import org.json.JSONException
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowAlarmManager
import org.robolectric.shadows.ShadowVibrator

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [32])
class AndroidInventoryTest {
    private lateinit var context: Context

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        mirrorPreferences().edit().clear().commit()
        credentialPreferences().edit().clear().commit()
        replacementPreferences().edit().clear().commit()
        replacementCredentialPreferences().edit().clear().commit()
        ShadowAlarmManager.reset()
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        Shadows.shadowOf(context.applicationContext as Application).clearNextStartedActivities()
        ShadowVibrator.reset()
        context.getSystemService(NotificationManager::class.java)
            .createNotificationChannel(AlarmNotificationChannel.create())
    }

    @After
    fun tearDown() {
        mirrorPreferences().edit().clear().commit()
        credentialPreferences().edit().clear().commit()
        replacementPreferences().edit().clear().commit()
        replacementCredentialPreferences().edit().clear().commit()
        ShadowAlarmManager.reset()
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        Shadows.shadowOf(context.applicationContext as Application).clearNextStartedActivities()
        ShadowVibrator.reset()
    }

    @Test
    fun `stable reservation identity round trips and legacy rows default to occurrence`() {
        val request = alarmRequest(
            platformAlarmId = "android:reservation:stable-1",
            reservationId = "stable-1",
            occurrenceId = "occurrence-1",
        )

        val restored = AlarmRequest.fromJson(request.toJson())

        assertEquals("stable-1", restored.reservationId)
        assertEquals(request.platformAlarmId, restored.platformAlarmId)
        assertEquals(
            "occurrence-legacy",
            AlarmRequest.fromJson(
                request.toJson().let { json ->
                    json.remove("reservationId")
                    json.put("occurrenceId", "occurrence-legacy")
                    json.put("platformAlarmId", "android:plan:occurrence-legacy")
                    json
                },
            ).reservationId,
        )
    }

    @Test
    fun `persisted reservation identity rejects non-string JSON values`() {
        val json = alarmRequest("android:plan:typed-reservation").toJson()
            .put("reservationId", 42)

        assertThrows(IllegalArgumentException::class.java) {
            AlarmRequest.fromJson(json)
        }
    }

    @Test
    fun `persisted reservation identity rejects null object and blank values`() {
        listOf<Any?>(JSONObject.NULL, JSONObject(), "").forEach { value ->
            val json = alarmRequest("android:plan:typed-reservation").toJson()
                .put("reservationId", value)
            assertThrows(IllegalArgumentException::class.java) {
                AlarmRequest.fromJson(json)
            }
        }
    }

    @Test
    fun `inventory removes expired and corrupt rows and does not return them as success`() {
        val expired = alarmRequest(
            platformAlarmId = "android:plan:expired-inventory",
            scheduledAtMillis = System.currentTimeMillis() - 1_000,
        )
        mirrorPreferences().edit()
            .putString(expired.platformAlarmId, expired.toJson().toString())
            .putString("android:plan:corrupt-inventory", "not-json")
            .commit()

        val snapshot = AlarmStore(context).inventory(context, System.currentTimeMillis())

        assertTrue(snapshot.requests.isEmpty())
        assertTrue(snapshot.corruptKeys.contains("android:plan:corrupt-inventory"))
        assertFalse(mirrorPreferences().contains(expired.platformAlarmId))
        assertFalse(mirrorPreferences().contains("android:plan:corrupt-inventory"))
    }

    @Test
    fun `inventory reports a matching-key noncanonical platform override as corrupt`() {
        val platformAlarmId = "android:corrupt:override"
        val request = alarmRequest(
            platformAlarmId = platformAlarmId,
            reservationId = "canonical-reservation",
            occurrenceId = "canonical-occurrence",
            wakePlanId = "canonical-plan",
        )
        mirrorPreferences().edit()
            .putString(platformAlarmId, request.toJson().toString())
            .commit()

        val result = CapturingResult()
        AndroidAlarmBridge(context).onMethodCall(
            MethodCall("getInventory", mapOf("schemaVersion" to 1)),
            result,
        )

        assertEquals("CORRUPT", result.errorCode)
        assertFalse(mirrorPreferences().contains(platformAlarmId))
    }

    @Test
    fun `noncanonical matching-key rows have no receiver or cancel side effects and are not restored`() {
        val platformAlarmId = "android:corrupt:override-lifecycle"
        val request = alarmRequest(
            platformAlarmId = platformAlarmId,
            reservationId = "lifecycle-reservation",
            occurrenceId = "lifecycle-occurrence",
            wakePlanId = "lifecycle-plan",
            vibrationEnabled = true,
        )
        mirrorPreferences().edit()
            .putString(platformAlarmId, request.toJson().toString())
            .commit()

        AlarmReceiver().onReceive(
            context,
            Shadows.shadowOf(AlarmIntents.receiver(context, platformAlarmId)).savedIntent,
        )
        assertTrue(
            context.getSystemService(NotificationManager::class.java)
                .activeNotifications
                .isEmpty(),
        )
        assertNull(Shadows.shadowOf(context.applicationContext as Application).peekNextStartedActivity())
        assertNull(shadowVibrator().getVibrationAttributesFromLastVibration())

        val cancelResult = CapturingResult()
        AndroidAlarmBridge(context).onMethodCall(
            MethodCall(
                "cancelOccurrences",
                mapOf(
                    "schemaVersion" to 1,
                    "alarms" to listOf(
                        mapOf(
                            "occurrenceId" to request.occurrenceId,
                            "reservationId" to request.reservationId,
                            "platformAlarmId" to platformAlarmId,
                        ),
                    ),
                ),
            ),
            cancelResult,
        )
        val cancelRow = (cancelResult.value as Map<*, *>)
            .let { it["alarms"] as List<*> }
            .single() as Map<*, *>
        assertEquals("failure", cancelRow["status"])
        assertEquals("nativeError", cancelRow["failureReason"])
        assertTrue(mirrorPreferences().contains(platformAlarmId))

        AlarmRestore.restoreForTest(context, context) {
            throw AssertionError("Noncanonical rows must not be restored")
        }
        assertFalse(mirrorPreferences().contains(platformAlarmId))
    }

    @Test
    fun `inventory reports duplicate stable identities without inventing rows`() {
        val first = alarmRequest(
            platformAlarmId = "android:plan:occurrence-1",
            reservationId = "duplicate",
            occurrenceId = "occurrence-1",
        )
        val second = alarmRequest(
            platformAlarmId = "android:plan:occurrence-2",
            reservationId = "duplicate",
            occurrenceId = "occurrence-2",
        )
        mirrorPreferences().edit()
            .putString(first.platformAlarmId, first.toJson().toString())
            .putString(second.platformAlarmId, second.toJson().toString())
            .commit()

        val snapshot = AlarmStore(context).inventory(context, System.currentTimeMillis())

        assertTrue(snapshot.requests.isEmpty())
        assertTrue(snapshot.duplicateIdentity!!.contains("duplicate"))
    }

    @Test
    fun `ringing state remains inventoried after one-shot pending intent is consumed`() {
        val bridge = AndroidAlarmBridge(context)
        val result = CapturingResult()
        bridge.onMethodCall(
            MethodCall(
                "scheduleOccurrences",
                scheduleArguments(
                    occurrenceId = "ringing-pending-intent",
                    reservationId = "ringing-pending-reservation",
                    wakePlanId = "ringing-pending-plan",
                ),
            ),
            result,
        )
        assertNull(result.errorCode)
        val operation = scheduledAlarms().single().operation!!
        operation.send()
        val firedIntent = Shadows.shadowOf(operation).savedIntent
        context.sendBroadcast(firedIntent)
        AlarmReceiver().onReceive(context, firedIntent)

        val snapshot = AlarmStore(context).inventory(context, System.currentTimeMillis())

        assertEquals(AlarmState.RINGING.value, snapshot.status(snapshot.requests.single()))
        assertNotNull(AlarmStore(context).get("android:reservation:ringing-pending-reservation"))
    }

    @Test
    fun `restore keeps an active ringing row after its scheduled time`() {
        val request = alarmRequest(
            "android:plan:ringing-restore",
            scheduledAtMillis = System.currentTimeMillis() - 1_000,
            state = AlarmState.RINGING,
        )
        assertTrue(AlarmStore(context).put(request))

        AlarmRestore.restoreForTest(context, context) {
            throw AssertionError("Ringing rows must not be rearmed during restore")
        }

        assertEquals(AlarmState.RINGING, AlarmStore(context).get(request.platformAlarmId)?.state)
    }

    @Test
    fun `test alarm cancellation accepts the synthetic test identity only`() {
        val testRequest = alarmRequest(
            platformAlarmId = "android:test:test-123",
            reservationId = "test-123",
            occurrenceId = "test-123",
            wakePlanId = "test",
        ).copy(isTest = true, platformAlarmIdOverride = "android:test:test-123")
        assertTrue(AlarmStore(context).put(testRequest))
        val bridge = AndroidAlarmBridge(context)
        val result = CapturingResult()

        bridge.onMethodCall(
            MethodCall(
                "cancelOccurrences",
                mapOf(
                    "schemaVersion" to 1,
                    "alarms" to listOf(
                        mapOf(
                            "occurrenceId" to "ci-smoke-test-alarm",
                            "reservationId" to "ci-smoke-test-alarm",
                            "platformAlarmId" to testRequest.platformAlarmId,
                        ),
                    ),
                ),
            ),
            result,
        )

        assertNull(result.errorCode)
        assertEquals(
            "success",
            ((result.value as Map<*, *>)["alarms"] as List<*>).single()
                .let { it as Map<*, *> }["status"],
        )
        assertNull(AlarmStore(context).get(testRequest.platformAlarmId))
    }

    @Test
    fun `misclassified test row cannot bypass cancellation identity`() {
        val request = alarmRequest(
            platformAlarmId = "android:reservation:real-reservation",
            reservationId = "real-reservation",
            occurrenceId = "real-occurrence",
        ).copy(isTest = true)
        assertTrue(AlarmStore(context).put(request))
        val bridge = AndroidAlarmBridge(context)
        val result = CapturingResult()

        bridge.onMethodCall(
            MethodCall(
                "cancelOccurrences",
                mapOf(
                    "schemaVersion" to 1,
                    "alarms" to listOf(
                        mapOf(
                            "occurrenceId" to "wrong-occurrence",
                            "reservationId" to "wrong-reservation",
                            "platformAlarmId" to request.platformAlarmId,
                        ),
                    ),
                ),
            ),
            result,
        )

        assertNull(result.errorCode)
        val response = result.value as Map<*, *>
        val row = (response["alarms"] as List<*>).single() as Map<*, *>
        assertEquals("failure", row["status"])
        assertEquals("invalidRequest", row["failureReason"])
        assertNotNull(AlarmStore(context).get(request.platformAlarmId))
    }

    @Test
    fun `receiver rejects a corrupt mirror payload without mutation`() {
        val lookupPlatformAlarmId = "android:plan:receiver-corrupt"
        val foreign = alarmRequest(
            platformAlarmId = "android:reservation:foreign-ringing",
            reservationId = "receiver-reservation",
            occurrenceId = "receiver-occurrence",
            vibrationEnabled = true,
        )
        mirrorPreferences().edit()
            .putString(lookupPlatformAlarmId, foreign.toJson().toString())
            .commit()

        AlarmReceiver().onReceive(
            context,
            Shadows.shadowOf(AlarmIntents.receiver(context, lookupPlatformAlarmId)).savedIntent,
        )

        assertEquals(
            AlarmState.SCHEDULED,
            AlarmStore(context).get(lookupPlatformAlarmId)?.state,
        )
        assertEquals(foreign.toJson().toString(), mirrorPreferences().getString(lookupPlatformAlarmId, null))
        assertFalse(mirrorPreferences().contains(foreign.platformAlarmId))
        assertTrue(
            context.getSystemService(NotificationManager::class.java)
                .activeNotifications
                .isEmpty(),
        )
        assertNull(Shadows.shadowOf(context.applicationContext as Application).peekNextStartedActivity())
        assertNull(shadowVibrator().getVibrationAttributesFromLastVibration())
    }

    @Test
    fun `mark ringing rejects a corrupt mirror payload without mutation`() {
        val lookupPlatformAlarmId = "android:plan:mark-ringing-corrupt"
        val foreign = alarmRequest(
            platformAlarmId = "android:reservation:foreign-mark-ringing",
            reservationId = "mark-ringing-reservation",
            occurrenceId = "mark-ringing-occurrence",
        )
        mirrorPreferences().edit()
            .putString(lookupPlatformAlarmId, foreign.toJson().toString())
            .commit()

        val store = AlarmStore(context)

        assertFalse(store.markRinging(lookupPlatformAlarmId))
        assertEquals(
            foreign.toJson().toString(),
            mirrorPreferences().getString(lookupPlatformAlarmId, null),
        )
        assertFalse(mirrorPreferences().contains(foreign.platformAlarmId))
        assertEquals(
            AlarmState.SCHEDULED,
            store.get(lookupPlatformAlarmId)?.state,
        )
    }

    @Test
    fun `new stable reservation adopts a matching legacy mirror row`() {
        val legacy = alarmRequest(
            platformAlarmId = "android:plan:legacy-occurrence",
            reservationId = "legacy-occurrence",
            occurrenceId = "legacy-occurrence",
        )
        assertTrue(AlarmStore(context).put(legacy))
        val bridge = AndroidAlarmBridge(context)
        val result = CapturingResult()

        bridge.onMethodCall(
            MethodCall(
                "scheduleOccurrences",
                scheduleArguments(
                    occurrenceId = legacy.occurrenceId,
                    reservationId = "stable-reservation",
                    wakePlanId = legacy.wakePlanId,
                ),
            ),
            result,
        )

        assertNull(result.errorCode)
        val row = ((result.value as Map<*, *>)["occurrences"] as List<*>).single() as Map<*, *>
        assertEquals("success", row["status"])
        assertEquals(legacy.platformAlarmId, row["platformAlarmId"])
        val inventory = AlarmStore(context).inventory(context, System.currentTimeMillis())
        assertEquals(1, inventory.requests.size)
        assertEquals("stable-reservation", inventory.requests.single().reservationId)
    }

    @Test
    fun `adopted legacy reservation is idempotent through ringing retry`() {
        val legacy = alarmRequest(
            platformAlarmId = "android:plan:adopted-occurrence",
            reservationId = "adopted-occurrence",
            occurrenceId = "adopted-occurrence",
        )
        assertTrue(AlarmStore(context).put(legacy))
        val bridge = AndroidAlarmBridge(context)
        val arguments = scheduleArguments(
            occurrenceId = legacy.occurrenceId,
            reservationId = "adopted-reservation",
            wakePlanId = legacy.wakePlanId,
        )

        val first = CapturingResult()
        bridge.onMethodCall(MethodCall("scheduleOccurrences", arguments), first)
        assertNull(first.errorCode)
        val firstPayload = first.value as Map<*, *>
        val firstOccurrence = firstPayload["occurrences"] as List<*>
        val firstRow = firstOccurrence.single() as Map<*, *>
        assertEquals("success", firstRow["status"])
        assertEquals(legacy.platformAlarmId, firstRow["platformAlarmId"])

        val duplicate = CapturingResult()
        bridge.onMethodCall(MethodCall("scheduleOccurrences", arguments), duplicate)
        assertNull(duplicate.errorCode)
        val duplicatePayload = duplicate.value as Map<*, *>
        val duplicateRow = (duplicatePayload["occurrences"] as List<*>).single() as Map<*, *>
        assertEquals("success", duplicateRow["status"])

        AlarmReceiver().onReceive(
            context,
            Shadows.shadowOf(AlarmIntents.receiver(context, legacy.platformAlarmId)).savedIntent,
        )
        assertEquals(AlarmState.RINGING, AlarmStore(context).get(legacy.platformAlarmId)?.state)

        val scheduledBeforeRetry = scheduledAlarms()
        ShadowAlarmManager.setCanScheduleExactAlarms(false)
        val ringingRetry = CapturingResult()
        bridge.onMethodCall(MethodCall("scheduleOccurrences", arguments), ringingRetry)
        assertNull(ringingRetry.errorCode)
        val ringingRetryPayload = ringingRetry.value as Map<*, *>
        val ringingRetryRow = (ringingRetryPayload["occurrences"] as List<*>).single() as Map<*, *>
        assertEquals("success", ringingRetryRow["status"])
        assertEquals("adopted-reservation", ringingRetryRow["reservationId"])
        assertEquals("adopted-occurrence", ringingRetryRow["occurrenceId"])
        assertEquals(legacy.platformAlarmId, ringingRetryRow["platformAlarmId"])
        assertEquals(scheduledBeforeRetry, scheduledAlarms())
        assertEquals(AlarmState.RINGING, AlarmStore(context).get(legacy.platformAlarmId)?.state)
    }

    @Test
    fun `adopted legacy reservation accepts occurrence-compatible cancel`() {
        val legacy = alarmRequest(
            platformAlarmId = "android:plan:cancel-adopted-occurrence",
            reservationId = "cancel-adopted-occurrence",
            occurrenceId = "cancel-adopted-occurrence",
        )
        assertTrue(AlarmStore(context).put(legacy))
        val bridge = AndroidAlarmBridge(context)
        val scheduleResult = CapturingResult()
        bridge.onMethodCall(
            MethodCall(
                "scheduleOccurrences",
                scheduleArguments(
                    occurrenceId = legacy.occurrenceId,
                    reservationId = "cancel-adopted-reservation",
                    wakePlanId = legacy.wakePlanId,
                ),
            ),
            scheduleResult,
        )

        val cancelResult = CapturingResult()
        bridge.onMethodCall(
            MethodCall(
                "cancelOccurrences",
                mapOf(
                    "schemaVersion" to 1,
                    "alarms" to listOf(
                        mapOf(
                            "occurrenceId" to legacy.occurrenceId,
                            "platformAlarmId" to legacy.platformAlarmId,
                        ),
                    ),
                ),
            ),
            cancelResult,
        )

        assertNull(scheduleResult.errorCode)
        assertNull(cancelResult.errorCode)
        val row = (cancelResult.value as Map<*, *>)
            .let { it["alarms"] as List<*> }
            .single() as Map<*, *>
        assertEquals("success", row["status"])
        assertNull(AlarmStore(context).get(legacy.platformAlarmId))
    }

    @Test
    fun `ringing legacy adoption persists stable inventory without rearming`() {
        val scheduledAtMillis = System.currentTimeMillis() + 60_000
        val legacy = alarmRequest(
            platformAlarmId = "android:plan:ringing-adopted-occurrence",
            reservationId = "ringing-adopted-occurrence",
            occurrenceId = "ringing-adopted-occurrence",
            state = AlarmState.RINGING,
            scheduledAtMillis = scheduledAtMillis,
        )
        assertTrue(AlarmStore(context).put(legacy))
        val bridge = AndroidAlarmBridge(context)
        val arguments = scheduleArguments(
            occurrenceId = legacy.occurrenceId,
            reservationId = "ringing-adopted-reservation",
            wakePlanId = legacy.wakePlanId,
            scheduledAtMillis = scheduledAtMillis,
        )
        val scheduledBeforeRetry = scheduledAlarms()

        val first = CapturingResult()
        bridge.onMethodCall(MethodCall("scheduleOccurrences", arguments), first)
        assertNull(first.errorCode)
        val firstPayload = first.value as Map<*, *>
        val firstRow = (firstPayload["occurrences"] as List<*>).single() as Map<*, *>
        assertEquals("success", firstRow["status"])
        assertEquals("ringing-adopted-reservation", firstRow["reservationId"])
        assertEquals(legacy.occurrenceId, firstRow["occurrenceId"])
        assertEquals(legacy.platformAlarmId, firstRow["platformAlarmId"])
        assertEquals(scheduledBeforeRetry, scheduledAlarms())

        val firstInventoryResult = CapturingResult()
        bridge.onMethodCall(
            MethodCall("getInventory", mapOf("schemaVersion" to 1)),
            firstInventoryResult,
        )
        assertNull(firstInventoryResult.errorCode)
        val firstInventoryResponse = firstInventoryResult.value as Map<*, *>
        val firstInventoryRow =
            (firstInventoryResponse["reservations"] as List<*>).single() as Map<*, *>
        assertEquals("ringing-adopted-reservation", firstInventoryRow["reservationId"])
        assertEquals(legacy.occurrenceId, firstInventoryRow["occurrenceId"])
        assertEquals(legacy.wakePlanId, firstInventoryRow["wakePlanId"])
        assertEquals(legacy.platformAlarmId, firstInventoryRow["platformAlarmId"])
        assertEquals(AlarmState.RINGING.value, firstInventoryRow["status"])
        assertFalse(mirrorPreferences().contains("android:reservation:ringing-adopted-reservation"))

        val duplicate = CapturingResult()
        bridge.onMethodCall(MethodCall("scheduleOccurrences", arguments), duplicate)
        assertNull(duplicate.errorCode)
        val duplicatePayload = duplicate.value as Map<*, *>
        val duplicateRow = (duplicatePayload["occurrences"] as List<*>).single() as Map<*, *>
        assertEquals("success", duplicateRow["status"])
        assertEquals("ringing-adopted-reservation", duplicateRow["reservationId"])
        assertEquals(legacy.occurrenceId, duplicateRow["occurrenceId"])
        assertEquals(legacy.wakePlanId, duplicateRow["wakePlanId"])
        assertEquals(legacy.platformAlarmId, duplicateRow["platformAlarmId"])
        assertEquals(scheduledBeforeRetry, scheduledAlarms())

        val duplicateInventoryResult = CapturingResult()
        bridge.onMethodCall(
            MethodCall("getInventory", mapOf("schemaVersion" to 1)),
            duplicateInventoryResult,
        )
        assertNull(duplicateInventoryResult.errorCode)
        val duplicateInventoryResponse = duplicateInventoryResult.value as Map<*, *>
        val duplicateInventoryRow =
            (duplicateInventoryResponse["reservations"] as List<*>).single() as Map<*, *>
        assertEquals("ringing-adopted-reservation", duplicateInventoryRow["reservationId"])
        assertEquals(legacy.occurrenceId, duplicateInventoryRow["occurrenceId"])
        assertEquals(legacy.wakePlanId, duplicateInventoryRow["wakePlanId"])
        assertEquals(legacy.platformAlarmId, duplicateInventoryRow["platformAlarmId"])
        assertEquals(AlarmState.RINGING.value, duplicateInventoryRow["status"])
    }

    @Test
    fun `legacy adoption rejects a foreign platform key without mutation`() {
        val legacy = alarmRequest(
            platformAlarmId = "android:plan:corrupt-occurrence",
            reservationId = "corrupt-occurrence",
            occurrenceId = "corrupt-occurrence",
        )
        val foreign = legacy.copy(platformAlarmIdOverride = "android:reservation:foreign")
        mirrorPreferences().edit()
            .putString(legacy.platformAlarmId, foreign.toJson().toString())
            .commit()
        val bridge = AndroidAlarmBridge(context)
        val result = CapturingResult()

        bridge.onMethodCall(
            MethodCall(
                "scheduleOccurrences",
                scheduleArguments(
                    occurrenceId = legacy.occurrenceId,
                    reservationId = "stable-corrupt",
                    wakePlanId = legacy.wakePlanId,
                ),
            ),
            result,
        )

        assertNull(result.errorCode)
        val response = result.value as Map<*, *>
        val row = (response["occurrences"] as List<*>).single() as Map<*, *>
        assertEquals("failure", row["status"])
        assertEquals("nativeError", row["failureReason"])
        assertTrue(scheduledAlarms().isEmpty())
        assertEquals(
            foreign.toJson().toString(),
            mirrorPreferences().getString(legacy.platformAlarmId, null),
        )
        assertFalse(mirrorPreferences().contains("android:reservation:stable-corrupt"))
    }

    @Test
    fun `cancel rejects a row whose payload platform key differs`() {
        val platformAlarmId = "android:reservation:cancel-corrupt"
        val foreign = alarmRequest(
            platformAlarmId = "android:reservation:foreign-cancel",
            reservationId = "cancel-reservation",
            occurrenceId = "cancel-occurrence",
        )
        mirrorPreferences().edit()
            .putString(platformAlarmId, foreign.toJson().toString())
            .commit()
        val bridge = AndroidAlarmBridge(context)
        val result = CapturingResult()

        bridge.onMethodCall(
            MethodCall(
                "cancelOccurrences",
                mapOf(
                    "schemaVersion" to 1,
                    "alarms" to listOf(
                        mapOf(
                            "occurrenceId" to foreign.occurrenceId,
                            "reservationId" to foreign.reservationId,
                            "platformAlarmId" to platformAlarmId,
                        ),
                    ),
                ),
            ),
            result,
        )

        assertNull(result.errorCode)
        val response = result.value as Map<*, *>
        val row = (response["alarms"] as List<*>).single() as Map<*, *>
        assertEquals("failure", row["status"])
        assertEquals("nativeError", row["failureReason"])
        assertTrue(mirrorPreferences().contains(platformAlarmId))
        assertTrue(scheduledAlarms().isEmpty())
    }

    @Test
    fun `duplicate schedule after firing preserves the ringing state`() {
        val bridge = AndroidAlarmBridge(context)
        val arguments = scheduleArguments(
            occurrenceId = "occurrence-ringing-retry",
            reservationId = "reservation-ringing-retry",
            wakePlanId = "plan-ringing-retry",
        )
        val first = CapturingResult()
        bridge.onMethodCall(MethodCall("scheduleOccurrences", arguments), first)
        assertNull(first.errorCode)
        val firstRow = ((first.value as Map<*, *>)["occurrences"] as List<*>).single() as Map<*, *>
        val platformAlarmId = firstRow["platformAlarmId"] as String

        AlarmReceiver().onReceive(
            context,
            Shadows.shadowOf(AlarmIntents.receiver(context, platformAlarmId)).savedIntent,
        )
        assertEquals(
            AlarmState.RINGING,
            AlarmStore(context).get(platformAlarmId)?.state,
        )

        val retry = CapturingResult()
        bridge.onMethodCall(MethodCall("scheduleOccurrences", arguments), retry)

        assertNull(retry.errorCode)
        assertEquals(AlarmState.RINGING, AlarmStore(context).get(platformAlarmId)?.state)
    }

    @Test
    fun `schedule persistence failure control flow cancels the same receiver and preserves prior mirror`() {
        val request = alarmRequest(
            platformAlarmId = "android:plan:rollback",
            occurrenceId = "rollback",
        )
        assertTrue(AlarmStore(context).put(request))
        val priorJson = mirrorPreferences().getString(request.platformAlarmId, null)
        var armCount = 0
        var cancelCount = 0
        val bridge = AndroidAlarmBridge(context)

        val failed = bridge.armAndPersistForTest(
            request = request,
            platformAlarmId = request.platformAlarmId,
            arm = { armCount += 1 },
            persist = { false },
            cancel = { cancelCount += 1 },
        )
        assertEquals("failure", failed["status"])
        assertEquals("nativeError", failed["failureReason"])
        assertEquals(1, armCount)
        assertEquals(1, cancelCount)
        assertEquals(priorJson, mirrorPreferences().getString(request.platformAlarmId, null))

        val exceptionFailure = bridge.armAndPersistForTest(
            request = request,
            platformAlarmId = request.platformAlarmId,
            arm = { armCount += 1 },
            persist = { throw JSONException("toJson failure") },
            cancel = { cancelCount += 1 },
        )
        assertEquals("failure", exceptionFailure["status"])
        assertEquals("nativeError", exceptionFailure["failureReason"])
        assertEquals(2, armCount)
        assertEquals(2, cancelCount)
        assertEquals(priorJson, mirrorPreferences().getString(request.platformAlarmId, null))
    }

    @Test
    fun `schedule and cancel duplicate calls preserve one native reservation`() {
        val bridge = AndroidAlarmBridge(context)
        val arguments = scheduleArguments(
            occurrenceId = "occurrence-bridge",
            reservationId = "reservation-bridge",
            wakePlanId = "plan-bridge",
        )
        val first = CapturingResult()
        bridge.onMethodCall(MethodCall("scheduleOccurrences", arguments), first)
        assertNull(first.errorCode)
        val firstResponse = first.value as Map<*, *>
        val firstRow = (firstResponse["occurrences"] as List<*>).single() as Map<*, *>
        assertEquals("success", firstRow["status"])
        assertEquals("reservation-bridge", firstRow["reservationId"])

        val second = CapturingResult()
        bridge.onMethodCall(MethodCall("scheduleOccurrences", arguments), second)
        assertNull(second.errorCode)
        assertEquals(1, scheduledAlarms().size)

        val inventory = CapturingResult()
        bridge.onMethodCall(MethodCall("getInventory", mapOf("schemaVersion" to 1)), inventory)
        assertNull(inventory.errorCode)
        val inventoryResponse = inventory.value as Map<*, *>
        val inventoryRow = (inventoryResponse["reservations"] as List<*>).single() as Map<*, *>
        assertEquals("reservation-bridge", inventoryRow["reservationId"])
        assertEquals("scheduled", inventoryRow["status"])

        val cancelArguments = mapOf<String, Any?>(
            "schemaVersion" to 1,
            "alarms" to listOf(
                mapOf<String, Any?>(
                    "occurrenceId" to "occurrence-bridge",
                    "reservationId" to "reservation-bridge",
                    "platformAlarmId" to firstRow["platformAlarmId"],
                ),
            ),
        )
        val cancel = CapturingResult()
        bridge.onMethodCall(MethodCall("cancelOccurrences", cancelArguments), cancel)
        assertNull(cancel.errorCode)
        assertEquals("success", ((cancel.value as Map<*, *>)["alarms"] as List<*>).single().let { it as Map<*, *> }["status"])

        val duplicateCancel = CapturingResult()
        bridge.onMethodCall(MethodCall("cancelOccurrences", cancelArguments), duplicateCancel)
        assertNull(duplicateCancel.errorCode)
        assertEquals("success", ((duplicateCancel.value as Map<*, *>)["alarms"] as List<*>).single().let { it as Map<*, *> }["status"])
    }

    @Test
    fun `replacement recovery converges every crash seam and lost reply`() {
        data class CrashSeam(
            val name: String,
            val phase: AlarmReplacementPhase,
            val armCandidate: Boolean,
            val mirrorCommitted: Boolean,
            val expectedNewWinner: Boolean,
        )

        val seams = listOf(
            CrashSeam(
                name = "pre-arm",
                phase = AlarmReplacementPhase.STAGING,
                armCandidate = false,
                mirrorCommitted = false,
                expectedNewWinner = false,
            ),
            CrashSeam(
                name = "post-arm-pre-phase",
                phase = AlarmReplacementPhase.STAGING,
                armCandidate = true,
                mirrorCommitted = false,
                expectedNewWinner = false,
            ),
            CrashSeam(
                name = "post-arm-pre-mirror",
                phase = AlarmReplacementPhase.CANDIDATE_ARMED,
                armCandidate = true,
                mirrorCommitted = false,
                expectedNewWinner = false,
            ),
            CrashSeam(
                name = "mirror-commit-pre-retirement",
                phase = AlarmReplacementPhase.OLD_RETIRED,
                armCandidate = true,
                mirrorCommitted = true,
                expectedNewWinner = true,
            ),
        )

        for (seam in seams) {
            setUp()
            val reservationId = "recovery-${seam.name}"
            val old = alarmRequest(
                platformAlarmId = "android:reservation:$reservationId",
                reservationId = reservationId,
                occurrenceId = "$reservationId-old",
                wakePlanId = "recovery-plan",
            )
            val newTemplate = old.copy(occurrenceId = "$reservationId-new")
            val candidate = newTemplate.copy(
                platformAlarmIdOverride = AlarmRequest.replacementPlatformAlarmId(newTemplate),
            )
            val store = AlarmStore(context)
            assertTrue(store.put(old))
            armForRecoveryTest(old)
            if (seam.armCandidate) armForRecoveryTest(candidate)
            if (seam.mirrorCommitted) {
                assertTrue(store.replace(old.platformAlarmId, candidate.platformAlarmId, candidate))
            }
            assertTrue(
                AlarmReplacementJournalStore(context).save(
                    AlarmReplacementJournal(old = old, new = candidate, phase = seam.phase),
                ),
            )
            assertNotNull(replacementPreferences().getString("active", null))
            assertFalse(replacementCredentialPreferences().contains("active"))

            val first = AndroidAlarmReplacementRecovery.reconcile(context, context)
            val firstWinner = AlarmStore(context).inventory(context, System.currentTimeMillis())
                .requests.single()
            val second = AndroidAlarmReplacementRecovery.reconcile(context, context)
            val secondWinner = AlarmStore(context).inventory(context, System.currentTimeMillis())
                .requests.single()

            assertTrue(seam.name, first.isSuccess)
            assertTrue("${seam.name} lost reply", second.isSuccess)
            assertEquals(
                if (seam.expectedNewWinner) candidate.occurrenceId else old.occurrenceId,
                firstWinner.occurrenceId,
            )
            assertEquals(firstWinner, secondWinner)
            assertEquals(listOf(firstWinner.platformAlarmId), scheduledAlarmIds())
            assertNull(AlarmReplacementJournalStore(context).load())
        }
    }

    @Test
    fun `replacement recovery preserves the exact due alarm being admitted`() {
        for (phase in listOf(
            AlarmReplacementPhase.STAGING,
            AlarmReplacementPhase.CANDIDATE_ARMED,
        )) {
            setUp()
            val reservationId = "due-admission-${phase.name.lowercase()}"
            val old = alarmRequest(
                platformAlarmId = "android:reservation:$reservationId",
                reservationId = reservationId,
                occurrenceId = "$reservationId-old",
                wakePlanId = "due-admission-plan",
                scheduledAtMillis = System.currentTimeMillis() - 1_000,
            )
            val newTemplate = old.copy(
                occurrenceId = "$reservationId-new",
                scheduledAtMillis = System.currentTimeMillis() + 60_000,
                targetAtMillis = System.currentTimeMillis() + 60_000,
            )
            val candidate = newTemplate.copy(
                platformAlarmIdOverride = AlarmRequest.replacementPlatformAlarmId(newTemplate),
            )
            assertTrue(AlarmStore(context).put(old))
            armForRecoveryTest(old)
            if (phase == AlarmReplacementPhase.CANDIDATE_ARMED) armForRecoveryTest(candidate)
            assertTrue(
                AlarmReplacementJournalStore(context).save(
                    AlarmReplacementJournal(old = old, new = candidate, phase = phase),
                ),
            )
            context.getSystemService(AlarmManager::class.java)
                .cancel(AlarmIntents.receiver(context, old.platformAlarmId))

            val recovery = AndroidAlarmReplacementRecovery.reconcile(
                context,
                context,
                admittingPlatformAlarmId = old.platformAlarmId,
            )

            assertTrue(recovery.isSuccess)
            assertNotNull(AlarmStore(context).get(old.platformAlarmId))
            assertNull(AlarmStore(context).get(candidate.platformAlarmId))
            assertTrue(scheduledAlarmIds().isEmpty())
            assertNull(AlarmReplacementJournalStore(context).load())
        }
    }

    @Test
    fun `committed due candidate remains authoritative during its admission`() {
        val dueAt = System.currentTimeMillis() - 1_000
        val old = alarmRequest(
            platformAlarmId = "android:reservation:committed-due-slot",
            reservationId = "committed-due-slot",
            occurrenceId = "committed-due-old",
            wakePlanId = "committed-due-plan",
            scheduledAtMillis = dueAt,
        )
        val newTemplate = old.copy(occurrenceId = "committed-due-new")
        val candidate = newTemplate.copy(
            platformAlarmIdOverride = AlarmRequest.replacementPlatformAlarmId(newTemplate),
        )
        assertTrue(AlarmStore(context).put(candidate))
        armForRecoveryTest(candidate)
        assertTrue(
            AlarmReplacementJournalStore(context).save(
                AlarmReplacementJournal(
                    old = old,
                    new = candidate,
                    phase = AlarmReplacementPhase.OLD_RETIRED,
                ),
            ),
        )
        context.getSystemService(AlarmManager::class.java)
            .cancel(AlarmIntents.receiver(context, candidate.platformAlarmId))

        val recovery = AndroidAlarmReplacementRecovery.reconcile(
            context,
            context,
            admittingPlatformAlarmId = candidate.platformAlarmId,
        )

        assertTrue(recovery.isSuccess)
        assertNotNull(AlarmStore(context).get(candidate.platformAlarmId))
        assertTrue(scheduledAlarmIds().isEmpty())
        assertNull(AlarmReplacementJournalStore(context).load())
    }

    @Test
    fun `unrelated admission identity fails closed and retains replacement evidence`() {
        val old = alarmRequest(
            platformAlarmId = "android:reservation:admission-owner-slot",
            reservationId = "admission-owner-slot",
            occurrenceId = "admission-owner-old",
            wakePlanId = "admission-owner-plan",
        )
        val newTemplate = old.copy(occurrenceId = "admission-owner-new")
        val candidate = newTemplate.copy(
            platformAlarmIdOverride = AlarmRequest.replacementPlatformAlarmId(newTemplate),
        )
        assertTrue(AlarmStore(context).put(old))
        armForRecoveryTest(old)
        assertTrue(
            AlarmReplacementJournalStore(context).save(
                AlarmReplacementJournal(old = old, new = candidate),
            ),
        )
        val evidence = replacementPreferences().getString("active", null)

        val recovery = AndroidAlarmReplacementRecovery.reconcile(
            context,
            context,
            admittingPlatformAlarmId = "android:reservation:unrelated-slot",
        )

        assertFalse(recovery.isSuccess)
        assertNotNull(AlarmStore(context).get(old.platformAlarmId))
        assertEquals(evidence, replacementPreferences().getString("active", null))
        assertEquals(listOf(old.platformAlarmId), scheduledAlarmIds())
    }

    @Test
    fun `corrupt and ambiguous replacement journals fail closed and retain evidence`() {
        val retained = alarmRequest(
            platformAlarmId = "android:reservation:retained-recovery-slot",
            reservationId = "retained-recovery-slot",
            occurrenceId = "retained-recovery-occurrence",
            wakePlanId = "retained-recovery-plan",
        )
        assertTrue(AlarmStore(context).put(retained))
        val invalidJournals = listOf(
            "not-json",
            JSONObject()
                .put("schemaVersion", 1)
                .put("old", retained.toJson())
                .put(
                    "new",
                    retained.copy(
                        occurrenceId = "ambiguous-occurrence",
                        reservationId = "different-reservation",
                    ).toJson(),
                )
                .put("phase", AlarmReplacementPhase.CANDIDATE_ARMED.name)
                .toString(),
        )

        for (journal in invalidJournals) {
            assertTrue(replacementPreferences().edit().putString("active", journal).commit())

            val first = AndroidAlarmReplacementRecovery.reconcile(context, context)
            val second = AndroidAlarmReplacementRecovery.reconcile(context, context)

            assertFalse(first.isSuccess)
            assertFalse(second.isSuccess)
            assertNotNull(AlarmStore(context).get(retained.platformAlarmId))
            assertEquals(journal, replacementPreferences().getString("active", null))
            assertEquals(0, scheduledAlarms().size)
        }
    }

    @Test
    fun `expired replacement recovery retires both generations in every phase`() {
        for (phase in AlarmReplacementPhase.values()) {
            setUp()
            val expiredAt = System.currentTimeMillis() - 1_000
            val reservationId = "expired-recovery-${phase.name.lowercase()}"
            val old = alarmRequest(
                platformAlarmId = "android:reservation:$reservationId",
                reservationId = reservationId,
                occurrenceId = "$reservationId-old",
                wakePlanId = "expired-recovery-plan",
                scheduledAtMillis = expiredAt,
            )
            val newTemplate = old.copy(occurrenceId = "$reservationId-new")
            val candidate = newTemplate.copy(
                platformAlarmIdOverride = AlarmRequest.replacementPlatformAlarmId(newTemplate),
            )
            assertTrue(AlarmStore(context).put(old))
            assertTrue(AlarmStore(context).put(candidate))
            armForRecoveryTest(old)
            armForRecoveryTest(candidate)
            assertTrue(
                AlarmReplacementJournalStore(context).save(
                    AlarmReplacementJournal(old = old, new = candidate, phase = phase),
                ),
            )

            val first = AndroidAlarmReplacementRecovery.reconcile(context, context)
            val second = AndroidAlarmReplacementRecovery.reconcile(context, context)

            assertTrue(first.isSuccess)
            assertTrue(second.isSuccess)
            assertNull(AlarmStore(context).get(old.platformAlarmId))
            assertNull(AlarmStore(context).get(candidate.platformAlarmId))
            assertEquals(0, scheduledAlarms().size)
            assertNull(AlarmReplacementJournalStore(context).load())
        }
    }

    private fun armForRecoveryTest(request: AlarmRequest) {
        context.getSystemService(AlarmManager::class.java).setAlarmClock(
            AlarmManager.AlarmClockInfo(
                request.scheduledAtMillis,
                AlarmIntents.showIntent(context, request.platformAlarmId),
            ),
            AlarmIntents.receiver(context, request.platformAlarmId),
        )
    }

    private fun scheduleArguments(
        occurrenceId: String,
        reservationId: String,
        wakePlanId: String,
        scheduledAtMillis: Long = System.currentTimeMillis() + 60_000,
    ): Map<String, Any?> {
        val scheduledAt = Instant.ofEpochMilli(scheduledAtMillis)
        return mapOf<String, Any?>(
            "schemaVersion" to 1,
            "occurrences" to listOf(
                mapOf<String, Any?>(
                    "occurrenceId" to occurrenceId,
                    "reservationId" to reservationId,
                    "wakePlanId" to wakePlanId,
                    "scheduledAt" to scheduledAt.toString(),
                    "targetAt" to scheduledAt.toString(),
                    "indexInPlan" to 0,
                    "totalInPlan" to 1,
                    "soundId" to "default",
                    "vibrationEnabled" to false,
                ),
            ),
        )
    }

    private fun mirrorPreferences() = deviceProtectedContext()
        .getSharedPreferences("native_alarm_store", Context.MODE_PRIVATE)

    private fun credentialPreferences() = context
        .getSharedPreferences("native_alarm_store", Context.MODE_PRIVATE)

    private fun replacementPreferences() = deviceProtectedContext()
        .getSharedPreferences("native_alarm_replacement_journal", Context.MODE_PRIVATE)

    private fun replacementCredentialPreferences() = context
        .getSharedPreferences("native_alarm_replacement_journal", Context.MODE_PRIVATE)

    private fun deviceProtectedContext(): Context {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.createDeviceProtectedStorageContext()
        } else {
            context
        }
    }

    private fun scheduledAlarms(): List<ShadowAlarmManager.ScheduledAlarm> {
        return Shadows.shadowOf(context.getSystemService(AlarmManager::class.java)).scheduledAlarms
    }

    private fun scheduledAlarmIds(): List<String> {
        return scheduledAlarms().mapNotNull { alarm ->
            Shadows.shadowOf(alarm.operation).savedIntent
                .getStringExtra(AlarmIntents.EXTRA_PLATFORM_ALARM_ID)
        }
    }

    private fun shadowVibrator(): ShadowVibrator {
        return Shadows.shadowOf(context.getSystemService(Vibrator::class.java))
    }

    private fun alarmRequest(
        platformAlarmId: String,
        reservationId: String? = null,
        occurrenceId: String? = null,
        wakePlanId: String? = null,
        scheduledAtMillis: Long = System.currentTimeMillis() + 60_000,
        state: AlarmState = AlarmState.SCHEDULED,
        vibrationEnabled: Boolean = false,
    ): AlarmRequest {
        val identifiersOmitted = occurrenceId == null && reservationId == null && wakePlanId == null
        val resolvedOccurrenceId = if (identifiersOmitted) {
            platformAlarmId.substringAfterLast(':')
        } else {
            occurrenceId ?: "occurrence"
        }
        val resolvedReservationId = reservationId ?: "occurrence"
        val resolvedWakePlanId = wakePlanId ?: "plan"
        return AlarmRequest(
            occurrenceId = resolvedOccurrenceId,
            reservationId = resolvedReservationId,
            wakePlanId = resolvedWakePlanId,
            scheduledAtMillis = scheduledAtMillis,
            targetAtMillis = scheduledAtMillis,
            soundId = "default",
            vibrationEnabled = vibrationEnabled,
            platformAlarmIdOverride = platformAlarmId,
            state = state,
        )
    }

    private class CapturingResult : MethodChannel.Result {
        var value: Any? = null
        var errorCode: String? = null

        override fun success(result: Any?) {
            value = result
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            this.errorCode = errorCode
        }

        override fun notImplemented() {
            errorCode = "NOT_IMPLEMENTED"
        }
    }
}
