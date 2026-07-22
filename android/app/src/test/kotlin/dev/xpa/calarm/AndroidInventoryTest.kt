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
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import org.json.JSONException
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
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
        activationCleanupPreferences().edit().clear().commit()
        authorityPreferences().edit().clear().commit()
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
        activationCleanupPreferences().edit().clear().commit()
        authorityPreferences().edit().clear().commit()
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
        armForRecoveryTest(expired)

        val snapshot = AlarmStore(context).inventory(context, System.currentTimeMillis())

        assertTrue(snapshot.requests.isEmpty())
        assertTrue(snapshot.corruptKeys.contains("android:plan:corrupt-inventory"))
        assertFalse(mirrorPreferences().contains(expired.platformAlarmId))
        assertFalse(mirrorPreferences().contains("android:plan:corrupt-inventory"))
        assertTrue(scheduledAlarmIds().isEmpty())
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
            indexInPlan = 0,
            totalInPlan = 2,
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
        assertEquals(0, AlarmStore(context).get(legacy.platformAlarmId)?.indexInPlan)
        assertEquals(2, AlarmStore(context).get(legacy.platformAlarmId)?.totalInPlan)

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

        val newerGeneration = CapturingResult()
        bridge.onMethodCall(
            MethodCall(
                "scheduleOccurrences",
                scheduleArguments(
                    occurrenceId = legacy.occurrenceId,
                    reservationId = "ringing-adopted-reservation",
                    wakePlanId = legacy.wakePlanId,
                    scheduledAtMillis = scheduledAtMillis,
                    reservationGeneration = 1L,
                    indexInPlan = 0,
                    totalInPlan = 2,
                ),
            ),
            newerGeneration,
        )
        val newerGenerationRow =
            (((newerGeneration.value as Map<*, *>)["occurrences"] as List<*>).single())
                as Map<*, *>
        assertEquals("failure", newerGenerationRow["status"])
        assertEquals("invalidRequest", newerGenerationRow["failureReason"])
        assertEquals(0L, AlarmStore(context).get(legacy.platformAlarmId)?.reservationGeneration)
        assertEquals(AlarmState.RINGING, AlarmStore(context).get(legacy.platformAlarmId)?.state)
        assertEquals(scheduledBeforeRetry, scheduledAlarms())

        val mismatch = CapturingResult()
        bridge.onMethodCall(
            MethodCall(
                "scheduleOccurrences",
                scheduleArguments(
                    occurrenceId = legacy.occurrenceId,
                    reservationId = "ringing-adopted-reservation",
                    wakePlanId = legacy.wakePlanId,
                    scheduledAtMillis = scheduledAtMillis,
                    indexInPlan = 1,
                    totalInPlan = 2,
                ),
            ),
            mismatch,
        )
        assertNull(mismatch.errorCode)
        val mismatchPayload = mismatch.value as Map<*, *>
        val mismatchRow = (mismatchPayload["occurrences"] as List<*>).single() as Map<*, *>
        assertEquals("failure", mismatchRow["status"])
        assertEquals("invalidRequest", mismatchRow["failureReason"])
        assertEquals(0, AlarmStore(context).get(legacy.platformAlarmId)?.indexInPlan)
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
    fun `ringing stable identity on a legacy key persists missing metadata once`() {
        val scheduledAtMillis = System.currentTimeMillis() + 60_000
        val stableReservationId = "ringing-stable-legacy-reservation"
        val legacy = alarmRequest(
            platformAlarmId = "android:plan:ringing-stable-legacy-occurrence",
            reservationId = stableReservationId,
            occurrenceId = "ringing-stable-legacy-occurrence",
            state = AlarmState.RINGING,
            scheduledAtMillis = scheduledAtMillis,
        )
        assertNull(legacy.indexInPlan)
        assertNull(legacy.totalInPlan)
        assertTrue(AlarmStore(context).put(legacy))
        val bridge = AndroidAlarmBridge(context)
        val exactArguments = scheduleArguments(
            occurrenceId = legacy.occurrenceId,
            reservationId = stableReservationId,
            wakePlanId = legacy.wakePlanId,
            scheduledAtMillis = scheduledAtMillis,
            indexInPlan = 0,
            totalInPlan = 2,
        )
        val scheduledBeforeRetry = scheduledAlarms()

        val first = CapturingResult()
        bridge.onMethodCall(MethodCall("scheduleOccurrences", exactArguments), first)
        val firstRow = ((first.value as Map<*, *>)["occurrences"] as List<*>)
            .single() as Map<*, *>
        assertEquals("success", firstRow["status"])
        assertEquals(0, AlarmStore(context).get(legacy.platformAlarmId)?.indexInPlan)
        assertEquals(2, AlarmStore(context).get(legacy.platformAlarmId)?.totalInPlan)
        assertEquals(scheduledBeforeRetry, scheduledAlarms())

        val duplicate = CapturingResult()
        bridge.onMethodCall(MethodCall("scheduleOccurrences", exactArguments), duplicate)
        val duplicateRow = ((duplicate.value as Map<*, *>)["occurrences"] as List<*>)
            .single() as Map<*, *>
        assertEquals("success", duplicateRow["status"])
        assertEquals(scheduledBeforeRetry, scheduledAlarms())

        val mismatch = CapturingResult()
        bridge.onMethodCall(
            MethodCall(
                "scheduleOccurrences",
                scheduleArguments(
                    occurrenceId = legacy.occurrenceId,
                    reservationId = stableReservationId,
                    wakePlanId = legacy.wakePlanId,
                    scheduledAtMillis = scheduledAtMillis,
                    indexInPlan = 1,
                    totalInPlan = 2,
                ),
            ),
            mismatch,
        )
        val mismatchRow = ((mismatch.value as Map<*, *>)["occurrences"] as List<*>)
            .single() as Map<*, *>
        assertEquals("failure", mismatchRow["status"])
        assertEquals("invalidRequest", mismatchRow["failureReason"])
        assertEquals(0, AlarmStore(context).get(legacy.platformAlarmId)?.indexInPlan)
        assertEquals(scheduledBeforeRetry, scheduledAlarms())
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
    fun `schedule activation failures compensate or retain durable recovery evidence`() {
        val request = alarmRequest(
            platformAlarmId = "android:reservation:rollback-slot",
            reservationId = "rollback-slot",
            occurrenceId = "rollback-occurrence",
            wakePlanId = "rollback-plan",
        )
        var armCount = 0
        var cancelCount = 0
        val bridge = AndroidAlarmBridge(context)

        val failed = bridge.armAndPersistForTest(
            request = request,
            platformAlarmId = request.platformAlarmId,
            arm = {
                assertNotNull(activationCleanupPreferences().getString("active", null))
                armCount += 1
            },
            persist = { false },
            cancel = {
                cancelCount += 1
                true
            },
        )
        assertEquals("failure", failed["status"])
        assertEquals("nativeError", failed["failureReason"])
        assertEquals(1, armCount)
        assertEquals(1, cancelCount)
        assertNull(AlarmStore(context).get(request.platformAlarmId))

        val exceptionFailure = bridge.armAndPersistForTest(
            request = request,
            platformAlarmId = request.platformAlarmId,
            arm = { armCount += 1 },
            persist = { throw JSONException("toJson failure") },
            cancel = {
                cancelCount += 1
                true
            },
        )
        assertEquals("failure", exceptionFailure["status"])
        assertEquals("nativeError", exceptionFailure["failureReason"])
        assertEquals(2, armCount)
        assertEquals(2, cancelCount)
        assertNull(AlarmStore(context).get(request.platformAlarmId))

        val authorityFailure = bridge.armAndPersistForTest(
            request = request,
            platformAlarmId = request.platformAlarmId,
            arm = { armCount += 1 },
            persist = { AlarmStore(context).put(request) },
            cancel = {
                cancelCount += 1
                true
            },
            recordActive = { false },
        )
        assertEquals("failure", authorityFailure["status"])
        assertEquals("nativeError", authorityFailure["failureReason"])
        assertEquals(3, armCount)
        assertEquals(3, cancelCount)
        assertNull(AlarmStore(context).get(request.platformAlarmId))

        val retired = alarmRequest(
            platformAlarmId = "android:reservation:pending-activation-slot",
            reservationId = "pending-activation-slot",
            occurrenceId = "pending-activation-old",
            wakePlanId = "pending-activation-plan",
            reservationGeneration = 1L,
        )
        val pendingTemplate = retired.copy(
            occurrenceId = "pending-activation-current",
            reservationGeneration = 2L,
        )
        val pending = pendingTemplate.copy(
            platformAlarmIdOverride = AlarmRequest.replacementPlatformAlarmId(pendingTemplate),
        )
        val authorityStore = ReservationAuthorityStore(context)
        assertTrue(authorityStore.recordRetired(listOf(retired)))
        var pendingCancelCount = 0
        val pendingFailure = bridge.armAndPersistForTest(
            request = pending,
            platformAlarmId = pending.platformAlarmId,
            arm = { armForRecoveryTest(pending) },
            persist = { AlarmStore(context).put(pending) },
            cancel = {
                pendingCancelCount += 1
                false
            },
            recordActive = { false },
            recordRetired = { false },
            removePersisted = { throw AssertionError("Mirror removal must follow cancellation.") },
        )
        assertEquals("failure", pendingFailure["status"])
        assertTrue(
            (pendingFailure["failureMessage"] as String).contains("pending durable recovery"),
        )
        assertEquals(0, pendingCancelCount)
        assertNotNull(AlarmStore(context).get(pending.platformAlarmId))
        assertNotNull(activationCleanupPreferences().getString("active", null))

        val recovery = AndroidAlarmReplacementRecovery.reconcile(context, context)

        assertTrue(recovery.isSuccess)
        assertNull(AlarmStore(context).get(pending.platformAlarmId))
        assertFalse(scheduledAlarmIds().contains(pending.platformAlarmId))
        assertNull(activationCleanupPreferences().getString("active", null))
        assertEquals(
            ReservationAuthorityState.RETIRED,
            authorityStore.load().reservations[pending.reservationId]?.state,
        )

        val removalRetired = retired.copy(
            occurrenceId = "pending-removal-old",
            reservationId = "pending-removal-slot",
            platformAlarmIdOverride = "android:reservation:pending-removal-slot",
        )
        val removalTemplate = removalRetired.copy(
            occurrenceId = "pending-removal-current",
            reservationGeneration = 2L,
        )
        val removalPending = removalTemplate.copy(
            platformAlarmIdOverride = AlarmRequest.replacementPlatformAlarmId(removalTemplate),
        )
        assertTrue(authorityStore.recordRetired(listOf(removalRetired)))
        val removalFailure = bridge.armAndPersistForTest(
            request = removalPending,
            platformAlarmId = removalPending.platformAlarmId,
            arm = { armForRecoveryTest(removalPending) },
            persist = { AlarmStore(context).put(removalPending) },
            cancel = {
                context.getSystemService(AlarmManager::class.java)
                    .cancel(AlarmIntents.receiver(context, removalPending.platformAlarmId))
                true
            },
            recordActive = { false },
            removePersisted = { false },
        )
        assertEquals("failure", removalFailure["status"])
        assertNotNull(AlarmStore(context).get(removalPending.platformAlarmId))

        val removalRecovery = AndroidAlarmReplacementRecovery.reconcile(context, context)

        assertTrue(removalRecovery.isSuccess)
        assertNull(AlarmStore(context).get(removalPending.platformAlarmId))
        assertFalse(scheduledAlarmIds().contains(removalPending.platformAlarmId))
        assertEquals(
            ReservationAuthorityState.RETIRED,
            authorityStore.load().reservations[removalPending.reservationId]?.state,
        )
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
    fun `concurrent generation advance waits for prior admission transaction`() {
        val reachedArm = CountDownLatch(1)
        val releaseArm = CountDownLatch(1)
        val firstBridge = AndroidAlarmBridge(context).also { bridge ->
            bridge.setBeforeAlarmManagerMutationForTest {
                reachedArm.countDown()
                check(releaseArm.await(5, TimeUnit.SECONDS))
            }
        }
        val secondBridge = AndroidAlarmBridge(context)
        val executor = Executors.newFixedThreadPool(2)
        try {
            val first = executor.submit<CapturingResult> {
                CapturingResult().also { result ->
                    firstBridge.onMethodCall(
                        MethodCall(
                            "scheduleOccurrences",
                            scheduleArguments(
                                "serialized-old",
                                "serialized-slot",
                                "serialized-plan",
                                reservationGeneration = 1L,
                            ),
                        ),
                        result,
                    )
                }
            }
            assertTrue(reachedArm.await(5, TimeUnit.SECONDS))
            val second = executor.submit<CapturingResult> {
                CapturingResult().also { result ->
                    secondBridge.onMethodCall(
                        MethodCall(
                            "scheduleOccurrences",
                            scheduleArguments(
                                "serialized-new",
                                "serialized-slot",
                                "serialized-plan",
                                reservationGeneration = 2L,
                            ),
                        ),
                        result,
                    )
                }
            }

            assertThrows(TimeoutException::class.java) {
                second.get(200, TimeUnit.MILLISECONDS)
            }
            releaseArm.countDown()
            val firstRow = ((first.get(5, TimeUnit.SECONDS).value as Map<*, *>)["occurrences"] as List<*>)
                .single() as Map<*, *>
            val secondRow = ((second.get(5, TimeUnit.SECONDS).value as Map<*, *>)["occurrences"] as List<*>)
                .single() as Map<*, *>
            val persisted = AlarmStore(context)
                .inventory(context, System.currentTimeMillis())
                .requests.single()

            assertEquals("success", firstRow["status"])
            assertEquals("success", secondRow["status"])
            assertEquals(2L, persisted.reservationGeneration)
            assertEquals("serialized-new", persisted.occurrenceId)
            assertEquals(listOf(persisted.platformAlarmId), scheduledAlarmIds())
            assertEquals(
                ReservationAuthorityState.ACTIVE,
                ReservationAuthorityStore(context).load()
                    .reservations[persisted.reservationId]?.state,
            )
        } finally {
            releaseArm.countDown()
            executor.shutdownNow()
        }
    }

    @Test
    fun `recovery cannot mutate a partially admitted schedule transaction`() {
        val reachedArm = CountDownLatch(1)
        val releaseArm = CountDownLatch(1)
        val bridge = AndroidAlarmBridge(context).also { configured ->
            configured.setBeforeAlarmManagerMutationForTest {
                reachedArm.countDown()
                check(releaseArm.await(5, TimeUnit.SECONDS))
            }
        }
        val executor = Executors.newFixedThreadPool(2)
        try {
            val schedule = executor.submit<CapturingResult> {
                CapturingResult().also { result ->
                    bridge.onMethodCall(
                        MethodCall(
                            "scheduleOccurrences",
                            scheduleArguments(
                                "recovery-serialized-occurrence",
                                "recovery-serialized-slot",
                                "recovery-serialized-plan",
                                reservationGeneration = 3L,
                            ),
                        ),
                        result,
                    )
                }
            }
            assertTrue(reachedArm.await(5, TimeUnit.SECONDS))
            val recovery = executor.submit<AlarmReplacementRecoveryResult> {
                AndroidAlarmReplacementRecovery.reconcile(context, context)
            }

            assertThrows(TimeoutException::class.java) {
                recovery.get(200, TimeUnit.MILLISECONDS)
            }
            releaseArm.countDown()
            val row = ((schedule.get(5, TimeUnit.SECONDS).value as Map<*, *>)["occurrences"] as List<*>)
                .single() as Map<*, *>
            val recoveryResult = recovery.get(5, TimeUnit.SECONDS)
            val persisted = AlarmStore(context)
                .inventory(context, System.currentTimeMillis())
                .requests.single()

            assertEquals("success", row["status"])
            assertTrue(recoveryResult.isSuccess)
            assertEquals(3L, persisted.reservationGeneration)
            assertEquals(listOf(persisted.platformAlarmId), scheduledAlarmIds())
            assertEquals(
                ReservationAuthorityState.ACTIVE,
                ReservationAuthorityStore(context).load()
                    .reservations[persisted.reservationId]?.state,
            )
            assertFalse(activationCleanupPreferences().contains("active"))
        } finally {
            releaseArm.countDown()
            executor.shutdownNow()
        }
    }

    @Test
    fun `replacement recovery converges the pre-arm seam and lost reply`() {
        assertRecoveryCrashSeam(
            phase = AlarmReplacementPhase.STAGING,
            armCandidate = false,
            mirrorCommitted = false,
            expectedNewWinner = false,
        )
    }

    @Test
    fun `replacement recovery converges the post-arm pre-phase seam and lost reply`() {
        assertRecoveryCrashSeam(
            phase = AlarmReplacementPhase.STAGING,
            armCandidate = true,
            mirrorCommitted = false,
            expectedNewWinner = false,
        )
    }

    @Test
    fun `replacement recovery converges the post-arm pre-mirror seam and lost reply`() {
        assertRecoveryCrashSeam(
            phase = AlarmReplacementPhase.CANDIDATE_ARMED,
            armCandidate = true,
            mirrorCommitted = false,
            expectedNewWinner = false,
        )
    }

    @Test
    fun `replacement recovery converges the mirror-commit pre-retirement seam and lost reply`() {
        assertRecoveryCrashSeam(
            phase = AlarmReplacementPhase.OLD_RETIRED,
            armCandidate = true,
            mirrorCommitted = true,
            expectedNewWinner = true,
        )
    }

    @Test
    fun `cancel resolves the exact replacement winner after recovery`() {
        val old = alarmRequest(
            platformAlarmId = "android:reservation:cancel-recovery-slot",
            reservationId = "cancel-recovery-slot",
            occurrenceId = "cancel-recovery-old",
            wakePlanId = "cancel-recovery-plan",
            reservationGeneration = 0L,
        )
        val newTemplate = old.copy(
            occurrenceId = "cancel-recovery-current",
            reservationGeneration = 1L,
        )
        val candidate = newTemplate.copy(
            platformAlarmIdOverride = AlarmRequest.replacementPlatformAlarmId(newTemplate),
        )
        assertTrue(AlarmStore(context).put(candidate))
        armForRecoveryTest(old)
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
        val recovery = AndroidAlarmReplacementRecovery.reconcile(context, context)
        assertTrue(recovery.isSuccess)
        assertNull(AlarmStore(context).get(old.platformAlarmId))
        assertNotNull(AlarmStore(context).get(candidate.platformAlarmId))

        val staleCancel = CapturingResult()
        AndroidAlarmBridge(context).onMethodCall(
            MethodCall(
                "cancelOccurrences",
                mapOf(
                    "schemaVersion" to 1,
                    "alarms" to listOf(
                        mapOf(
                            "occurrenceId" to candidate.occurrenceId,
                            "reservationId" to candidate.reservationId,
                            "reservationGeneration" to old.reservationGeneration,
                            "platformAlarmId" to old.platformAlarmId,
                        ),
                    ),
                ),
            ),
            staleCancel,
        )
        val staleRow = ((staleCancel.value as Map<*, *>)["alarms"] as List<*>)
            .single() as Map<*, *>
        assertEquals("failure", staleRow["status"])
        assertEquals("invalidRequest", staleRow["failureReason"])
        assertNotNull(AlarmStore(context).get(candidate.platformAlarmId))

        val cancel = CapturingResult()

        AndroidAlarmBridge(context).onMethodCall(
            MethodCall(
                "cancelOccurrences",
                mapOf(
                    "schemaVersion" to 1,
                    "alarms" to listOf(
                        mapOf(
                            "occurrenceId" to candidate.occurrenceId,
                            "reservationId" to candidate.reservationId,
                            "reservationGeneration" to candidate.reservationGeneration,
                            "platformAlarmId" to old.platformAlarmId,
                        ),
                    ),
                ),
            ),
            cancel,
        )

        val row = ((cancel.value as Map<*, *>)["alarms"] as List<*>)
            .single() as Map<*, *>
        assertEquals("success", row["status"])
        assertEquals(old.platformAlarmId, row["platformAlarmId"])
        assertNull(AlarmStore(context).get(old.platformAlarmId))
        assertNull(AlarmStore(context).get(candidate.platformAlarmId))
        assertTrue(scheduledAlarmIds().isEmpty())
        assertEquals(
            ReservationAuthorityState.RETIRED,
            ReservationAuthorityStore(context).load()
                .reservations[candidate.reservationId]?.state,
        )
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
    fun `receiver admission recovers armed and committed candidates before mirror lookup`() {
        for (phase in listOf(
            AlarmReplacementPhase.CANDIDATE_ARMED,
            AlarmReplacementPhase.OLD_RETIRED,
        )) {
            setUp()
            val reservationId = "receiver-seam-${phase.name.lowercase()}"
            val old = alarmRequest(
                platformAlarmId = "android:reservation:$reservationId",
                reservationId = reservationId,
                occurrenceId = "$reservationId-old",
                wakePlanId = "receiver-seam-plan",
            )
            val candidateTemplate = old.copy(occurrenceId = "$reservationId-new")
            val candidate = candidateTemplate.copy(
                platformAlarmIdOverride = AlarmRequest.replacementPlatformAlarmId(candidateTemplate),
            )
            val store = AlarmStore(context)
            assertTrue(
                store.put(if (phase == AlarmReplacementPhase.OLD_RETIRED) candidate else old),
            )
            assertTrue(
                AlarmReplacementJournalStore(context).save(
                    AlarmReplacementJournal(old = old, new = candidate, phase = phase),
                ),
            )

            AlarmReceiver().onReceive(
                context,
                Shadows.shadowOf(AlarmIntents.receiver(context, candidate.platformAlarmId))
                    .savedIntent,
            )

            assertEquals(AlarmState.RINGING, store.get(candidate.platformAlarmId)?.state)
            assertNull(store.get(old.platformAlarmId))
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
    fun `uncommitted candidate admission preserves the exact firing candidate`() {
        val old = alarmRequest(
            platformAlarmId = "android:reservation:viable-incumbent-slot",
            reservationId = "viable-incumbent-slot",
            occurrenceId = "viable-incumbent-old",
            wakePlanId = "viable-incumbent-plan",
            scheduledAtMillis = System.currentTimeMillis() + 60_000,
        )
        val newTemplate = old.copy(
            occurrenceId = "viable-incumbent-new",
            scheduledAtMillis = System.currentTimeMillis() - 1_000,
            targetAtMillis = System.currentTimeMillis() - 1_000,
        )
        val candidate = newTemplate.copy(
            platformAlarmIdOverride = AlarmRequest.replacementPlatformAlarmId(newTemplate),
        )
        assertTrue(AlarmStore(context).put(old))
        armForRecoveryTest(old)
        armForRecoveryTest(candidate)
        assertTrue(
            AlarmReplacementJournalStore(context).save(
                AlarmReplacementJournal(
                    old = old,
                    new = candidate,
                    phase = AlarmReplacementPhase.CANDIDATE_ARMED,
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
        assertNull(AlarmStore(context).get(old.platformAlarmId))
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
    fun `receiver admission rejects stale cross-plan and mismatched authority tuples`() {
        val staleAuthority = alarmRequest(
            platformAlarmId = "android:reservation:stale-admission-slot",
            reservationId = "stale-admission-slot",
            occurrenceId = "stale-admission-current",
            wakePlanId = "admission-plan",
            reservationGeneration = 2L,
        )
        val crossPlanAuthority = alarmRequest(
            platformAlarmId = "android:reservation:cross-plan-admission-slot",
            reservationId = "cross-plan-admission-slot",
            occurrenceId = "cross-plan-admission-current",
            wakePlanId = "admission-plan",
            reservationGeneration = 2L,
        )
        val mismatchAuthority = alarmRequest(
            platformAlarmId = "android:reservation:mismatch-admission-slot",
            reservationId = "mismatch-admission-slot",
            occurrenceId = "mismatch-admission-current",
            wakePlanId = "admission-plan",
            reservationGeneration = 2L,
        )
        val conflicts = listOf(
            staleAuthority to staleAuthority.copy(
                occurrenceId = "stale-admission-old",
                reservationGeneration = 1L,
            ),
            crossPlanAuthority to crossPlanAuthority.copy(wakePlanId = "foreign-plan"),
            mismatchAuthority to mismatchAuthority.copy(
                occurrenceId = "mismatch-admission-other",
            ),
        )
        val authorityStore = ReservationAuthorityStore(context)
        for ((authority, mirror) in conflicts) {
            assertTrue(authorityStore.recordActive(authority))
            assertTrue(AlarmStore(context).put(mirror))
            armForRecoveryTest(mirror)
        }

        for ((_, mirror) in conflicts) {
            val recovery = AndroidAlarmReplacementRecovery.reconcile(
                context,
                context,
                admittingPlatformAlarmId = mirror.platformAlarmId,
            )

            assertFalse(recovery.isSuccess)
            assertTrue(recovery.message?.contains("conflicts") == true)
            assertNotNull(AlarmStore(context).get(mirror.platformAlarmId))
            assertTrue(scheduledAlarmIds().contains(mirror.platformAlarmId))
        }
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
    fun `corrupt activation cleanup journal fails closed and retains evidence`() {
        val evidence = "not-json"
        assertTrue(
            activationCleanupPreferences().edit().putString("active", evidence).commit(),
        )

        val first = AndroidAlarmReplacementRecovery.reconcile(context, context)
        val second = AndroidAlarmReplacementRecovery.reconcile(context, context)

        assertFalse(first.isSuccess)
        assertFalse(second.isSuccess)
        assertEquals(evidence, activationCleanupPreferences().getString("active", null))
        assertTrue(scheduledAlarmIds().isEmpty())
    }

    @Test
    fun `committed activation survives reopen before cleanup evidence clears`() {
        val request = alarmRequest(
            platformAlarmId = "android:reservation:committed-activation-slot",
            reservationId = "committed-activation-slot",
            occurrenceId = "committed-activation-occurrence",
            wakePlanId = "committed-activation-plan",
            reservationGeneration = 3L,
        ).copy(updatedAtMillis = 1L)
        assertTrue(AlarmActivationCleanupStore(context).save(request))
        armForRecoveryTest(request)
        assertTrue(AlarmStore(context).put(request))
        val persisted = AlarmStore(context).get(request.platformAlarmId)
        assertNotNull(persisted)
        assertNotEquals(
            request.updatedAtMillis,
            persisted?.updatedAtMillis,
        )
        val authorityStore = ReservationAuthorityStore(context)
        assertTrue(authorityStore.recordActive(request))

        val recovery = AndroidAlarmReplacementRecovery.reconcile(context, context)

        assertTrue(recovery.isSuccess)
        assertEquals(persisted, AlarmStore(context).get(request.platformAlarmId))
        assertEquals(listOf(request.platformAlarmId), scheduledAlarmIds())
        assertEquals(
            ReservationAuthorityState.ACTIVE,
            authorityStore.load().reservations[request.reservationId]?.state,
        )
        assertNull(activationCleanupPreferences().getString("active", null))
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

    private fun assertRecoveryCrashSeam(
        phase: AlarmReplacementPhase,
        armCandidate: Boolean,
        mirrorCommitted: Boolean,
        expectedNewWinner: Boolean,
    ) {
        val reservationId = "recovery-${phase.name.lowercase()}-$armCandidate-$mirrorCommitted"
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
        if (armCandidate) armForRecoveryTest(candidate)
        if (mirrorCommitted) {
            assertTrue(store.replace(old.platformAlarmId, candidate.platformAlarmId, candidate))
        }
        assertTrue(
            AlarmReplacementJournalStore(context).save(
                AlarmReplacementJournal(old = old, new = candidate, phase = phase),
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

        assertTrue(first.isSuccess)
        assertTrue(second.isSuccess)
        assertEquals(
            if (expectedNewWinner) candidate.occurrenceId else old.occurrenceId,
            firstWinner.occurrenceId,
        )
        assertEquals(firstWinner, secondWinner)
        assertEquals(listOf(firstWinner.platformAlarmId), scheduledAlarmIds())
        assertNull(AlarmReplacementJournalStore(context).load())
    }

    @Test
    fun `stable reservation atomically rebinds a recreated occurrence`() {
        val bridge = AndroidAlarmBridge(context)
        val original = scheduleArguments(
            occurrenceId = "occurrence-original",
            reservationId = "reservation-recreated",
            wakePlanId = "plan-recreated",
        )
        val recreated = scheduleArguments(
            occurrenceId = "occurrence-recreated",
            reservationId = "reservation-recreated",
            wakePlanId = "plan-recreated",
            scheduledAtMillis = System.currentTimeMillis() + 120_000,
            reservationGeneration = 1L,
        )

        val first = CapturingResult()
        bridge.onMethodCall(MethodCall("scheduleOccurrences", original), first)
        val originalRow = ((first.value as Map<*, *>)["occurrences"] as List<*>)
            .single() as Map<*, *>
        val second = CapturingResult()
        bridge.onMethodCall(MethodCall("scheduleOccurrences", recreated), second)
        val recreatedRow = ((second.value as Map<*, *>)["occurrences"] as List<*>)
            .single() as Map<*, *>

        assertEquals("success", originalRow["status"])
        assertEquals("success", recreatedRow["status"])
        assertFalse(originalRow["platformAlarmId"] == recreatedRow["platformAlarmId"])
        assertEquals(1, scheduledAlarms().size)
        val inventory = AlarmStore(context).inventory(context, System.currentTimeMillis())
        assertEquals(1, inventory.requests.size)
        assertEquals("reservation-recreated", inventory.requests.single().reservationId)
        assertEquals("occurrence-recreated", inventory.requests.single().occurrenceId)
        assertEquals(recreatedRow["platformAlarmId"], inventory.requests.single().platformAlarmId)

        val retry = CapturingResult()
        bridge.onMethodCall(MethodCall("scheduleOccurrences", recreated), retry)
        val retryRow = ((retry.value as Map<*, *>)["occurrences"] as List<*>)
            .single() as Map<*, *>
        assertEquals("success", retryRow["status"])
        assertEquals(recreatedRow["platformAlarmId"], retryRow["platformAlarmId"])
        assertEquals(1, scheduledAlarms().size)
        assertEquals(
            1,
            AlarmStore(context).inventory(context, System.currentTimeMillis()).requests.size,
        )

        val staleCancel = CapturingResult()
        bridge.onMethodCall(
            MethodCall(
                "cancelOccurrences",
                mapOf(
                    "schemaVersion" to 1,
                    "alarms" to listOf(
                        mapOf(
                            "occurrenceId" to "occurrence-original",
                            "reservationId" to "reservation-recreated",
                            "platformAlarmId" to originalRow["platformAlarmId"],
                        ),
                    ),
                ),
            ),
            staleCancel,
        )
        val staleRow = ((staleCancel.value as Map<*, *>)["alarms"] as List<*>)
            .single() as Map<*, *>
        assertEquals("failure", staleRow["status"])
        assertEquals("invalidRequest", staleRow["failureReason"])
        val remaining = AlarmStore(context)
            .inventory(context, System.currentTimeMillis())
            .requests
            .single()
        assertEquals(recreatedRow["platformAlarmId"], remaining.platformAlarmId)
        assertEquals(1L, remaining.reservationGeneration)
        assertEquals(listOf(recreatedRow["platformAlarmId"]), scheduledAlarmIds())
    }

    @Test
    fun `stable reservation rejects cross-plan and occurrence hijacks`() {
        val bridge = AndroidAlarmBridge(context)
        val first = CapturingResult()
        bridge.onMethodCall(
            MethodCall(
                "scheduleOccurrences",
                scheduleArguments("occurrence-owned", "reservation-owned", "plan-owned"),
            ),
            first,
        )

        for (arguments in listOf(
            scheduleArguments(
                "occurrence-new",
                "reservation-owned",
                "plan-foreign",
                reservationGeneration = 2L,
            ),
            scheduleArguments("occurrence-owned", "reservation-foreign", "plan-owned"),
        )) {
            val result = CapturingResult()
            bridge.onMethodCall(MethodCall("scheduleOccurrences", arguments), result)
            val row = ((result.value as Map<*, *>)["occurrences"] as List<*>)
                .single() as Map<*, *>
            assertEquals("failure", row["status"])
            assertEquals("invalidRequest", row["failureReason"])
        }

        val inventory = AlarmStore(context).inventory(context, System.currentTimeMillis())
        assertEquals(1, inventory.requests.size)
        assertEquals("occurrence-owned", inventory.requests.single().occurrenceId)
        assertEquals(1, scheduledAlarms().size)
    }

    @Test
    fun `reservation generation round trips and legacy rows default to zero`() {
        val current = alarmRequest(
            platformAlarmId = "android:reservation:generation-round-trip",
            reservationId = "generation-round-trip",
            occurrenceId = "generation-occurrence",
            reservationGeneration = 7L,
        )
        val legacy = current.toJson().apply { remove("reservationGeneration") }

        assertEquals(7L, AlarmRequest.fromJson(current.toJson()).reservationGeneration)
        assertEquals(0L, AlarmRequest.fromJson(legacy).reservationGeneration)
        for (invalid in listOf(-1, 1.0, "1", true)) {
            assertThrows(IllegalArgumentException::class.java) {
                AlarmRequest.fromJson(current.toJson().put("reservationGeneration", invalid))
            }
        }
    }

    @Test
    fun `higher generation with a gap wins and delayed replay cannot roll it back`() {
        val reservationId = "monotonic-slot"
        val planId = "monotonic-plan"
        val firstArguments = scheduleArguments(
            "monotonic-old",
            reservationId,
            planId,
            reservationGeneration = 0L,
        )
        val currentArguments = scheduleArguments(
            "monotonic-current",
            reservationId,
            planId,
            scheduledAtMillis = System.currentTimeMillis() + 120_000,
            reservationGeneration = 2L,
        )
        val bridge = AndroidAlarmBridge(context)
        val first = CapturingResult()
        bridge.onMethodCall(MethodCall("scheduleOccurrences", firstArguments), first)
        val current = CapturingResult()
        bridge.onMethodCall(MethodCall("scheduleOccurrences", currentArguments), current)

        val restartedBridge = AndroidAlarmBridge(context)
        val replay = CapturingResult()
        restartedBridge.onMethodCall(MethodCall("scheduleOccurrences", firstArguments), replay)
        val replayRow = ((replay.value as Map<*, *>)["occurrences"] as List<*>)
            .single() as Map<*, *>
        val inventory = AlarmStore(context).inventory(context, System.currentTimeMillis())

        assertEquals("failure", replayRow["status"])
        assertEquals("invalidRequest", replayRow["failureReason"])
        assertEquals(1, inventory.requests.size)
        assertEquals("monotonic-current", inventory.requests.single().occurrenceId)
        assertEquals(2L, inventory.requests.single().reservationGeneration)
        assertEquals(1, scheduledAlarms().size)
    }

    @Test
    fun `equal generation with changed payload fails closed`() {
        val scheduledAt = System.currentTimeMillis() + 60_000
        val original = scheduleArguments(
            "same-generation-occurrence",
            "same-generation-slot",
            "same-generation-plan",
            scheduledAtMillis = scheduledAt,
            reservationGeneration = 4L,
        )
        val mismatch = scheduleArguments(
            "same-generation-occurrence",
            "same-generation-slot",
            "same-generation-plan",
            scheduledAtMillis = scheduledAt + 60_000,
            reservationGeneration = 4L,
        )
        val bridge = AndroidAlarmBridge(context)
        bridge.onMethodCall(MethodCall("scheduleOccurrences", original), CapturingResult())
        val result = CapturingResult()
        bridge.onMethodCall(MethodCall("scheduleOccurrences", mismatch), result)
        val row = ((result.value as Map<*, *>)["occurrences"] as List<*>)
            .single() as Map<*, *>

        assertEquals("failure", row["status"])
        assertEquals("invalidRequest", row["failureReason"])
        assertEquals(
            scheduledAt,
            AlarmStore(context).inventory(context, System.currentTimeMillis())
                .requests.single().scheduledAtMillis,
        )
    }

    @Test
    fun `higher generation may update payload without changing occurrence identity`() {
        val firstAt = System.currentTimeMillis() + 60_000
        val bridge = AndroidAlarmBridge(context)
        bridge.onMethodCall(
            MethodCall(
                "scheduleOccurrences",
                scheduleArguments(
                    "configuration-occurrence",
                    "configuration-slot",
                    "configuration-plan",
                    scheduledAtMillis = firstAt,
                    reservationGeneration = 1L,
                ),
            ),
            CapturingResult(),
        )
        val updated = CapturingResult()
        bridge.onMethodCall(
            MethodCall(
                "scheduleOccurrences",
                scheduleArguments(
                    "configuration-occurrence",
                    "configuration-slot",
                    "configuration-plan",
                    scheduledAtMillis = firstAt + 60_000,
                    reservationGeneration = 2L,
                ),
            ),
            updated,
        )
        val row = ((updated.value as Map<*, *>)["occurrences"] as List<*>)
            .single() as Map<*, *>
        val current = AlarmStore(context).inventory(context, System.currentTimeMillis())
            .requests.single()

        assertEquals("success", row["status"])
        assertEquals(2L, row["reservationGeneration"])
        assertEquals("configuration-occurrence", current.occurrenceId)
        assertEquals(2L, current.reservationGeneration)
        assertEquals(firstAt + 60_000, current.scheduledAtMillis)
    }

    @Test
    fun `retired generation rejects exact and older replay after reopen`() {
        val arguments = scheduleArguments(
            "retired-occurrence",
            "retired-slot",
            "retired-plan",
            reservationGeneration = 3L,
        )
        val bridge = AndroidAlarmBridge(context)
        val scheduled = CapturingResult()
        bridge.onMethodCall(MethodCall("scheduleOccurrences", arguments), scheduled)
        val scheduledRow = ((scheduled.value as Map<*, *>)["occurrences"] as List<*>)
            .single() as Map<*, *>
        val cancel = CapturingResult()
        bridge.onMethodCall(
            MethodCall(
                "cancelOccurrences",
                mapOf(
                    "schemaVersion" to 1,
                    "alarms" to listOf(
                        mapOf(
                            "occurrenceId" to "retired-occurrence",
                            "reservationId" to "retired-slot",
                            "reservationGeneration" to 3L,
                            "platformAlarmId" to scheduledRow["platformAlarmId"],
                        ),
                    ),
                ),
            ),
            cancel,
        )
        val replay = CapturingResult()
        AndroidAlarmBridge(context).onMethodCall(
            MethodCall("scheduleOccurrences", arguments),
            replay,
        )
        val replayRow = ((replay.value as Map<*, *>)["occurrences"] as List<*>)
            .single() as Map<*, *>

        assertEquals("success", ((cancel.value as Map<*, *>)["alarms"] as List<*>).single().let { (it as Map<*, *>)["status"] })
        assertEquals("failure", replayRow["status"])
        assertTrue(AlarmStore(context).inventory(context, System.currentTimeMillis()).requests.isEmpty())
    }

    @Test
    fun `retired mirror is finished from durable authority after reopen`() {
        val request = alarmRequest(
            platformAlarmId = "android:reservation:retirement-recovery-slot",
            reservationId = "retirement-recovery-slot",
            occurrenceId = "retirement-recovery-occurrence",
            wakePlanId = "retirement-recovery-plan",
            reservationGeneration = 4L,
        )
        assertTrue(AlarmStore(context).put(request))
        armForRecoveryTest(request)
        val authorityStore = ReservationAuthorityStore(context)
        assertTrue(authorityStore.recordActive(request))
        assertTrue(authorityStore.recordRetired(listOf(request)))

        val recovery = AndroidAlarmReplacementRecovery.reconcile(context, context)

        assertTrue(recovery.isSuccess)
        assertNull(AlarmStore(context).get(request.platformAlarmId))
        assertTrue(scheduledAlarmIds().isEmpty())
        assertEquals(
            ReservationAuthorityState.RETIRED,
            authorityStore.load().reservations[request.reservationId]?.state,
        )
    }

    @Test
    fun `higher durable mirror repairs activation after authority write crash`() {
        val retired = alarmRequest(
            platformAlarmId = "android:reservation:activation-recovery-slot",
            reservationId = "activation-recovery-slot",
            occurrenceId = "activation-recovery-old",
            wakePlanId = "activation-recovery-plan",
            reservationGeneration = 2L,
        )
        val currentTemplate = retired.copy(
            occurrenceId = "activation-recovery-current",
            reservationGeneration = 3L,
        )
        val current = currentTemplate.copy(
            platformAlarmIdOverride = AlarmRequest.replacementPlatformAlarmId(currentTemplate),
        )
        val authorityStore = ReservationAuthorityStore(context)
        assertTrue(authorityStore.recordRetired(listOf(retired)))
        assertTrue(AlarmStore(context).put(current))

        val failure = authorityStore.validateAndSeedActive(listOf(current))

        assertNull(failure)
        val repaired = authorityStore.load().reservations[current.reservationId]
        assertEquals(ReservationAuthorityState.ACTIVE, repaired?.state)
        assertEquals(current.reservationGeneration, repaired?.reservationGeneration)
        assertEquals(current.occurrenceId, repaired?.occurrenceId)
    }

    @Test
    fun `corrupt generation authority blocks scheduling without deleting evidence`() {
        assertTrue(authorityPreferences().edit().putString("authority", "not-json").commit())
        val result = CapturingResult()

        AndroidAlarmBridge(context).onMethodCall(
            MethodCall(
                "scheduleOccurrences",
                scheduleArguments("blocked-occurrence", "blocked-slot", "blocked-plan"),
            ),
            result,
        )
        val row = ((result.value as Map<*, *>)["occurrences"] as List<*>)
            .single() as Map<*, *>

        assertEquals("failure", row["status"])
        assertEquals("nativeError", row["failureReason"])
        assertEquals("not-json", authorityPreferences().getString("authority", null))
        assertTrue(scheduledAlarms().isEmpty())
    }

    @Test
    fun `replacement platform identity includes generation when occurrence cycles`() {
        val first = alarmRequest(
            platformAlarmId = "ignored",
            reservationId = "cycle-slot",
            occurrenceId = "cycle-occurrence",
            reservationGeneration = 1L,
        )
        val second = first.copy(reservationGeneration = 2L)

        assertFalse(
            AlarmRequest.replacementPlatformAlarmId(first) ==
                AlarmRequest.replacementPlatformAlarmId(second),
        )
    }

    @Test
    fun `non-monotonic version two replacement journal is rejected`() {
        val old = alarmRequest(
            platformAlarmId = "android:reservation:non-monotonic-slot",
            reservationId = "non-monotonic-slot",
            occurrenceId = "non-monotonic-old",
            reservationGeneration = 2L,
        )
        val newTemplate = old.copy(
            occurrenceId = "non-monotonic-new",
            reservationGeneration = 1L,
            platformAlarmIdOverride = null,
        )
        val replacement = newTemplate.copy(
            platformAlarmIdOverride = AlarmRequest.replacementPlatformAlarmId(newTemplate),
        )

        assertThrows(IllegalArgumentException::class.java) {
            AlarmReplacementJournal(
                old = old,
                new = replacement,
                schemaVersion = 2,
            )
        }
    }

    @Test
    fun `replacement journal chooses one authoritative generation after process death`() {
        for (phase in AlarmReplacementPhase.values()) {
            val previousAlarmManager = context.getSystemService(AlarmManager::class.java)
            scheduledAlarms().mapNotNull { it.operation }.forEach { operation ->
                previousAlarmManager.cancel(operation)
                operation.cancel()
            }
            setUp()
            val alarmManager = context.getSystemService(AlarmManager::class.java)
            val reservationId = "restart-slot-${phase.name.lowercase()}"
            val old = alarmRequest(
                platformAlarmId = "android:reservation:$reservationId",
                reservationId = reservationId,
                occurrenceId = "occurrence-old",
                wakePlanId = "plan-restart",
            )
            val newTemplate = old.copy(
                occurrenceId = "occurrence-new",
                reservationGeneration = 1L,
            )
            val replacement = newTemplate.copy(
                platformAlarmIdOverride = AlarmRequest.replacementPlatformAlarmId(newTemplate),
            )
            assertTrue(AlarmStore(context).put(old))
            assertTrue(
                AlarmReplacementJournalStore(context).save(
                    AlarmReplacementJournal(old = old, new = replacement, phase = phase),
                ),
            )
            fun arm(request: AlarmRequest) {
                alarmManager.setAlarmClock(
                    AlarmManager.AlarmClockInfo(
                        request.scheduledAtMillis,
                        AlarmIntents.showIntent(context, request.platformAlarmId),
                    ),
                    AlarmIntents.receiver(context, request.platformAlarmId),
                )
            }
            when (phase) {
                AlarmReplacementPhase.STAGING -> arm(old)
                AlarmReplacementPhase.CANDIDATE_ARMED -> {
                    arm(old)
                    arm(replacement)
                }
                AlarmReplacementPhase.OLD_RETIRED -> arm(replacement)
            }

            val result = AndroidAlarmReplacementRecovery.reconcile(context, context)
            val inventory = AlarmStore(context).inventory(context, System.currentTimeMillis())

            assertTrue(result.isSuccess)
            assertEquals(1, inventory.requests.size)
            assertEquals(
                if (phase == AlarmReplacementPhase.OLD_RETIRED) {
                    replacement.occurrenceId
                } else {
                    old.occurrenceId
                },
                inventory.requests.single().occurrenceId,
            )
            assertEquals(1, scheduledAlarms().size)
            assertNull(AlarmReplacementJournalStore(context).load())
        }
    }

    @Test
    fun `corrupt replacement journal fails closed during restore`() {
        val retained = alarmRequest(
            platformAlarmId = "android:reservation:corrupt-journal-slot",
            reservationId = "corrupt-journal-slot",
            occurrenceId = "corrupt-journal-occurrence",
            wakePlanId = "corrupt-journal-plan",
        )
        assertTrue(AlarmStore(context).put(retained))
        assertTrue(
            replacementPreferences().edit()
                .putString("active", "not-json")
                .commit(),
        )
        var restoreAttempts = 0

        AlarmRestore.restoreForTest(context, context) { restoreAttempts += 1 }

        assertEquals(0, restoreAttempts)
        assertNotNull(AlarmStore(context).get(retained.platformAlarmId))
        assertEquals("not-json", replacementPreferences().getString("active", null))
    }

    @Test
    fun `expired replacement journal retires both generations and unblocks scheduling`() {
        val expiredAt = System.currentTimeMillis() - 1_000
        val old = alarmRequest(
            platformAlarmId = "android:reservation:expired-journal-slot",
            reservationId = "expired-journal-slot",
            occurrenceId = "expired-journal-old",
            wakePlanId = "expired-journal-plan",
            scheduledAtMillis = expiredAt,
        )
        val newTemplate = old.copy(
            occurrenceId = "expired-journal-new",
            reservationGeneration = 1L,
        )
        val replacement = newTemplate.copy(
            platformAlarmIdOverride = AlarmRequest.replacementPlatformAlarmId(newTemplate),
        )
        assertTrue(AlarmStore(context).put(old))
        assertTrue(AlarmStore(context).put(replacement))
        assertTrue(
            AlarmReplacementJournalStore(context).save(
                AlarmReplacementJournal(
                    old = old,
                    new = replacement,
                    phase = AlarmReplacementPhase.CANDIDATE_ARMED,
                ),
            ),
        )

        val recovery = AndroidAlarmReplacementRecovery.reconcile(context, context)
        val schedule = CapturingResult()
        AndroidAlarmBridge(context).onMethodCall(
            MethodCall(
                "scheduleOccurrences",
                scheduleArguments(
                    occurrenceId = "unrelated-after-expired-journal",
                    reservationId = "unrelated-after-expired-journal",
                    wakePlanId = "unrelated-plan",
                ),
            ),
            schedule,
        )
        val expiredReplay = CapturingResult()
        AndroidAlarmBridge(context).onMethodCall(
            MethodCall(
                "scheduleOccurrences",
                scheduleArguments(
                    occurrenceId = old.occurrenceId,
                    reservationId = old.reservationId,
                    wakePlanId = old.wakePlanId,
                    scheduledAtMillis = System.currentTimeMillis() + 60_000,
                    reservationGeneration = old.reservationGeneration,
                ),
            ),
            expiredReplay,
        )

        assertTrue(recovery.isSuccess)
        assertNull(AlarmStore(context).get(old.platformAlarmId))
        assertNull(AlarmStore(context).get(replacement.platformAlarmId))
        assertNull(AlarmReplacementJournalStore(context).load())
        assertNull(schedule.errorCode)
        val row = ((schedule.value as Map<*, *>)["occurrences"] as List<*>)
            .single() as Map<*, *>
        assertEquals("success", row["status"])
        val replayRow = ((expiredReplay.value as Map<*, *>)["occurrences"] as List<*>)
            .single() as Map<*, *>
        assertEquals("failure", replayRow["status"])
    }

    @Test
    fun `expired old retired journal does not rearm its candidate`() {
        val expiredAt = System.currentTimeMillis() - 1_000
        val old = alarmRequest(
            platformAlarmId = "android:reservation:expired-retired-slot",
            reservationId = "expired-retired-slot",
            occurrenceId = "expired-retired-old",
            wakePlanId = "expired-retired-plan",
            scheduledAtMillis = expiredAt,
        )
        val newTemplate = old.copy(
            occurrenceId = "expired-retired-new",
            reservationGeneration = 5L,
        )
        val replacement = newTemplate.copy(
            platformAlarmIdOverride = AlarmRequest.replacementPlatformAlarmId(newTemplate),
        )
        assertTrue(AlarmStore(context).put(old))
        assertTrue(AlarmStore(context).put(replacement))
        assertTrue(
            AlarmReplacementJournalStore(context).save(
                AlarmReplacementJournal(
                    old = old,
                    new = replacement,
                    phase = AlarmReplacementPhase.OLD_RETIRED,
                ),
            ),
        )

        val recovery = AndroidAlarmReplacementRecovery.reconcile(context, context)

        assertTrue(recovery.isSuccess)
        assertNull(AlarmStore(context).get(old.platformAlarmId))
        assertNull(AlarmStore(context).get(replacement.platformAlarmId))
        assertNull(AlarmReplacementJournalStore(context).load())
        assertTrue(scheduledAlarms().isEmpty())
        val authority = ReservationAuthorityStore(context).load()
            .reservations[old.reservationId]
        assertEquals(5L, authority?.reservationGeneration)
        assertEquals(ReservationAuthorityState.RETIRED, authority?.state)
    }

    private fun scheduleArguments(
        occurrenceId: String,
        reservationId: String,
        wakePlanId: String,
        scheduledAtMillis: Long = System.currentTimeMillis() + 60_000,
        reservationGeneration: Long = 0L,
        indexInPlan: Int = 0,
        totalInPlan: Int = 1,
    ): Map<String, Any?> {
        val scheduledAt = Instant.ofEpochMilli(scheduledAtMillis)
        return mapOf<String, Any?>(
            "schemaVersion" to 1,
            "occurrences" to listOf(
                mapOf<String, Any?>(
                    "occurrenceId" to occurrenceId,
                    "reservationId" to reservationId,
                    "reservationGeneration" to reservationGeneration,
                    "wakePlanId" to wakePlanId,
                    "scheduledAt" to scheduledAt.toString(),
                    "targetAt" to scheduledAt.toString(),
                    "indexInPlan" to indexInPlan,
                    "totalInPlan" to totalInPlan,
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

    private fun activationCleanupPreferences() = deviceProtectedContext()
        .getSharedPreferences("native_alarm_activation_cleanup", Context.MODE_PRIVATE)

    private fun authorityPreferences() = deviceProtectedContext()
        .getSharedPreferences("native_alarm_reservation_authority", Context.MODE_PRIVATE)

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
        reservationGeneration: Long = 0L,
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
            reservationGeneration = reservationGeneration,
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
