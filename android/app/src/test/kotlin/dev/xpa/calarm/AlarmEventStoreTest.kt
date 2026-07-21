package dev.xpa.calarm

import android.app.Application
import android.content.Context
import android.content.Intent
import android.os.Build
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AlarmEventStoreTest {
    private lateinit var context: Context

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        eventPreferences().edit().clear().commit()
        alarmPreferences().edit().clear().commit()
        Shadows.shadowOf(context.applicationContext as Application).clearNextStartedActivities()
    }

    @After
    fun tearDown() {
        eventPreferences().edit().clear().commit()
        alarmPreferences().edit().clear().commit()
        Shadows.shadowOf(context.applicationContext as Application).clearNextStartedActivities()
    }

    @Test
    fun `fetch is non destructive duplicate ids overwrite and ack removes only named events`() {
        val store = AlarmEventStore(context)
        assertTrue(store.appendDelivered("alarm-1", 100L))
        assertTrue(store.appendDelivered("alarm-1", 150L))
        assertTrue(store.appendDismissed("alarm-1", 200L))

        val first = store.fetch()
        val replay = AlarmEventStore(context).fetch()

        assertTrue(first.corruptKeys.isEmpty())
        assertEquals(2, first.events.size)
        assertEquals(first.events, replay.events)
        assertEquals(150L, first.events.first().timestampMillis)
        assertTrue(store.acknowledge(listOf("alarm-1:delivered")))
        assertEquals(
            listOf("alarm-1:dismissed"),
            AlarmEventStore(context).fetch().events.map { it.eventId },
        )
        assertTrue(store.acknowledge(listOf("unknown-event")))
        assertEquals(1, store.fetch().events.size)
    }

    @Test
    fun `journal retention is bounded and deterministic`() {
        val store = AlarmEventStore(context)
        repeat(205) { index ->
            assertTrue(store.appendDelivered("alarm-${index.toString().padStart(3, '0')}", index.toLong()))
        }

        val events = store.fetch().events

        assertEquals(200, events.size)
        assertEquals("alarm-005:delivered", events.first().eventId)
        assertEquals("alarm-204:delivered", events.last().eventId)
    }

    @Test
    fun `corrupt rows are pruned while unsupported storage schema is retained and reported`() {
        val valid = AlarmEvent(
            eventId = "valid:delivered",
            platformAlarmId = "valid",
            type = AlarmEventType.DELIVERED,
            timestampMillis = 10L,
        )
        val future = AlarmEvent(
            eventId = "future:delivered",
            platformAlarmId = "future",
            type = AlarmEventType.DELIVERED,
            timestampMillis = 20L,
        )
        val unsupported = future.toJson().put("schemaVersion", 2)
        eventPreferences().edit()
            .putString(valid.eventId, valid.toJson().toString())
            .putString("wrong-key", valid.toJson().toString())
            .putString(future.eventId, unsupported.toString())
            .putString("not-json", "broken")
            .commit()

        val first = AlarmEventStore(context).fetch()
        val second = AlarmEventStore(context).fetch()

        assertEquals(listOf(valid), first.events)
        assertEquals(listOf("not-json", "wrong-key"), first.corruptKeys)
        assertEquals(listOf(future.eventId), first.unsupportedSchemaKeys)
        assertEquals(listOf(valid), second.events)
        assertTrue(second.corruptKeys.isEmpty())
        assertEquals(listOf(future.eventId), second.unsupportedSchemaKeys)
        eventPreferences().edit().putString("ack-corrupt", "broken").commit()
        assertTrue(
            AlarmEventStore(context).acknowledge(
                listOf(valid.eventId, "ack-corrupt", future.eventId, "unknown"),
            ),
        )
        assertFalse(eventPreferences().contains(valid.eventId))
        assertTrue(eventPreferences().contains("ack-corrupt"))
        assertTrue(eventPreferences().contains(future.eventId))
        assertTrue(AlarmEventStore(context).appendDelivered("future", 99L))

        val current = AlarmEventStore(context).fetch()
        assertEquals(listOf("future:delivered"), current.events.map { it.eventId })
        assertEquals(99L, current.events.single().timestampMillis)
        assertTrue(current.corruptKeys.isEmpty())
        assertTrue(current.unsupportedSchemaKeys.isEmpty())
        val archiveEntry = eventPreferences().all.entries.single {
            it.key != future.eventId
        }
        val archive = JSONObject(archiveEntry.value as String)
        assertEquals(future.eventId, archive.getString("eventId"))
        val retained = JSONObject(archive.getString("payload"))
        assertEquals(2, retained.getInt("schemaVersion"))

        assertTrue(AlarmEventStore(context).acknowledge(listOf(future.eventId)))
        assertFalse(eventPreferences().contains(future.eventId))
        assertTrue(eventPreferences().contains(archiveEntry.key))
    }

    @Test
    fun `device protected journal is visible across storage contexts`() {
        val deviceContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.createDeviceProtectedStorageContext()
        } else {
            context
        }

        assertTrue(AlarmEventStore(deviceContext).appendDelivered("direct-boot", 42L))

        assertEquals(
            "direct-boot:delivered",
            AlarmEventStore(context).fetch().events.single().eventId,
        )
    }

    @Test
    fun `bridge fetches schema one rows non destructively and acknowledges exact ids`() {
        val store = AlarmEventStore(context)
        assertTrue(store.appendDelivered("bridge", 123L))
        assertTrue(store.appendDismissed("bridge", 456L))
        val bridge = AndroidAlarmBridge(context)

        val fetch = CapturingResult()
        bridge.onMethodCall(
            MethodCall("fetchAlarmEvents", mapOf("schemaVersion" to 1)),
            fetch,
        )

        assertNull(fetch.errorCode)
        val response = fetch.value as Map<*, *>
        assertEquals(1, response["schemaVersion"])
        val rows = response["events"] as List<*>
        assertEquals(2, rows.size)
        assertEquals(2, store.fetch().events.size)

        val ack = CapturingResult()
        bridge.onMethodCall(
            MethodCall(
                "acknowledgeAlarmEvents",
                mapOf(
                    "schemaVersion" to 1,
                    "eventIds" to listOf("bridge:delivered"),
                ),
            ),
            ack,
        )

        assertNull(ack.errorCode)
        assertEquals("success", (ack.value as Map<*, *>)["status"])
        assertEquals(listOf("bridge:dismissed"), store.fetch().events.map { it.eventId })
    }

    @Test
    fun `bridge rejects malformed ack payloads without deleting events`() {
        val store = AlarmEventStore(context)
        assertTrue(store.appendDelivered("safe", 1L))
        val invalidValues = listOf<Any?>(
            null,
            "safe:delivered",
            listOf("safe:delivered", 3),
            listOf(""),
            listOf("safe:delivered", "safe:delivered"),
        )

        invalidValues.forEach { value ->
            val arguments = mutableMapOf<String, Any?>("schemaVersion" to 1)
            if (value != null) arguments["eventIds"] = value
            val result = CapturingResult()
            AndroidAlarmBridge(context).onMethodCall(
                MethodCall("acknowledgeAlarmEvents", arguments),
                result,
            )
            assertEquals("INVALID_REQUEST", result.errorCode)
            assertEquals(1, store.fetch().events.size)
        }
    }

    @Test
    fun `bridge signals cleaned corruption before returning remaining valid events`() {
        assertTrue(AlarmEventStore(context).appendDelivered("valid", 1L))
        eventPreferences().edit().putString("corrupt", "not-json").commit()
        val bridge = AndroidAlarmBridge(context)

        val first = CapturingResult()
        bridge.onMethodCall(MethodCall("fetchAlarmEvents", mapOf("schemaVersion" to 1)), first)
        val second = CapturingResult()
        bridge.onMethodCall(MethodCall("fetchAlarmEvents", mapOf("schemaVersion" to 1)), second)

        assertEquals("CORRUPT", first.errorCode)
        assertNull(second.errorCode)
        assertEquals(1, ((second.value as Map<*, *>)["events"] as List<*>).size)
    }

    @Test
    fun `delivery callback runs only after a real fallback succeeds`() {
        val alarmId = "android:plan:delivery-order"
        val alarmStore = AlarmStore(context)
        assertTrue(alarmStore.put(alarmRequest(alarmId)))
        assertTrue(alarmStore.markRinging(alarmId))
        val eventStore = AlarmEventStore(context)

        val failed = AlarmReceiver().deliverAlarm(
            store = alarmStore,
            platformAlarmId = alarmId,
            notification = { throw SecurityException("blocked") },
            screen = { throw IllegalStateException("blocked") },
            vibration = null,
            recordDelivered = { eventStore.appendDelivered(alarmId, 1L) },
        )

        assertFalse(failed)
        assertTrue(eventStore.fetch().events.isEmpty())

        assertTrue(alarmStore.put(alarmRequest(alarmId)))
        assertTrue(alarmStore.markRinging(alarmId))
        val delivered = AlarmReceiver().deliverAlarm(
            store = alarmStore,
            platformAlarmId = alarmId,
            notification = {},
            screen = { throw IllegalStateException("blocked") },
            vibration = null,
            recordDelivered = { eventStore.appendDelivered(alarmId, 2L) },
        )

        assertTrue(delivered)
        assertEquals("$alarmId:delivered", eventStore.fetch().events.single().eventId)
    }

    @Test
    fun `delivery is recorded once at the first successful native path`() {
        val alarmId = "android:plan:first-delivery"
        val alarmStore = AlarmStore(context)
        assertTrue(alarmStore.put(alarmRequest(alarmId)))
        assertTrue(alarmStore.markRinging(alarmId))
        val order = mutableListOf<String>()

        val delivered = AlarmReceiver().deliverAlarm(
            store = alarmStore,
            platformAlarmId = alarmId,
            notification = { order += "notification" },
            screen = { order += "screen" },
            vibration = { order += "vibration" },
            recordDelivered = { order += "journal" },
        )

        assertTrue(delivered)
        assertEquals(listOf("notification", "journal", "screen", "vibration"), order)
    }

    @Test
    fun `receiver records delivered after its native delivery paths succeed`() {
        val alarmId = "android:plan:receiver-delivered"
        assertTrue(AlarmStore(context).put(alarmRequest(alarmId)))

        AlarmReceiver().onReceive(
            context,
            Shadows.shadowOf(AlarmIntents.receiver(context, alarmId)).savedIntent,
        )

        assertEquals(
            "$alarmId:delivered",
            AlarmEventStore(context).fetch().events.single().eventId,
        )
    }

    @Test
    fun `only the explicit stop action records dismissal`() {
        val lifecycleAlarmId = "android:plan:lifecycle"
        assertTrue(AlarmStore(context).put(alarmRequest(lifecycleAlarmId)))
        Robolectric.buildActivity(
            AlarmStopActivity::class.java,
            stopIntent(lifecycleAlarmId),
        ).setup().destroy()
        assertTrue(AlarmEventStore(context).fetch().events.isEmpty())

        val stoppedAlarmId = "android:plan:stopped"
        assertTrue(AlarmStore(context).put(alarmRequest(stoppedAlarmId)))
        val activity = Robolectric.buildActivity(
            AlarmStopActivity::class.java,
            stopIntent(stoppedAlarmId),
        ).setup().get()
        val layout = activity.findViewById<ViewGroup>(android.R.id.content)
        val matchingViews = arrayListOf<View>()
        layout.findViewsWithText(
            matchingViews,
            "Stop current alarm",
            View.FIND_VIEWS_WITH_TEXT,
        )

        (matchingViews.single { it is Button } as Button).performClick()

        assertEquals(
            "$stoppedAlarmId:dismissed",
            AlarmEventStore(context).fetch().events.single().eventId,
        )
    }

    private fun stopIntent(platformAlarmId: String): Intent {
        return Intent(context, AlarmStopActivity::class.java)
            .setAction(AlarmIntents.ACTION_ALARM_STOP)
            .putExtra(AlarmIntents.EXTRA_PLATFORM_ALARM_ID, platformAlarmId)
    }

    private fun alarmRequest(platformAlarmId: String): AlarmRequest {
        return AlarmRequest(
            occurrenceId = platformAlarmId.substringAfterLast(':'),
            wakePlanId = "plan",
            scheduledAtMillis = System.currentTimeMillis() + 60_000,
            targetAtMillis = System.currentTimeMillis() + 120_000,
            soundId = "default",
            vibrationEnabled = false,
            platformAlarmIdOverride = platformAlarmId,
        )
    }

    private fun eventPreferences() = deviceProtectedContext()
        .getSharedPreferences("native_alarm_events", Context.MODE_PRIVATE)

    private fun alarmPreferences() = deviceProtectedContext()
        .getSharedPreferences("native_alarm_store", Context.MODE_PRIVATE)

    private fun deviceProtectedContext(): Context {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.createDeviceProtectedStorageContext()
        } else {
            context
        }
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
