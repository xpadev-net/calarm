package dev.xpa.calarm

import android.app.AlarmManager
import android.content.Context
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.time.Instant
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowAlarmManager

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AndroidInventoryTest {
    private lateinit var context: Context

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        mirrorPreferences().edit().clear().commit()
        credentialPreferences().edit().clear().commit()
        ShadowAlarmManager.reset()
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
    }

    @After
    fun tearDown() {
        mirrorPreferences().edit().clear().commit()
        credentialPreferences().edit().clear().commit()
        ShadowAlarmManager.reset()
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
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
    fun `inventory reports duplicate stable identities without inventing rows`() {
        val first = alarmRequest(
            platformAlarmId = "android:reservation:duplicate-1",
            reservationId = "duplicate",
            occurrenceId = "occurrence-1",
        )
        val second = alarmRequest(
            platformAlarmId = "android:reservation:duplicate-2",
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
        val request = alarmRequest("android:plan:ringing", state = AlarmState.RINGING)
        assertTrue(AlarmStore(context).put(request))

        val snapshot = AlarmStore(context).inventory(context, System.currentTimeMillis())

        assertEquals(AlarmState.RINGING.value, snapshot.status(snapshot.requests.single()))
        assertNotNull(AlarmStore(context).get(request.platformAlarmId))
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
        val testRequest = alarmRequest("android:test:synthetic").copy(isTest = true)
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

    private fun scheduleArguments(
        occurrenceId: String,
        reservationId: String,
        wakePlanId: String,
    ): Map<String, Any?> {
        val scheduledAt = Instant.ofEpochMilli(System.currentTimeMillis() + 60_000)
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

    private fun alarmRequest(
        platformAlarmId: String,
        reservationId: String = "occurrence",
        occurrenceId: String = "occurrence",
        scheduledAtMillis: Long = System.currentTimeMillis() + 60_000,
        state: AlarmState = AlarmState.SCHEDULED,
    ): AlarmRequest {
        return AlarmRequest(
            occurrenceId = occurrenceId,
            reservationId = reservationId,
            wakePlanId = "plan",
            scheduledAtMillis = scheduledAtMillis,
            targetAtMillis = scheduledAtMillis,
            soundId = "default",
            vibrationEnabled = false,
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
