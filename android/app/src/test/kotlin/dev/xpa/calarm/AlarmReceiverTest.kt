package dev.xpa.calarm

import android.app.AlarmManager
import android.app.Application
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Vibrator
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows
import org.robolectric.shadows.ShadowVibrator

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AlarmReceiverTest {
    private lateinit var context: Context
    private lateinit var application: Application

    @Before
    fun setUp() {
        application = RuntimeEnvironment.getApplication()
        context = application
        context.getSharedPreferences("native_alarm_store", Context.MODE_PRIVATE)
            .edit()
            .clear()
            .commit()
        deviceProtectedPreferences("native_alarm_events").edit().clear().commit()
        replacementPreferences().edit().clear().commit()
        deviceProtectedPreferences().edit().clear().commit()
        Shadows.shadowOf(application).clearNextStartedActivities()
        ShadowVibrator.reset()
    }

    @After
    fun tearDown() {
        context.getSharedPreferences("native_alarm_store", Context.MODE_PRIVATE)
            .edit()
            .clear()
            .commit()
        deviceProtectedPreferences("native_alarm_events").edit().clear().commit()
        replacementPreferences().edit().clear().commit()
        deviceProtectedPreferences().edit().clear().commit()
        Shadows.shadowOf(application).clearNextStartedActivities()
        ShadowVibrator.reset()
    }

    @Test
    fun `delivery failures are isolated so every alarm fallback is attempted`() {
        val calls = mutableListOf<String>()

        val delivered = AlarmReceiver().deliverFallbacks(
            notification = {
                calls += "notification"
                throw SecurityException("notification revoked")
            },
            screen = {
                calls += "screen"
                throw IllegalStateException("background launch blocked")
            },
            vibration = {
                calls += "vibration"
                throw SecurityException("vibration revoked")
            },
        )

        assertEquals(listOf("notification", "screen", "vibration"), calls)
        assertFalse(delivered)
    }

    @Test
    fun `all delivery failures remove ringing alarm state`() {
        val platformAlarmId = "android:plan:undeliverable"
        val store = AlarmStore(context)
        assertTrue(store.put(alarmRequest(platformAlarmId, vibrationEnabled = true)))
        assertTrue(store.markRinging(platformAlarmId))

        AlarmReceiver().deliverAlarm(
            store = store,
            platformAlarmId = platformAlarmId,
            notification = { throw SecurityException("notification revoked") },
            screen = { throw IllegalStateException("background launch blocked") },
            vibration = { throw SecurityException("vibration revoked") },
        )

        assertNull(store.get(platformAlarmId))
    }

    @Test
    fun `partial delivery success preserves ringing alarm state`() {
        val platformAlarmId = "android:plan:partially-delivered"
        val store = AlarmStore(context)
        assertTrue(store.put(alarmRequest(platformAlarmId, vibrationEnabled = true)))
        assertTrue(store.markRinging(platformAlarmId))

        AlarmReceiver().deliverAlarm(
            store = store,
            platformAlarmId = platformAlarmId,
            notification = {},
            screen = { throw IllegalStateException("background launch blocked") },
            vibration = { throw SecurityException("vibration revoked") },
        )

        assertEquals(AlarmState.RINGING, store.get(platformAlarmId)?.state)
    }

    @Test
    fun `alarm clock show intent opens non-ringing detail activity without consuming scheduled alarm`() {
        val platformAlarmId = "android:plan:show"
        val request = alarmRequest(platformAlarmId, vibrationEnabled = true)
        assertTrue(AlarmStore(context).put(request))

        val operation = AlarmIntents.receiver(context, platformAlarmId)
        val stopIntent = AlarmIntents.stopActivity(context, platformAlarmId)
        val showIntent = AlarmManager.AlarmClockInfo(
            request.scheduledAtMillis,
            AlarmIntents.showIntent(context, platformAlarmId),
        ).showIntent

        assertTrue(Shadows.shadowOf(operation).isBroadcastIntent)
        assertTrue(Shadows.shadowOf(stopIntent).isActivityIntent)
        assertTrue(Shadows.shadowOf(showIntent).isActivityIntent)
        assertTrue(operation.isImmutable)
        assertTrue(stopIntent.isImmutable)
        assertTrue(showIntent.isImmutable)
        assertFalse(operation == showIntent)
        assertFalse(operation == stopIntent)
        assertFalse(stopIntent == showIntent)

        showIntent.send()

        val started = Shadows.shadowOf(application).nextStartedActivity
        assertNotNull(started)
        assertEquals(AlarmStopActivity::class.java.name, started!!.component?.className)
        assertEquals(AlarmIntents.ACTION_ALARM_SHOW, started.action)
        assertEquals(platformAlarmId, started.getStringExtra(AlarmIntents.EXTRA_PLATFORM_ALARM_ID))
        assertNotNull(AlarmStore(context).get(platformAlarmId))
        assertNull(shadowVibrator().getVibrationAttributesFromLastVibration())

        val detailActivity = Robolectric.buildActivity(AlarmStopActivity::class.java, started)
            .setup()
            .get()
        val detailLayout = detailActivity.findViewById<ViewGroup>(android.R.id.content)
            .getChildAt(0) as LinearLayout
        val detailText = (detailLayout.getChildAt(0) as TextView).text.toString()
        assertTrue(detailText.contains("Scheduled:"))
        assertTrue(detailText.contains("Wake target:"))
        assertFalse(detailText.contains(request.wakePlanId))
        assertEquals("Close", (detailLayout.getChildAt(1) as Button).text)
        assertFalse(
            detailActivity.window.attributes.flags and
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED != 0,
        )
        assertFalse(
            detailActivity.window.attributes.flags and
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON != 0,
        )
        detailActivity.finish()
        assertNotNull(AlarmStore(context).get(platformAlarmId))
    }

    @Test
    fun `scheduled receiver fires stop activity and vibrates when persisted setting is enabled`() {
        val platformAlarmId = "android:plan:enabled"
        assertTrue(AlarmStore(context).put(alarmRequest(platformAlarmId, vibrationEnabled = true)))

        AlarmReceiver().onReceive(
            context,
            Shadows.shadowOf(AlarmIntents.receiver(context, platformAlarmId)).savedIntent,
        )

        val started = Shadows.shadowOf(application).nextStartedActivity
        assertNotNull(started)
        assertEquals(AlarmStopActivity::class.java.name, started!!.component?.className)
        assertNotNull(shadowVibrator().getVibrationAttributesFromLastVibration())
    }

    @Test
    fun `scheduled receiver does not vibrate when persisted setting is disabled`() {
        val platformAlarmId = "android:plan:disabled"
        assertTrue(AlarmStore(context).put(alarmRequest(platformAlarmId, vibrationEnabled = false)))

        AlarmReceiver().onReceive(
            context,
            Shadows.shadowOf(AlarmIntents.receiver(context, platformAlarmId)).savedIntent,
        )

        val started = Shadows.shadowOf(application).nextStartedActivity
        assertNotNull(started)
        assertEquals(AlarmStopActivity::class.java.name, started!!.component?.className)
        assertNull(shadowVibrator().getVibrationAttributesFromLastVibration())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = context.getSystemService(NotificationManager::class.java)
            assertFalse(
                notificationManager.getNotificationChannel(AlarmNotificationChannel.ID).shouldVibrate(),
            )
        }
    }

    @Test
    fun `receiver ignores a firing request without persisted state`() {
        val platformAlarmId = "android:plan:missing"

        AlarmReceiver().onReceive(
            context,
            Shadows.shadowOf(AlarmIntents.receiver(context, platformAlarmId)).savedIntent,
        )

        assertNull(Shadows.shadowOf(application).peekNextStartedActivity())
        assertNull(shadowVibrator().getVibrationAttributesFromLastVibration())
    }

    @Test
    fun `receiver ignores a present but corrupt persisted row without side effects`() {
        val platformAlarmId = "android:plan:corrupt"
        deviceProtectedPreferences()
            .edit()
            .putString(platformAlarmId, "not-json")
            .commit()

        AlarmReceiver().onReceive(
            context,
            Shadows.shadowOf(AlarmIntents.receiver(context, platformAlarmId)).savedIntent,
        )

        val started = Shadows.shadowOf(application).peekNextStartedActivity()
        assertNull(started)
        assertTrue(
            context.getSystemService(NotificationManager::class.java)
                .activeNotifications
                .isEmpty(),
        )
        assertNull(shadowVibrator().getVibrationAttributesFromLastVibration())
    }

    @Test
    fun `receiver recovers an armed candidate before mirror lookup and admits it once`() {
        val reservationId = "receiver-recovery"
        val old = alarmRequest(
            platformAlarmId = "android:reservation:$reservationId",
            vibrationEnabled = false,
            reservationId = reservationId,
            occurrenceId = "receiver-recovery-old",
            wakePlanId = "receiver-recovery-plan",
        )
        val candidateTemplate = old.copy(occurrenceId = "receiver-recovery-new")
        val candidate = candidateTemplate.copy(
            platformAlarmIdOverride = AlarmRequest.replacementPlatformAlarmId(candidateTemplate),
        )
        assertTrue(AlarmStore(context).put(old))
        assertTrue(
            replacementPreferences().edit()
                .putString(
                    "active",
                    AlarmReplacementJournal(
                        old = old,
                        new = candidate,
                        phase = AlarmReplacementPhase.CANDIDATE_ARMED,
                    ).toJson().toString(),
                )
                .commit(),
        )

        val receiverIntent = Shadows.shadowOf(
            AlarmIntents.receiver(context, candidate.platformAlarmId),
        ).savedIntent
        AlarmReceiver().onReceive(context, receiverIntent)

        assertEquals(AlarmState.RINGING, AlarmStore(context).get(candidate.platformAlarmId)?.state)
        assertNull(AlarmStore(context).get(old.platformAlarmId))
        assertNull(AlarmReplacementJournalStore(context).load())
        assertNotNull(Shadows.shadowOf(application).peekNextStartedActivity())
        assertEquals(
            1,
            AlarmEventStore(context).fetch().events.count {
                it.eventId == AlarmEvent.idFor(candidate.platformAlarmId, AlarmEventType.DELIVERED)
            },
        )

        Shadows.shadowOf(application).clearNextStartedActivities()
        AlarmReceiver().onReceive(context, receiverIntent)

        assertNull(Shadows.shadowOf(application).peekNextStartedActivity())
        assertEquals(
            1,
            AlarmEventStore(context).fetch().events.count {
                it.eventId == AlarmEvent.idFor(candidate.platformAlarmId, AlarmEventType.DELIVERED)
            },
        )
    }

    @Test
    fun `receiver fails closed on corrupt replacement journal and retains evidence`() {
        val platformAlarmId = "android:reservation:corrupt-recovery"
        val request = alarmRequest(platformAlarmId, vibrationEnabled = true)
        assertTrue(AlarmStore(context).put(request))
        assertTrue(replacementPreferences().edit().putString("active", "not-json").commit())

        AlarmReceiver().onReceive(
            context,
            Shadows.shadowOf(AlarmIntents.receiver(context, platformAlarmId)).savedIntent,
        )

        assertEquals(AlarmState.SCHEDULED, AlarmStore(context).get(platformAlarmId)?.state)
        assertEquals("not-json", replacementPreferences().getString("active", null))
        assertTrue(
            context.getSystemService(NotificationManager::class.java)
                .activeNotifications
                .isEmpty(),
        )
        assertNull(Shadows.shadowOf(application).peekNextStartedActivity())
        assertNull(shadowVibrator().getVibrationAttributesFromLastVibration())
        assertTrue(AlarmEventStore(context).fetch().events.isEmpty())
    }

    @Test
    fun `receiver delivers an unrelated safe alarm while retaining other recovery evidence`() {
        val safe = alarmRequest(
            platformAlarmId = "android:plan:unrelated-safe",
            vibrationEnabled = false,
        )
        val otherReservation = "other-recovery"
        val otherOld = alarmRequest(
            platformAlarmId = "android:reservation:$otherReservation",
            vibrationEnabled = false,
            reservationId = otherReservation,
            occurrenceId = "other-recovery-old",
        )
        val otherNewTemplate = otherOld.copy(occurrenceId = "other-recovery-new")
        val otherNew = otherNewTemplate.copy(
            platformAlarmIdOverride = AlarmRequest.replacementPlatformAlarmId(otherNewTemplate),
        )
        assertTrue(AlarmStore(context).put(safe))
        assertTrue(
            AlarmReplacementJournalStore(context).save(
                AlarmReplacementJournal(old = otherOld, new = otherNew),
            ),
        )

        AlarmReceiver().onReceive(
            context,
            Shadows.shadowOf(AlarmIntents.receiver(context, safe.platformAlarmId)).savedIntent,
        )

        assertEquals(AlarmState.RINGING, AlarmStore(context).get(safe.platformAlarmId)?.state)
        assertNotNull(Shadows.shadowOf(application).peekNextStartedActivity())
        assertNotNull(AlarmReplacementJournalStore(context).load())
    }

    @Test
    fun `stop activity removes persisted alarm state when stop is pressed`() {
        val platformAlarmId = "android:plan:stop"
        assertTrue(AlarmStore(context).put(alarmRequest(platformAlarmId, vibrationEnabled = true)))
        val intent = Intent(context, AlarmStopActivity::class.java)
            .setAction(AlarmIntents.ACTION_ALARM_STOP)
            .putExtra(AlarmIntents.EXTRA_PLATFORM_ALARM_ID, platformAlarmId)

        val activity = Robolectric.buildActivity(AlarmStopActivity::class.java, intent)
            .setup()
            .get()
        val content = activity.findViewById<ViewGroup>(android.R.id.content)
        val layout = content.getChildAt(0) as LinearLayout
        val stopButton = layout.getChildAt(layout.childCount - 1) as Button

        stopButton.performClick()

        assertNull(AlarmStore(context).get(platformAlarmId))
        assertTrue(activity.isFinishing)
    }

    @Test
    fun `stop intent upgrades an existing detail activity to ringing mode`() {
        val platformAlarmId = "android:plan:detail-to-ring"
        assertTrue(AlarmStore(context).put(alarmRequest(platformAlarmId, vibrationEnabled = true)))
        val showIntent = Shadows.shadowOf(AlarmIntents.showIntent(context, platformAlarmId)).savedIntent

        val activity = Robolectric.buildActivity(AlarmStopActivity::class.java, showIntent)
            .setup()
            .get()
        val stopIntent = AlarmIntents.stopActivityIntent(context, platformAlarmId)

        activity.onNewIntent(stopIntent)

        val content = activity.findViewById<ViewGroup>(android.R.id.content)
        val layout = content.getChildAt(0) as LinearLayout
        val stopButton = layout.getChildAt(layout.childCount - 1) as Button
        assertEquals("Stop current alarm", stopButton.text)
        stopButton.performClick()
        assertNull(AlarmStore(context).get(platformAlarmId))
    }

    @Test
    fun `second stop intent does not retarget an already ringing activity`() {
        val currentAlarmId = "android:plan:current-ring"
        val secondAlarmId = "android:plan:second-ring"
        assertTrue(AlarmStore(context).put(alarmRequest(currentAlarmId, vibrationEnabled = true)))
        assertTrue(AlarmStore(context).put(alarmRequest(secondAlarmId, vibrationEnabled = true)))

        val activity = Robolectric.buildActivity(
            AlarmStopActivity::class.java,
            AlarmIntents.stopActivityIntent(context, currentAlarmId),
        ).setup().get()

        activity.onNewIntent(AlarmIntents.stopActivityIntent(context, secondAlarmId))

        val content = activity.findViewById<ViewGroup>(android.R.id.content)
        val layout = content.getChildAt(0) as LinearLayout
        (layout.getChildAt(layout.childCount - 1) as Button).performClick()

        assertNull(AlarmStore(context).get(currentAlarmId))
        assertNotNull(AlarmStore(context).get(secondAlarmId))
    }

    @Test
    fun `ringing activity preserves alarm state across configuration change`() {
        val platformAlarmId = "android:plan:rotation"
        assertTrue(AlarmStore(context).put(alarmRequest(platformAlarmId, vibrationEnabled = true)))

        val controller = Robolectric.buildActivity(
            AlarmStopActivity::class.java,
            AlarmIntents.stopActivityIntent(context, platformAlarmId),
        ).setup()
        controller.configurationChange()

        val recreated = controller.get()
        assertNotNull(AlarmStore(context).get(platformAlarmId))
        val content = recreated.findViewById<ViewGroup>(android.R.id.content)
        val layout = content.getChildAt(0) as LinearLayout
        val stopButton = layout.getChildAt(layout.childCount - 1) as Button
        assertEquals("Stop current alarm", stopButton.text)
        assertEquals(0, shadowVibrator().repeat)
        stopButton.performClick()
        assertNull(AlarmStore(context).get(platformAlarmId))
    }

    @Test
    fun `alarm request round trips position metadata and legacy rows omit it safely`() {
        val request = alarmRequest(
            platformAlarmId = "android:plan:positioned",
            vibrationEnabled = true,
            indexInPlan = 1,
            totalInPlan = 3,
        )

        val positioned = AlarmRequest.fromJson(request.toJson())
        val legacyJson = request.toJson().apply {
            remove("indexInPlan")
            remove("totalInPlan")
        }
        deviceProtectedPreferences().edit()
            .putString(request.platformAlarmId, legacyJson.toString())
            .commit()
        val legacy = AlarmStore(context).get(request.platformAlarmId)

        assertEquals(1, positioned.indexInPlan)
        assertEquals(3, positioned.totalInPlan)
        assertNotNull(legacy)
        assertNull(legacy?.indexInPlan)
        assertNull(legacy?.totalInPlan)
    }

    @Test
    fun `persisted position metadata rejects partial or out of range values`() {
        val request = alarmRequest("android:plan:invalid-position", vibrationEnabled = true)
        val partial = request.toJson().put("indexInPlan", 0)
        val outOfRange = request.toJson()
            .put("indexInPlan", 2)
            .put("totalInPlan", 2)

        assertThrows(IllegalArgumentException::class.java) {
            AlarmRequest.fromJson(partial)
        }
        assertThrows(IllegalArgumentException::class.java) {
            AlarmRequest.fromJson(outOfRange)
        }
    }

    @Test
    fun `schedule decode preserves valid position and rejects malformed position`() {
        val scheduledAt = java.time.Instant.ofEpochMilli(System.currentTimeMillis() + 60_000)
            .toString()
        val base = mutableMapOf<String, Any?>(
            "occurrenceId" to "positioned",
            "reservationId" to "positioned",
            "wakePlanId" to "plan",
            "scheduledAt" to scheduledAt,
            "targetAt" to scheduledAt,
            "soundId" to "default",
            "vibrationEnabled" to true,
            "indexInPlan" to 1,
            "totalInPlan" to 3,
        )

        val valid = AlarmRequest.fromScheduleMap(base)
        val malformed = AlarmRequest.fromScheduleMap(base + ("totalInPlan" to 1))

        assertEquals(1, valid?.indexInPlan)
        assertEquals(3, valid?.totalInPlan)
        assertNull(malformed)
    }

    @Test
    fun `next lookup selects deterministic later scheduled alarm in the same plan`() {
        val store = AlarmStore(context)
        val base = System.currentTimeMillis() + 60_000
        val current = alarmRequest(
            "android:plan:current",
            vibrationEnabled = true,
            scheduledAtMillis = base,
        )
        val expected = alarmRequest(
            "android:plan:a-next",
            vibrationEnabled = true,
            scheduledAtMillis = base + 60_000,
        )
        val sameTimeLaterTarget = alarmRequest(
            "android:plan:b-next",
            vibrationEnabled = true,
            scheduledAtMillis = base + 60_000,
            targetAtMillis = base + 90_000,
        )
        val ringing = alarmRequest(
            "android:plan:ringing-next",
            vibrationEnabled = true,
            scheduledAtMillis = base + 30_000,
        )
        val otherPlan = alarmRequest(
            "android:other:other-next",
            vibrationEnabled = true,
            wakePlanId = "other",
            scheduledAtMillis = base + 10_000,
        )
        val testAlarm = alarmRequest(
            "android:test:test-next",
            vibrationEnabled = true,
            scheduledAtMillis = base + 5_000,
            isTest = true,
        )
        listOf(current, expected, sameTimeLaterTarget, ringing, otherPlan, testAlarm).forEach {
            assertTrue(store.put(it))
        }
        assertTrue(store.markRinging(ringing.platformAlarmId))

        val next = store.nextScheduledAfter(current.wakePlanId, current.scheduledAtMillis)

        assertEquals(expected.platformAlarmId, next?.platformAlarmId)
        assertNull(store.nextScheduledAfter(current.wakePlanId, expected.scheduledAtMillis))
    }

    @Test
    fun `notification keeps rich context private and exposes a generic public version`() {
        val base = System.currentTimeMillis() + 60_000
        val current = alarmRequest(
            "android:plan:notification-current",
            vibrationEnabled = false,
            scheduledAtMillis = base,
            targetAtMillis = base + 120_000,
            indexInPlan = 1,
            totalInPlan = 3,
        )
        val next = alarmRequest(
            "android:plan:notification-next",
            vibrationEnabled = false,
            scheduledAtMillis = base + 60_000,
        )
        val store = AlarmStore(context)
        assertTrue(store.put(current))
        assertTrue(store.put(next))

        AlarmReceiver().onReceive(
            context,
            Shadows.shadowOf(AlarmIntents.receiver(context, current.platformAlarmId)).savedIntent,
        )

        val notification = context.getSystemService(NotificationManager::class.java)
            .activeNotifications
            .single { it.id == current.platformAlarmId.hashCode() }
            .notification
        val privateText = notification.extras
            .getCharSequence(Notification.EXTRA_BIG_TEXT)
            .toString()
        assertEquals(Notification.VISIBILITY_PRIVATE, notification.visibility)
        assertEquals("Wake alarm ringing now", notification.extras.getCharSequence(Notification.EXTRA_TITLE))
        assertTrue(privateText.contains("Scheduled:"))
        assertTrue(privateText.contains("Wake target:"))
        assertTrue(privateText.contains("Alarm 2 of 3"))
        assertTrue(privateText.contains("Next alarm:"))
        assertTrue(notification.`when` > 0)

        val publicVersion = notification.publicVersion
        assertNotNull(publicVersion)
        assertEquals(Notification.VISIBILITY_PUBLIC, publicVersion.visibility)
        assertEquals("Wake alarm", publicVersion.extras.getCharSequence(Notification.EXTRA_TITLE))
        assertEquals("Alarm is ringing", publicVersion.extras.getCharSequence(Notification.EXTRA_TEXT))
        assertFalse(publicVersion.extras.toString().contains("Alarm 2 of 3"))
        assertFalse(publicVersion.extras.toString().contains("Wake target"))
    }

    @Test
    fun `late delivery still shows the next staged alarm in plan order`() {
        val now = System.currentTimeMillis()
        val current = alarmRequest(
            "android:plan:late-current",
            vibrationEnabled = false,
            scheduledAtMillis = now - 120_000,
        )
        val next = alarmRequest(
            "android:plan:late-next",
            vibrationEnabled = false,
            scheduledAtMillis = now - 60_000,
        )
        assertTrue(AlarmStore(context).put(current))
        assertTrue(AlarmStore(context).put(next))

        AlarmReceiver().onReceive(
            context,
            Shadows.shadowOf(AlarmIntents.receiver(context, current.platformAlarmId)).savedIntent,
        )

        val notification = context.getSystemService(NotificationManager::class.java)
            .activeNotifications
            .single { it.id == current.platformAlarmId.hashCode() }
            .notification
        val privateText = notification.extras
            .getCharSequence(Notification.EXTRA_BIG_TEXT)
            .toString()
        val nextTime = java.text.DateFormat.getTimeInstance(java.text.DateFormat.SHORT)
            .format(java.util.Date(next.scheduledAtMillis))
        assertTrue(privateText.contains("Next alarm: $nextTime"))
    }

    @Test
    fun `ringing screen shows scheduled current target position and next alarm context`() {
        val base = System.currentTimeMillis() + 60_000
        val current = alarmRequest(
            "android:plan:screen-current",
            vibrationEnabled = false,
            scheduledAtMillis = base,
            targetAtMillis = base + 120_000,
            indexInPlan = 0,
            totalInPlan = 2,
        )
        val next = alarmRequest(
            "android:plan:screen-next",
            vibrationEnabled = false,
            scheduledAtMillis = base + 60_000,
        )
        assertTrue(AlarmStore(context).put(current))
        assertTrue(AlarmStore(context).put(next))

        val activity = Robolectric.buildActivity(
            AlarmStopActivity::class.java,
            AlarmIntents.stopActivityIntent(context, current.platformAlarmId),
        ).setup().get()
        val layout = activity.findViewById<ViewGroup>(android.R.id.content)
            .getChildAt(0) as LinearLayout
        val currentText = (layout.getChildAt(0) as TextView).text.toString()
        val summary = (layout.getChildAt(1) as TextView).text.toString()

        assertTrue(currentText.startsWith("Current time:"))
        assertTrue(summary.contains("Scheduled:"))
        assertTrue(summary.contains("Wake target:"))
        assertTrue(summary.contains("Alarm 1 of 2"))
        assertTrue(summary.contains("Next alarm:"))
        assertEquals("Stop current alarm", (layout.getChildAt(2) as Button).text)
        activity.finish()
    }

    @Test
    fun `ringing vibration follows request and is cancelled by current alarm cleanup`() {
        val enabled = alarmRequest("android:plan:vibrate-enabled", vibrationEnabled = true)
        assertTrue(AlarmStore(context).put(enabled))
        val enabledActivity = Robolectric.buildActivity(
            AlarmStopActivity::class.java,
            AlarmIntents.stopActivityIntent(context, enabled.platformAlarmId),
        ).setup().get()

        assertTrue(shadowVibrator().isVibrating)
        assertEquals(0, shadowVibrator().repeat)
        val layout = enabledActivity.findViewById<ViewGroup>(android.R.id.content)
            .getChildAt(0) as LinearLayout
        (layout.getChildAt(layout.childCount - 1) as Button).performClick()
        assertTrue(shadowVibrator().isCancelled)

        ShadowVibrator.reset()
        val disabled = alarmRequest("android:plan:vibrate-disabled", vibrationEnabled = false)
        assertTrue(AlarmStore(context).put(disabled))
        Robolectric.buildActivity(
            AlarmStopActivity::class.java,
            AlarmIntents.stopActivityIntent(context, disabled.platformAlarmId),
        ).setup()
        assertFalse(shadowVibrator().isVibrating)
    }

    @Test
    fun `missing vibrator service degrades without crashing the alarm activity`() {
        val request = alarmRequest("android:plan:no-vibrator-service", vibrationEnabled = false)
        assertTrue(AlarmStore(context).put(request))
        val activity = Robolectric.buildActivity(
            AlarmStopActivity::class.java,
            Shadows.shadowOf(AlarmIntents.showIntent(context, request.platformAlarmId)).savedIntent,
        ).setup().get()

        val resolved = activity.alarmVibrator(
            vibratorManagerProvider = { null },
            vibratorProvider = { null },
        )

        assertNull(resolved)
        assertFalse(activity.isFinishing)
        activity.finish()
    }

    private fun shadowVibrator(): ShadowVibrator {
        return Shadows.shadowOf(context.getSystemService(Vibrator::class.java))
    }

    private fun deviceProtectedPreferences(name: String = "native_alarm_store") =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.createDeviceProtectedStorageContext()
                .getSharedPreferences(name, Context.MODE_PRIVATE)
        } else {
            context.getSharedPreferences(name, Context.MODE_PRIVATE)
        }

    private fun replacementPreferences() = deviceProtectedPreferences("native_alarm_replacement_journal")

    private fun alarmRequest(
        platformAlarmId: String,
        vibrationEnabled: Boolean,
        wakePlanId: String = "plan",
        scheduledAtMillis: Long = System.currentTimeMillis() + 60_000,
        targetAtMillis: Long = scheduledAtMillis,
        reservationId: String? = null,
        occurrenceId: String? = null,
        indexInPlan: Int? = null,
        totalInPlan: Int? = null,
        isTest: Boolean = false,
    ): AlarmRequest {
        val resolvedOccurrenceId = occurrenceId ?: platformAlarmId.substringAfterLast(':')
        return AlarmRequest(
            occurrenceId = resolvedOccurrenceId,
            reservationId = reservationId ?: resolvedOccurrenceId,
            wakePlanId = wakePlanId,
            scheduledAtMillis = scheduledAtMillis,
            targetAtMillis = targetAtMillis,
            soundId = "default",
            vibrationEnabled = vibrationEnabled,
            platformAlarmIdOverride = platformAlarmId,
            indexInPlan = indexInPlan,
            totalInPlan = totalInPlan,
            isTest = isTest,
        )
    }
}
