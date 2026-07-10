package dev.xpa.calarm

import android.app.AlarmManager
import android.app.Application
import android.content.Context
import android.content.Intent
import android.os.Build
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
class AndroidRecoveryTest {
    private lateinit var context: Context
    private lateinit var application: Application

    @Before
    fun setUp() {
        application = RuntimeEnvironment.getApplication()
        context = application
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
    fun `restore leaves future mirror rows untouched when exact permission is missing`() {
        val request = alarmRequest("android:plan:permission-missing")
        assertTrue(AlarmStore(context).put(request))
        ShadowAlarmManager.setCanScheduleExactAlarms(false)

        BootReceiver().onReceive(context, Intent(Intent.ACTION_BOOT_COMPLETED))

        assertNotNull(AlarmStore(context).get(request.platformAlarmId))
        assertTrue(scheduledAlarms().isEmpty())
    }

    @Test
    fun `exact permission regrant broadcast restores future alarms`() {
        val request = alarmRequest("android:plan:permission-regranted")
        assertTrue(AlarmStore(context).put(request))
        ShadowAlarmManager.setCanScheduleExactAlarms(false)

        BootReceiver().onReceive(
            context,
            Intent(AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED),
        )
        assertTrue(scheduledAlarms().isEmpty())

        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        BootReceiver().onReceive(
            context,
            Intent(AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED),
        )

        assertEquals(1, scheduledAlarms().size)
        assertEquals(request.platformAlarmId, scheduledAlarmIds().single())
    }

    @Test
    fun `boot package replacement regrant and duplicate delivery restore one alarm`() {
        val request = alarmRequest("android:plan:idempotent")
        assertTrue(AlarmStore(context).put(request))
        val actions = listOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED,
        )

        actions.forEach { action ->
            repeat(2) {
                BootReceiver().onReceive(context, Intent(action))
            }
        }

        assertEquals(1, scheduledAlarms().size)
        assertEquals(request.platformAlarmId, scheduledAlarmIds().single())
    }

    @Test
    fun `locked boot restores only the device protected mirror`() {
        val credentialRequest = alarmRequest("android:plan:credential-only")
        credentialPreferences().edit()
            .putString(credentialRequest.platformAlarmId, credentialRequest.toJson().toString())
            .commit()
        val deviceRequest = alarmRequest("android:plan:device-protected")
        assertTrue(AlarmStore(deviceProtectedContext()).put(deviceRequest))
        assertNotNull(AlarmStore(deviceProtectedContext()).get(deviceRequest.platformAlarmId))

        BootReceiver().onReceive(context, Intent(Intent.ACTION_LOCKED_BOOT_COMPLETED))

        assertNotNull(AlarmStore(deviceProtectedContext()).get(deviceRequest.platformAlarmId))
        assertEquals(1, scheduledAlarms().size)
        assertEquals(deviceRequest.platformAlarmId, scheduledAlarmIds().single())
        assertTrue(credentialPreferences().contains(credentialRequest.platformAlarmId))
    }

    @Test
    fun `package replacement migrates legacy credential rows before restore`() {
        val request = alarmRequest("android:plan:legacy-package-replace")
        credentialPreferences().edit()
            .putString(request.platformAlarmId, request.toJson().toString())
            .commit()

        BootReceiver().onReceive(context, Intent(Intent.ACTION_MY_PACKAGE_REPLACED))

        assertEquals(1, scheduledAlarms().size)
        assertNotNull(AlarmStore(context).get(request.platformAlarmId))
        assertFalse(credentialPreferences().contains(request.platformAlarmId))
    }

    @Test
    fun `package replacement preserves device mirror when credential row is newer`() {
        val platformAlarmId = "android:plan:stale-mirror"
        val staleRequest = alarmRequest(
            platformAlarmId,
            scheduledAtMillis = System.currentTimeMillis() + 60_000,
        )
        val credentialRequest = alarmRequest(
            platformAlarmId,
            scheduledAtMillis = System.currentTimeMillis() + 120_000,
        )
        mirrorPreferences().edit()
            .putString(platformAlarmId, staleRequest.toJson().toString())
            .commit()
        credentialPreferences().edit()
            .putString(platformAlarmId, credentialRequest.toJson().toString())
            .commit()

        BootReceiver().onReceive(context, Intent(Intent.ACTION_MY_PACKAGE_REPLACED))

        val restored = AlarmStore(context).get(platformAlarmId)
        assertNotNull(restored)
        assertEquals(staleRequest.scheduledAtMillis, restored!!.scheduledAtMillis)
        assertFalse(credentialPreferences().contains(platformAlarmId))
    }

    @Test
    fun `package replacement preserves a newer device mirror over a stale credential row`() {
        val platformAlarmId = "android:plan:stale-credential"
        val credentialRequest = alarmRequest(
            platformAlarmId,
            scheduledAtMillis = System.currentTimeMillis() + 60_000,
        )
        val mirrorRequest = alarmRequest(
            platformAlarmId,
            scheduledAtMillis = System.currentTimeMillis() + 120_000,
        )
        credentialPreferences().edit()
            .putString(platformAlarmId, credentialRequest.toJson().toString())
            .commit()
        mirrorPreferences().edit()
            .putString(platformAlarmId, mirrorRequest.toJson().toString())
            .commit()

        BootReceiver().onReceive(context, Intent(Intent.ACTION_MY_PACKAGE_REPLACED))

        val restored = AlarmStore(context).get(platformAlarmId)
        assertNotNull(restored)
        assertEquals(mirrorRequest.scheduledAtMillis, restored!!.scheduledAtMillis)
        assertFalse(credentialPreferences().contains(platformAlarmId))
    }

    @Test
    fun `package replacement preserves mirror payload when schedule time is unchanged`() {
        val platformAlarmId = "android:plan:equal-time-payload"
        val scheduledAtMillis = System.currentTimeMillis() + 120_000
        val credentialRequest = alarmRequest(
            platformAlarmId,
            scheduledAtMillis = scheduledAtMillis,
            vibrationEnabled = false,
        )
        val mirrorRequest = alarmRequest(
            platformAlarmId,
            scheduledAtMillis = scheduledAtMillis,
            vibrationEnabled = true,
        )
        credentialPreferences().edit()
            .putString(platformAlarmId, credentialRequest.toJson().toString())
            .commit()
        mirrorPreferences().edit()
            .putString(platformAlarmId, mirrorRequest.toJson().toString())
            .commit()

        BootReceiver().onReceive(context, Intent(Intent.ACTION_MY_PACKAGE_REPLACED))

        val restored = AlarmStore(context).get(platformAlarmId)
        assertNotNull(restored)
        assertTrue(restored!!.vibrationEnabled)
        assertFalse(credentialPreferences().contains(platformAlarmId))
    }

    @Test
    fun `transient restore scheduling failure keeps future mirror row for retry`() {
        val request = alarmRequest("android:plan:transient-restore-failure")
        assertTrue(AlarmStore(context).put(request))

        AlarmRestore.restoreForTest(context, context) {
            throw IllegalStateException("temporary AlarmManager failure")
        }

        assertNotNull(AlarmStore(context).get(request.platformAlarmId))
    }

    @Test
    fun `expired and corrupt mirror rows are removed without scheduling`() {
        val expiredRequest = alarmRequest(
            platformAlarmId = "android:plan:expired",
            scheduledAtMillis = System.currentTimeMillis() - 1_000,
        )
        mirrorPreferences().edit()
            .putString(expiredRequest.platformAlarmId, expiredRequest.toJson().toString())
            .putString("android:plan:malformed", "not-json")
            .putInt("android:plan:wrong-type", 7)
            .commit()

        BootReceiver().onReceive(context, Intent(Intent.ACTION_BOOT_COMPLETED))

        assertFalse(mirrorPreferences().contains(expiredRequest.platformAlarmId))
        assertFalse(mirrorPreferences().contains("android:plan:malformed"))
        assertFalse(mirrorPreferences().contains("android:plan:wrong-type"))
        assertTrue(scheduledAlarms().isEmpty())
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
        return Shadows.shadowOf(context.getSystemService(AlarmManager::class.java))
            .scheduledAlarms
    }

    private fun scheduledAlarmIds(): List<String> {
        return scheduledAlarms().mapNotNull { alarm ->
            Shadows.shadowOf(alarm.operation).savedIntent
                .getStringExtra(AlarmIntents.EXTRA_PLATFORM_ALARM_ID)
        }
    }

    private fun alarmRequest(
        platformAlarmId: String,
        scheduledAtMillis: Long = System.currentTimeMillis() + 60_000,
        vibrationEnabled: Boolean = true,
    ): AlarmRequest {
        return AlarmRequest(
            occurrenceId = "occurrence",
            wakePlanId = "plan",
            scheduledAtMillis = scheduledAtMillis,
            targetAtMillis = scheduledAtMillis,
            soundId = "default",
            vibrationEnabled = vibrationEnabled,
            platformAlarmIdOverride = platformAlarmId,
        )
    }
}
