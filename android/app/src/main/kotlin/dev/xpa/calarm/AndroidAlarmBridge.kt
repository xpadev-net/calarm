package dev.xpa.calarm

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.time.Instant
import org.json.JSONObject

class AndroidAlarmBridge(private val context: Context) : MethodChannel.MethodCallHandler {
    private val appContext = context.applicationContext
    private val alarmManager = appContext.getSystemService(AlarmManager::class.java)
    private val notificationManager = appContext.getSystemService(NotificationManager::class.java)
    private val store = AlarmStore(appContext)

    fun register(binaryMessenger: BinaryMessenger) {
        ensureAlarmNotificationChannel()
        MethodChannel(binaryMessenger, CHANNEL_NAME).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        if (arguments == null || arguments["schemaVersion"] != SCHEMA_VERSION) {
            result.error("INVALID_REQUEST", "Unsupported native alarm schemaVersion.", null)
            return
        }

        when (call.method) {
            "getCapability" -> result.success(capabilityResponse())
            "requestPermissionIfNeeded" -> result.success(requestPermissionResponse())
            "scheduleOccurrences" -> result.success(scheduleOccurrences(arguments))
            "cancelOccurrences", "cancelPlan" -> result.success(cancel(arguments))
            "scheduleTestAlarm" -> result.success(scheduleTestAlarm(arguments))
            else -> result.notImplemented()
        }
    }

    private fun capabilityResponse(): Map<String, Any?> {
        val canExact = canScheduleExactAlarms()
        val notificationsAllowed = notificationsAllowed()
        val fullScreenAllowed = canUseFullScreenIntent()
        val notificationChannelReady = notificationChannelReady()
        val canSchedule = canExact && notificationsAllowed && fullScreenAllowed && notificationChannelReady
        return mutableResponse(
            "permissionStatus" to if (canSchedule) "authorized" else "denied",
            "canScheduleAlarms" to canSchedule,
            "canRequestPermission" to (!canExact || !notificationsAllowed || !fullScreenAllowed || !notificationChannelReady),
            "maxPendingAlarms" to null,
            "requiresExactAlarmPermission" to !canExact,
            "requiresNotificationPermission" to !notificationsAllowed,
            "requiresFullScreenIntentPermission" to !fullScreenAllowed,
            "requiresNotificationChannelSetup" to !notificationChannelReady,
            "supportsTestAlarm" to true,
        )
    }

    private fun requestPermissionResponse(): Map<String, Any?> {
        if (!canScheduleExactAlarms() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                data = Uri.parse("package:${appContext.packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            appContext.startActivity(intent)
        } else if (!notificationsAllowed() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            appContext.startActivity(appDetailsSettingsIntent())
        } else if (!canUseFullScreenIntent() && Build.VERSION.SDK_INT >= 34) {
            appContext.startActivity(appDetailsSettingsIntent())
        } else if (!notificationChannelReady() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            appContext.startActivity(appNotificationSettingsIntent())
        }

        val canSchedule = canScheduleExactAlarms() &&
            notificationsAllowed() &&
            canUseFullScreenIntent() &&
            notificationChannelReady()
        return mutableResponse(
            "status" to if (canSchedule) "granted" else "denied",
            "permissionStatus" to if (canSchedule) "authorized" else "denied",
        )
    }

    private fun scheduleOccurrences(arguments: Map<*, *>): Map<String, Any?> {
        val rows = arguments["occurrences"] as? List<*> ?: emptyList<Any?>()
        val results = rows.map { row ->
            val map = row as? Map<*, *>
            val request = AlarmRequest.fromScheduleMap(map)
            if (request == null) {
                scheduleFailure(
                    map?.get("occurrenceId") as? String ?: "",
                    map?.get("wakePlanId") as? String ?: "",
                    "invalidRequest",
                    "Invalid schedule occurrence.",
                )
            } else {
                schedule(request)
            }
        }
        return mutableResponse("occurrences" to results)
    }

    private fun scheduleTestAlarm(arguments: Map<*, *>): Map<String, Any?> {
        val fireAfterMillis = (arguments["fireAfterMillis"] as? Number)?.toLong()
        if (fireAfterMillis == null || fireAfterMillis <= 0) {
            return mutableResponse(
                "status" to "failure",
                "failureReason" to "invalidRequest",
                "failureMessage" to "fireAfterMillis must be positive.",
            )
        }

        val now = System.currentTimeMillis()
        val request = AlarmRequest(
            occurrenceId = "test-${now}",
            wakePlanId = "test",
            scheduledAtMillis = now + fireAfterMillis,
            targetAtMillis = now + fireAfterMillis,
            soundId = arguments["soundId"] as? String ?: "default",
            vibrationEnabled = arguments["vibrationEnabled"] as? Boolean ?: true,
            isTest = true,
        )
        val result = schedule(request)
        return if (result["status"] == "success") {
            mutableResponse(
                "status" to "success",
                "platformAlarmId" to result["platformAlarmId"],
            )
        } else {
            mutableResponse(
                "status" to "failure",
                "failureReason" to (result["failureReason"] ?: "nativeError"),
                "failureMessage" to result["failureMessage"],
            )
        }
    }

    private fun schedule(request: AlarmRequest): Map<String, Any?> {
        if (!canScheduleExactAlarms()) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "permissionMissing",
                "Exact alarm permission is not granted.",
            )
        }
        if (!notificationsAllowed()) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "permissionMissing",
                "Notification permission is not granted.",
            )
        }
        if (!canUseFullScreenIntent()) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "permissionMissing",
                "Full-screen intent permission is not granted.",
            )
        }
        if (!notificationChannelReady()) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "osConstraint",
                "Wake alarm notification channel is disabled.",
            )
        }
        if (request.scheduledAtMillis <= System.currentTimeMillis()) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "invalidRequest",
                "scheduledAt must be in the future.",
            )
        }

        val platformAlarmId = request.platformAlarmId
        return try {
            alarmManager.setAlarmClock(
                AlarmManager.AlarmClockInfo(
                    request.scheduledAtMillis,
                    AlarmIntents.showIntent(appContext, platformAlarmId),
                ),
                AlarmIntents.receiver(appContext, platformAlarmId),
            )
            if (!store.put(request.copy(platformAlarmIdOverride = platformAlarmId))) {
                alarmManager.cancel(AlarmIntents.receiver(appContext, platformAlarmId))
                return scheduleFailure(
                    request.occurrenceId,
                    request.wakePlanId,
                    "nativeError",
                    "Failed to persist native alarm mirror state.",
                )
            }
            mutableMapOf(
                "occurrenceId" to request.occurrenceId,
                "wakePlanId" to request.wakePlanId,
                "status" to "success",
                "platformAlarmId" to platformAlarmId,
            )
        } catch (error: RuntimeException) {
            scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "nativeError",
                error.message ?: "AlarmManager rejected the alarm.",
            )
        }
    }

    private fun cancel(arguments: Map<*, *>): Map<String, Any?> {
        val rows = arguments["alarms"] as? List<*> ?: emptyList<Any?>()
        val results = rows.map { row ->
            val map = row as? Map<*, *>
            val occurrenceId = map?.get("occurrenceId") as? String ?: ""
            val platformAlarmId = map?.get("platformAlarmId") as? String ?: ""
            if (occurrenceId.isBlank() || platformAlarmId.isBlank()) {
                cancelFailure(occurrenceId, platformAlarmId, "missingPlatformAlarmId", "Missing platformAlarmId.")
            } else {
                try {
                    alarmManager.cancel(AlarmIntents.receiver(appContext, platformAlarmId))
                    if (!store.remove(platformAlarmId)) {
                        cancelFailure(
                            occurrenceId,
                            platformAlarmId,
                            "nativeError",
                            "Failed to persist native alarm mirror removal.",
                        )
                    } else {
                        notificationManager.cancel(platformAlarmId.hashCode())
                        mutableMapOf(
                            "occurrenceId" to occurrenceId,
                            "platformAlarmId" to platformAlarmId,
                            "status" to "success",
                        )
                    }
                } catch (error: RuntimeException) {
                    cancelFailure(
                        occurrenceId,
                        platformAlarmId,
                        "nativeError",
                        error.message ?: "AlarmManager cancel failed.",
                    )
                }
            }
        }
        return mutableResponse("alarms" to results)
    }

    private fun canScheduleExactAlarms(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()
    }

    private fun notificationsAllowed(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            appContext.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    }

    private fun canUseFullScreenIntent(): Boolean {
        return Build.VERSION.SDK_INT < 34 || notificationManager.canUseFullScreenIntent()
    }

    private fun notificationChannelReady(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        return notificationManager.getNotificationChannel(AlarmNotificationChannel.ID)?.importance != NotificationManager.IMPORTANCE_NONE
    }

    private fun ensureAlarmNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        notificationManager.createNotificationChannel(AlarmNotificationChannel.create())
    }

    private fun appDetailsSettingsIntent(): Intent {
        return Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:${appContext.packageName}")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    }

    private fun appNotificationSettingsIntent(): Intent {
        return Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, appContext.packageName)
            putExtra(Settings.EXTRA_CHANNEL_ID, AlarmNotificationChannel.ID)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    }

    private fun mutableResponse(vararg pairs: Pair<String, Any?>): MutableMap<String, Any?> {
        return mutableMapOf("schemaVersion" to SCHEMA_VERSION, *pairs)
    }

    private fun scheduleFailure(
        occurrenceId: String,
        wakePlanId: String,
        reason: String,
        message: String,
    ): MutableMap<String, Any?> {
        return mutableMapOf(
            "occurrenceId" to occurrenceId,
            "wakePlanId" to wakePlanId,
            "status" to "failure",
            "failureReason" to reason,
            "failureMessage" to message,
        )
    }

    private fun cancelFailure(
        occurrenceId: String,
        platformAlarmId: String,
        reason: String,
        message: String,
    ): MutableMap<String, Any?> {
        return mutableMapOf(
            "occurrenceId" to occurrenceId,
            "platformAlarmId" to platformAlarmId,
            "status" to "failure",
            "failureReason" to reason,
            "failureMessage" to message,
        )
    }

    companion object {
        const val CHANNEL_NAME = "net.xpadev.calarm/native_alarm"
        const val SCHEMA_VERSION = 1
        const val ALARM_CHANNEL_ID = AlarmNotificationChannel.ID
    }
}

object AlarmNotificationChannel {
    const val ID = "wake_alarms"

    fun create(): NotificationChannel {
        return NotificationChannel(
            ID,
            "Wake alarms",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Calarm wake alarm alerts"
            setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM), null)
        }
    }
}

data class AlarmRequest(
    val occurrenceId: String,
    val wakePlanId: String,
    val scheduledAtMillis: Long,
    val targetAtMillis: Long,
    val soundId: String,
    val vibrationEnabled: Boolean,
    val isTest: Boolean = false,
    val platformAlarmIdOverride: String? = null,
) {
    val platformAlarmId: String
        get() = platformAlarmIdOverride ?: "android:${wakePlanId}:${occurrenceId}"

    fun toJson(): JSONObject {
        return JSONObject()
            .put("occurrenceId", occurrenceId)
            .put("wakePlanId", wakePlanId)
            .put("scheduledAtMillis", scheduledAtMillis)
            .put("targetAtMillis", targetAtMillis)
            .put("soundId", soundId)
            .put("vibrationEnabled", vibrationEnabled)
            .put("isTest", isTest)
            .put("platformAlarmId", platformAlarmId)
    }

    companion object {
        fun fromScheduleMap(map: Map<*, *>?): AlarmRequest? {
            if (map == null) return null
            val occurrenceId = map["occurrenceId"] as? String ?: return null
            val wakePlanId = map["wakePlanId"] as? String ?: return null
            val scheduledAt = map["scheduledAt"] as? String ?: return null
            val targetAt = map["targetAt"] as? String ?: return null
            val soundId = map["soundId"] as? String ?: return null
            val vibrationEnabled = map["vibrationEnabled"] as? Boolean ?: return null
            return try {
                AlarmRequest(
                    occurrenceId = occurrenceId,
                    wakePlanId = wakePlanId,
                    scheduledAtMillis = Instant.parse(scheduledAt).toEpochMilli(),
                    targetAtMillis = Instant.parse(targetAt).toEpochMilli(),
                    soundId = soundId,
                    vibrationEnabled = vibrationEnabled,
                )
            } catch (_: RuntimeException) {
                null
            }
        }

        fun fromJson(json: JSONObject): AlarmRequest {
            return AlarmRequest(
                occurrenceId = json.getString("occurrenceId"),
                wakePlanId = json.getString("wakePlanId"),
                scheduledAtMillis = json.getLong("scheduledAtMillis"),
                targetAtMillis = json.getLong("targetAtMillis"),
                soundId = json.getString("soundId"),
                vibrationEnabled = json.getBoolean("vibrationEnabled"),
                isTest = json.optBoolean("isTest", false),
                platformAlarmIdOverride = json.getString("platformAlarmId"),
            )
        }
    }
}

class AlarmStore(context: Context) {
    private val preferences: SharedPreferences =
        context.getSharedPreferences("native_alarm_store", Context.MODE_PRIVATE)

    fun put(request: AlarmRequest): Boolean {
        return preferences.edit()
            .putString(request.platformAlarmId, request.toJson().toString())
            .commit()
    }

    fun remove(platformAlarmId: String): Boolean {
        return preferences.edit().remove(platformAlarmId).commit()
    }

    fun get(platformAlarmId: String): AlarmRequest? {
        return try {
            val value = preferences.getString(platformAlarmId, null) ?: return null
            AlarmRequest.fromJson(JSONObject(value))
        } catch (_: Exception) {
            null
        }
    }

    fun contains(platformAlarmId: String): Boolean {
        return preferences.contains(platformAlarmId)
    }

    fun all(): List<AlarmRequest> {
        return preferences.all.values.mapNotNull { value ->
            try {
                AlarmRequest.fromJson(JSONObject(value as String))
            } catch (_: Exception) {
                null
            }
        }
    }
}

object AlarmRestore {
    fun restore(context: Context) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val store = AlarmStore(context)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
            return
        }
        store.all().forEach { request ->
            if (request.scheduledAtMillis <= System.currentTimeMillis()) {
                store.remove(request.platformAlarmId)
            } else {
                try {
                    alarmManager.setAlarmClock(
                        AlarmManager.AlarmClockInfo(
                            request.scheduledAtMillis,
                            AlarmIntents.showIntent(context, request.platformAlarmId),
                        ),
                        AlarmIntents.receiver(context, request.platformAlarmId),
                    )
                } catch (_: RuntimeException) {
                    store.remove(request.platformAlarmId)
                }
            }
        }
    }
}

object AlarmIntents {
    const val EXTRA_PLATFORM_ALARM_ID = "platformAlarmId"
    const val EXTRA_OCCURRENCE_ID = "occurrenceId"
    const val ACTION_ALARM_FIRE = "dev.xpa.calarm.ALARM_FIRE"
    const val ACTION_ALARM_STOP = "dev.xpa.calarm.ALARM_STOP"
    const val ACTION_ALARM_SHOW = "dev.xpa.calarm.ALARM_SHOW"

    fun receiver(context: Context, platformAlarmId: String): PendingIntent {
        val intent = Intent(context, AlarmReceiver::class.java)
            .setAction(ACTION_ALARM_FIRE)
            .setData(identityUri(platformAlarmId))
            .putExtra(EXTRA_PLATFORM_ALARM_ID, platformAlarmId)
        return PendingIntent.getBroadcast(
            context,
            requestCode(platformAlarmId),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun stopActivity(context: Context, platformAlarmId: String): PendingIntent {
        val intent = stopActivityIntent(context, platformAlarmId)
        return PendingIntent.getActivity(
            context,
            requestCode(platformAlarmId),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun showIntent(context: Context, platformAlarmId: String): PendingIntent {
        val intent = Intent(context, AlarmStopActivity::class.java)
            .setAction(ACTION_ALARM_SHOW)
            .setData(identityUri(platformAlarmId))
            .putExtra(EXTRA_PLATFORM_ALARM_ID, platformAlarmId)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            context,
            requestCode(platformAlarmId),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun stopActivityIntent(context: Context, platformAlarmId: String): Intent {
        return Intent(context, AlarmStopActivity::class.java)
            .setAction(ACTION_ALARM_STOP)
            .setData(identityUri(platformAlarmId))
            .putExtra(EXTRA_PLATFORM_ALARM_ID, platformAlarmId)
            .addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
    }

    private fun requestCode(platformAlarmId: String): Int {
        return platformAlarmId.hashCode()
    }

    private fun identityUri(platformAlarmId: String): Uri {
        return Uri.Builder()
            .scheme("calarm")
            .authority("native-alarm")
            .appendPath(platformAlarmId)
            .build()
    }
}
