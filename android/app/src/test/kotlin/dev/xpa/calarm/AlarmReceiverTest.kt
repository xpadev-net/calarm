package dev.xpa.calarm

import android.app.AlarmManager
import android.app.Application
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
        assertTrue((detailLayout.getChildAt(0) as TextView).text.toString().contains("Wake plan: plan"))
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
            .setAction(AlarmIntents.ACTION_ALARM_STOP)
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
        assertEquals("Stop", (layout.getChildAt(1) as Button).text)
        (layout.getChildAt(1) as Button).performClick()
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
        (layout.getChildAt(1) as Button).performClick()

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
        assertEquals("Stop", (layout.getChildAt(1) as Button).text)
        (layout.getChildAt(1) as Button).performClick()
        assertNull(AlarmStore(context).get(platformAlarmId))
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
