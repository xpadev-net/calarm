package dev.xpa.calarm

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.Application
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.ResolveInfo
import android.net.Uri
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.After
import org.junit.Assert.assertEquals
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
import org.robolectric.shadows.ShadowAlarmManager

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class AndroidPermissionBridgeTest {
    private lateinit var application: Application
    private lateinit var activity: Activity

    @Before
    fun setUp() {
        application = RuntimeEnvironment.getApplication()
        application.getSharedPreferences("native_alarm_permissions", Context.MODE_PRIVATE)
            .edit()
            .clear()
            .commit()
        Shadows.shadowOf(application).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        Shadows.shadowOf(application).clearNextStartedActivities()
        Shadows.shadowOf(application.getSystemService(NotificationManager::class.java))
            .setNotificationsEnabled(true)
        ShadowAlarmManager.reset()
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        application.getSystemService(NotificationManager::class.java)
            .createNotificationChannel(AlarmNotificationChannel.create())
        activity = Robolectric.buildActivity(Activity::class.java).setup().get()
    }

    @After
    fun tearDown() {
        activity.finish()
        ShadowAlarmManager.reset()
        Shadows.shadowOf(application).checkActivities(false)
        Shadows.shadowOf(application).clearNextStartedActivities()
    }

    @Test
    fun `notification runtime callback completes the pending method result`() {
        val bridge = AndroidAlarmBridge(activity)
        val result = CapturingResult()

        bridge.onMethodCall(permissionCall(), result)

        assertNull(result.value)
        assertNull(result.errorCode)
        Shadows.shadowOf(application).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        assertTrue(bridge.onRequestPermissionsResult(NOTIFICATION_PERMISSION_REQUEST_CODE))

        val response = result.value as Map<*, *>
        assertEquals("granted", response["status"])
        assertEquals("authorized", response["permissionStatus"])
    }

    @Test
    fun `activity destruction fails a pending callback exactly once`() {
        val bridge = AndroidAlarmBridge(activity)
        val result = CapturingResult()

        bridge.onMethodCall(permissionCall(), result)
        bridge.detach()
        bridge.detach()

        assertEquals("UNAVAILABLE", result.errorCode)
        assertEquals(1, result.completionCount)
    }

    @Test
    fun `permanently denied notification access falls back to app settings`() {
        application.getSharedPreferences("native_alarm_permissions", Context.MODE_PRIVATE)
            .edit()
            .putBoolean("notification_requested", true)
            .commit()
        val result = CapturingResult()

        AndroidAlarmBridge(activity).onMethodCall(permissionCall(), result)

        val launched = Shadows.shadowOf(application).nextStartedActivity
        assertEquals(Settings.ACTION_APP_NOTIFICATION_SETTINGS, launched.action)
        assertEquals("denied", (result.value as Map<*, *>)["status"])
    }

    @Test
    @Suppress("DEPRECATION")
    fun `notification settings fallback opens app details without an activity`() {
        val detailsIntent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:${application.packageName}")
        }
        Shadows.shadowOf(application.packageManager)
            .setResolveInfosForIntent(detailsIntent, listOf(ResolveInfo()))
        Shadows.shadowOf(application).checkActivities(true)
        val result = CapturingResult()

        AndroidAlarmBridge(application).onMethodCall(permissionCall(), result)

        val launched = Shadows.shadowOf(application).nextStartedActivity
        assertEquals(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, launched.action)
        assertEquals("package:${application.packageName}", launched.data.toString())
        assertEquals("denied", (result.value as Map<*, *>)["status"])
    }

    @Test
    @Config(sdk = [32])
    fun `globally disabled notifications open app notification settings before Android 13`() {
        Shadows.shadowOf(application.getSystemService(NotificationManager::class.java))
            .setNotificationsEnabled(false)
        val result = CapturingResult()

        AndroidAlarmBridge(activity).onMethodCall(permissionCall(), result)

        val launched = Shadows.shadowOf(application).nextStartedActivity
        assertEquals(Settings.ACTION_APP_NOTIFICATION_SETTINGS, launched.action)
        assertEquals("denied", (result.value as Map<*, *>)["status"])
    }

    @Test
    fun `globally disabled notifications open settings when runtime permission is granted`() {
        Shadows.shadowOf(application).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        Shadows.shadowOf(application.getSystemService(NotificationManager::class.java))
            .setNotificationsEnabled(false)
        val result = CapturingResult()

        AndroidAlarmBridge(activity).onMethodCall(permissionCall(), result)

        val launched = Shadows.shadowOf(application).nextStartedActivity
        assertEquals(Settings.ACTION_APP_NOTIFICATION_SETTINGS, launched.action)
        assertEquals("denied", (result.value as Map<*, *>)["status"])
        assertEquals(1, result.completionCount)
    }

    private fun permissionCall(): MethodCall {
        return MethodCall(
            "requestPermissionIfNeeded",
            mapOf("schemaVersion" to AndroidAlarmBridge.SCHEMA_VERSION),
        )
    }

    private class CapturingResult : MethodChannel.Result {
        var value: Any? = null
        var errorCode: String? = null
        var completionCount = 0

        override fun success(result: Any?) {
            completionCount += 1
            value = result
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            completionCount += 1
            this.errorCode = errorCode
        }

        override fun notImplemented() {
            completionCount += 1
            errorCode = "NOT_IMPLEMENTED"
        }
    }

    private companion object {
        const val NOTIFICATION_PERMISSION_REQUEST_CODE = 7103
    }
}
