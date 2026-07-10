package dev.xpa.calarm

import android.app.AlarmManager
import android.app.Application
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Vibrator
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows
import org.robolectric.shadows.ShadowVibrator

@RunWith(RobolectricTestRunner::class)
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
        Shadows.shadowOf(application).clearNextStartedActivities()
        ShadowVibrator.reset()
    }

    @After
    fun tearDown() {
        context.getSharedPreferences("native_alarm_store", Context.MODE_PRIVATE)
            .edit()
            .clear()
            .commit()
        Shadows.shadowOf(application).clearNextStartedActivities()
        ShadowVibrator.reset()
    }

    @Test
    fun `alarm clock show intent opens MainActivity without consuming scheduled alarm`() {
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
        assertEquals(MainActivity::class.java.name, started!!.component?.className)
        assertNull(started.action)
        assertNotNull(AlarmStore(context).get(platformAlarmId))
        assertNull(shadowVibrator().getVibrationAttributesFromLastVibration())
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
    fun `receiver still alerts for a present but corrupt persisted row without vibrating`() {
        val platformAlarmId = "android:plan:corrupt"
        context.getSharedPreferences("native_alarm_store", Context.MODE_PRIVATE)
            .edit()
            .putString(platformAlarmId, "not-json")
            .commit()

        AlarmReceiver().onReceive(
            context,
            Shadows.shadowOf(AlarmIntents.receiver(context, platformAlarmId)).savedIntent,
        )

        val started = Shadows.shadowOf(application).nextStartedActivity
        assertNotNull(started)
        assertEquals(AlarmStopActivity::class.java.name, started!!.component?.className)
        assertNull(shadowVibrator().getVibrationAttributesFromLastVibration())
    }

    @Test
    fun `stop activity removes persisted alarm state when stop is pressed`() {
        val platformAlarmId = "android:plan:stop"
        assertTrue(AlarmStore(context).put(alarmRequest(platformAlarmId, vibrationEnabled = true)))
        val intent = Intent(context, AlarmStopActivity::class.java)
            .putExtra(AlarmIntents.EXTRA_PLATFORM_ALARM_ID, platformAlarmId)

        val activity = Robolectric.buildActivity(AlarmStopActivity::class.java, intent)
            .setup()
            .get()
        val content = activity.findViewById<ViewGroup>(android.R.id.content)
        val layout = content.getChildAt(0) as LinearLayout
        val stopButton = layout.getChildAt(1) as Button

        stopButton.performClick()

        assertNull(AlarmStore(context).get(platformAlarmId))
        assertTrue(activity.isFinishing)
    }

    private fun shadowVibrator(): ShadowVibrator {
        return Shadows.shadowOf(context.getSystemService(Vibrator::class.java))
    }

    private fun alarmRequest(platformAlarmId: String, vibrationEnabled: Boolean): AlarmRequest {
        val scheduledAt = System.currentTimeMillis() + 60_000
        return AlarmRequest(
            occurrenceId = "occurrence",
            wakePlanId = "plan",
            scheduledAtMillis = scheduledAt,
            targetAtMillis = scheduledAt,
            soundId = "default",
            vibrationEnabled = vibrationEnabled,
            platformAlarmIdOverride = platformAlarmId,
        )
    }
}
