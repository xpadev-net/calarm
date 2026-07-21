package dev.xpa.calarm

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.UserManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.time.Instant
import org.json.JSONException
import org.json.JSONObject

class AndroidAlarmBridge(private val context: Context) : MethodChannel.MethodCallHandler {
    private val activity = context as? Activity
    private val appContext = context.applicationContext
    private val alarmManager = appContext.getSystemService(AlarmManager::class.java)
    private val notificationManager = appContext.getSystemService(NotificationManager::class.java)
    private val store = AlarmStore(appContext)
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null
    private var requestNotificationRuntimePermission: (Activity, Array<String>, Int) -> Unit =
        { permissionActivity, permissions, requestCode ->
            permissionActivity.requestPermissions(permissions, requestCode)
        }
    private var launchSettingsActivity: (Intent) -> Unit = { intent ->
        appContext.startActivity(intent)
    }

    internal constructor(
        context: Context,
        requestNotificationRuntimePermission: (Activity, Array<String>, Int) -> Unit,
    ) : this(context) {
        this.requestNotificationRuntimePermission = requestNotificationRuntimePermission
    }

    internal constructor(
        context: Context,
        launchSettingsActivity: (Intent) -> Unit,
    ) : this(context) {
        this.launchSettingsActivity = launchSettingsActivity
    }

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
            "requestPermissionIfNeeded" -> requestPermission(result)
            "scheduleOccurrences" -> result.success(scheduleOccurrences(arguments))
            "cancelOccurrences", "cancelPlan" -> result.success(cancel(arguments))
            "getInventory" -> {
                val inventory = inventoryResponse()
                if (inventory.failureCode != null) {
                    result.error(inventory.failureCode, inventory.failureMessage, null)
                } else {
                    result.success(inventory.response)
                }
            }
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
            "supportsInventory" to true,
        )
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (!canScheduleExactAlarms() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                data = Uri.parse("package:${appContext.packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startSettingsActivity(intent)
        } else if (!notificationRuntimePermissionAllowed() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requestNotificationPermission(result)
            return
        } else if (!appNotificationsEnabled() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            requestAppNotificationSettings()
        } else if (!canUseFullScreenIntent() && Build.VERSION.SDK_INT >= 34) {
            requestFullScreenIntentPermission()
        } else if (!notificationChannelReady() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startSettingsActivity(appNotificationSettingsIntent())
        }

        result.success(permissionResponse())
    }

    private fun permissionResponse(): Map<String, Any?> {
        val canSchedule = canScheduleExactAlarms() &&
            notificationsAllowed() &&
            canUseFullScreenIntent() &&
            notificationChannelReady()
        return mutableResponse(
            "status" to if (canSchedule) "granted" else "denied",
            "permissionStatus" to if (canSchedule) "authorized" else "denied",
        )
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (pendingNotificationPermissionResult != null) {
            result.error("REQUEST_IN_PROGRESS", "A notification permission request is already active.", null)
            return
        }

        val preferences = appContext.getSharedPreferences(PERMISSION_PREFERENCES, Context.MODE_PRIVATE)
        val requestedBefore = preferences.getBoolean(KEY_NOTIFICATION_PERMISSION_REQUESTED, false)
        val permissionActivity = activity
        if (permissionActivity == null) {
            requestAppNotificationSettings()
            result.success(permissionResponse())
            return
        }
        val shouldShowRationale = permissionActivity.shouldShowRequestPermissionRationale(
            Manifest.permission.POST_NOTIFICATIONS,
        )
        if (requestedBefore && !shouldShowRationale) {
            requestAppNotificationSettings()
            result.success(permissionResponse())
            return
        }

        preferences.edit().putBoolean(KEY_NOTIFICATION_PERMISSION_REQUESTED, true).apply()
        pendingNotificationPermissionResult = result
        try {
            requestNotificationRuntimePermission(
                permissionActivity,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST_CODE,
            )
        } catch (error: RuntimeException) {
            pendingNotificationPermissionResult = null
            preferences.edit().putBoolean(KEY_NOTIFICATION_PERMISSION_REQUESTED, false).apply()
            result.error(
                "UNAVAILABLE",
                error.message ?: "Notification permission request failed.",
                null,
            )
        }
    }

    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST_CODE) return false
        val result = pendingNotificationPermissionResult ?: return true
        pendingNotificationPermissionResult = null
        result.success(permissionResponse())
        return true
    }

    fun detach() {
        val result = pendingNotificationPermissionResult ?: return
        pendingNotificationPermissionResult = null
        result.error("UNAVAILABLE", "Activity was destroyed during the permission request.", null)
    }

    private fun requestFullScreenIntentPermission() {
        val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
            data = Uri.parse("package:${appContext.packageName}")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startSettingsActivity(intent)
    }

    private fun startSettingsActivity(intent: Intent) {
        try {
            launchSettingsActivity(intent)
        } catch (_: ActivityNotFoundException) {
            launchSettingsActivity(appDetailsSettingsIntent())
        } catch (_: SecurityException) {
            launchSettingsActivity(appDetailsSettingsIntent())
        }
    }

    private fun scheduleOccurrences(arguments: Map<*, *>): Map<String, Any?> {
        val rows = arguments["occurrences"] as? List<*> ?: emptyList<Any?>()
        val results = rows.map { row ->
            val map = row as? Map<*, *>
            val request = AlarmRequest.fromScheduleMap(map)
            if (request == null) {
                val invalidReservationId = (map?.get("reservationId") as? String)
                    ?.takeIf { it.isNotBlank() }
                    ?: (map?.get("occurrenceId") as? String).orEmpty()
                scheduleFailure(
                    map?.get("occurrenceId") as? String ?: "",
                    map?.get("wakePlanId") as? String ?: "",
                    "invalidRequest",
                    "Invalid schedule occurrence.",
                    invalidReservationId,
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
        val requestedPlatformAlarmId = request.platformAlarmId
        val legacyPlatformAlarmId = AlarmRequest.legacyPlatformAlarmId(request)
        val legacyRequest = if (legacyPlatformAlarmId != requestedPlatformAlarmId) {
            store.get(legacyPlatformAlarmId)
        } else {
            null
        }
        if (
            legacyPlatformAlarmId != requestedPlatformAlarmId &&
            store.contains(legacyPlatformAlarmId) &&
            legacyRequest == null
        ) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "nativeError",
                "Legacy native alarm mirror row is corrupt.",
                request.reservationId,
            )
        }
        val legacyIdentityMatches = legacyRequest != null &&
            legacyRequest.occurrenceId == request.occurrenceId &&
            legacyRequest.wakePlanId == request.wakePlanId &&
            (legacyRequest.reservationId == legacyRequest.occurrenceId ||
                legacyRequest.reservationId == request.reservationId)
        if (legacyRequest != null && legacyRequest.platformAlarmId != legacyPlatformAlarmId) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "nativeError",
                "Legacy native alarm mirror row is corrupt.",
                request.reservationId,
            )
        }
        if (legacyRequest != null && !legacyRequest.hasCanonicalPlatformAlarmId()) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "nativeError",
                "Legacy native alarm mirror row is corrupt.",
                request.reservationId,
            )
        }
        if (legacyRequest != null && !legacyIdentityMatches) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "invalidRequest",
                "Legacy native alarm identity conflicts with the requested reservation.",
                request.reservationId,
            )
        }

        if (legacyRequest != null && store.contains(requestedPlatformAlarmId)) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "invalidRequest",
                "Stable and legacy native alarm identities both exist for the occurrence.",
                request.reservationId,
            )
        }

        val platformAlarmId = if (legacyRequest != null) {
            legacyPlatformAlarmId
        } else {
            requestedPlatformAlarmId
        }
        val existing = store.get(platformAlarmId)
        if (store.contains(platformAlarmId) && existing == null) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "nativeError",
                "Native alarm mirror row is corrupt.",
                request.reservationId,
            )
        }
        if (existing != null && !existing.hasCanonicalPlatformAlarmId()) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "nativeError",
                "Native alarm mirror row is corrupt.",
                request.reservationId,
            )
        }
        if (
            existing != null &&
            legacyRequest == null &&
            !sameIdentity(existing, request)
        ) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "invalidRequest",
                "Native alarm identity is already owned by another reservation.",
                request.reservationId,
            )
        }
        if (existing?.state == AlarmState.RINGING) {
            if (
                existing.occurrenceId != request.occurrenceId ||
                existing.wakePlanId != request.wakePlanId ||
                existing.scheduledAtMillis != request.scheduledAtMillis
            ) {
                return scheduleFailure(
                    request.occurrenceId,
                    request.wakePlanId,
                    "invalidRequest",
                    "Cannot replace an actively ringing native alarm.",
                    request.reservationId,
                )
            }
            if (legacyRequest != null && existing.reservationId != request.reservationId) {
                val adoptedRingingRequest = existing.copy(
                    reservationId = request.reservationId,
                    platformAlarmIdOverride = platformAlarmId,
                )
                if (!store.put(adoptedRingingRequest)) {
                    return scheduleFailure(
                        request.occurrenceId,
                        request.wakePlanId,
                        "nativeError",
                        "Failed to persist native alarm mirror state.",
                        request.reservationId,
                    )
                }
            }
            return scheduleSuccess(request, platformAlarmId)
        }
        if (!canScheduleExactAlarms()) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "permissionMissing",
                "Exact alarm permission is not granted.",
                request.reservationId,
            )
        }
        if (!notificationsAllowed()) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "permissionMissing",
                "Notification permission is not granted.",
                request.reservationId,
            )
        }
        if (!canUseFullScreenIntent()) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "permissionMissing",
                "Full-screen intent permission is not granted.",
                request.reservationId,
            )
        }
        if (!notificationChannelReady()) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "osConstraint",
                "Wake alarm notification channel is disabled.",
                request.reservationId,
            )
        }
        if (request.scheduledAtMillis <= System.currentTimeMillis()) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "invalidRequest",
                "scheduledAt must be in the future.",
                request.reservationId,
            )
        }

        return armAndPersist(request, platformAlarmId)
    }

    private fun armAndPersist(
        request: AlarmRequest,
        platformAlarmId: String,
        arm: () -> Unit = {
            alarmManager.setAlarmClock(
                AlarmManager.AlarmClockInfo(
                    request.scheduledAtMillis,
                    AlarmIntents.showIntent(appContext, platformAlarmId),
                ),
                AlarmIntents.receiver(appContext, platformAlarmId),
            )
        },
        persist: () -> Boolean = {
            store.put(request.copy(platformAlarmIdOverride = platformAlarmId, state = AlarmState.SCHEDULED))
        },
        cancel: () -> Unit = { cancelReceiver(platformAlarmId) },
    ): MutableMap<String, Any?> {
        return try {
            arm()
            if (!persist()) {
                cancel()
                return scheduleFailure(
                    request.occurrenceId,
                    request.wakePlanId,
                    "nativeError",
                    "Failed to persist native alarm mirror state.",
                    request.reservationId,
                )
            }
            scheduleSuccess(request, platformAlarmId)
        } catch (error: JSONException) {
            cancel()
            scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "nativeError",
                error.message ?: "Failed to persist native alarm mirror state.",
                request.reservationId,
            )
        } catch (error: RuntimeException) {
            cancel()
            scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "nativeError",
                error.message ?: "AlarmManager rejected the alarm.",
                request.reservationId,
            )
        }
    }

    internal fun armAndPersistForTest(
        request: AlarmRequest,
        platformAlarmId: String,
        arm: () -> Unit,
        persist: () -> Boolean,
        cancel: () -> Unit,
    ): Map<String, Any?> {
        return armAndPersist(request, platformAlarmId, arm, persist, cancel)
    }

    private fun cancelReceiver(platformAlarmId: String) {
        try {
            alarmManager.cancel(AlarmIntents.receiver(appContext, platformAlarmId))
        } catch (_: RuntimeException) {
            // Preserve the original schedule failure if cleanup is rejected.
        }
    }

    private fun scheduleSuccess(
        request: AlarmRequest,
        platformAlarmId: String,
    ): MutableMap<String, Any?> {
        return mutableMapOf(
            "occurrenceId" to request.occurrenceId,
            "reservationId" to request.reservationId,
            "wakePlanId" to request.wakePlanId,
            "status" to "success",
            "platformAlarmId" to platformAlarmId,
        )
    }

    private fun sameIdentity(left: AlarmRequest, right: AlarmRequest): Boolean {
        return left.reservationId == right.reservationId &&
            left.occurrenceId == right.occurrenceId &&
            left.wakePlanId == right.wakePlanId
    }

    private fun cancel(arguments: Map<*, *>): Map<String, Any?> {
        val rows = arguments["alarms"] as? List<*> ?: emptyList<Any?>()
        val results = rows.map { row ->
            val map = row as? Map<*, *>
            val occurrenceId = map?.get("occurrenceId") as? String ?: ""
            val rawReservationId = map?.get("reservationId")
            val reservationId = when (rawReservationId) {
                null -> occurrenceId
                is String -> rawReservationId
                else -> ""
            }
            val platformAlarmId = map?.get("platformAlarmId") as? String ?: ""
            cancelOne(occurrenceId, reservationId, platformAlarmId)
        }
        return mutableResponse("alarms" to results)
    }

    private fun cancelOne(
        occurrenceId: String,
        reservationId: String,
        platformAlarmId: String,
    ): MutableMap<String, Any?> {
        if (occurrenceId.isBlank() || reservationId.isBlank() || platformAlarmId.isBlank()) {
            return cancelFailure(
                occurrenceId,
                platformAlarmId,
                if (platformAlarmId.isBlank()) "missingPlatformAlarmId" else "invalidRequest",
                if (platformAlarmId.isBlank()) "Missing platformAlarmId." else "Invalid cancel identity.",
                reservationId,
            )
        }
        return try {
            val stored = store.get(platformAlarmId)
            when {
                store.contains(platformAlarmId) && stored == null -> cancelFailure(
                    occurrenceId,
                    platformAlarmId,
                    "nativeError",
                    "Native alarm mirror row is corrupt.",
                    reservationId,
                )
                stored != null &&
                    (stored.platformAlarmId != platformAlarmId ||
                        !stored.hasCanonicalPlatformAlarmId()) -> cancelFailure(
                    occurrenceId,
                    platformAlarmId,
                    "nativeError",
                    "Native alarm mirror row is corrupt.",
                    reservationId,
                )
                stored != null &&
                    !cancelIdentityMatches(stored, occurrenceId, reservationId) ->
                    cancelFailure(
                        occurrenceId,
                        platformAlarmId,
                        "invalidRequest",
                        "Native alarm identity does not match the requested reservation.",
                        reservationId,
                    )
                else -> {
                    alarmManager.cancel(AlarmIntents.receiver(appContext, platformAlarmId))
                    if (!store.remove(platformAlarmId)) {
                        cancelFailure(
                            occurrenceId,
                            platformAlarmId,
                            "nativeError",
                            "Failed to persist native alarm mirror removal.",
                            reservationId,
                        )
                    } else {
                        notificationManager.cancel(platformAlarmId.hashCode())
                        mutableMapOf(
                            "occurrenceId" to occurrenceId,
                            "reservationId" to reservationId,
                            "platformAlarmId" to platformAlarmId,
                            "status" to "success",
                        )
                    }
                }
            }
        } catch (error: RuntimeException) {
            cancelFailure(
                occurrenceId,
                platformAlarmId,
                "nativeError",
                error.message ?: "AlarmManager cancel failed.",
                reservationId,
            )
        }
    }

    private fun cancelIdentityMatches(
        stored: AlarmRequest,
        occurrenceId: String,
        reservationId: String,
    ): Boolean {
        if (isSyntheticTestAlarm(stored)) return true
        if (stored.occurrenceId != occurrenceId) return false
        if (stored.reservationId == reservationId) return true
        return reservationId == occurrenceId &&
            stored.reservationId != stored.occurrenceId &&
            stored.platformAlarmId == AlarmRequest.legacyPlatformAlarmId(stored)
    }

    private fun canScheduleExactAlarms(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()
    }

    private fun notificationsAllowed(): Boolean {
        return notificationRuntimePermissionAllowed() && appNotificationsEnabled()
    }

    private fun notificationRuntimePermissionAllowed(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            appContext.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    }

    private fun appNotificationsEnabled(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.N || notificationManager.areNotificationsEnabled()
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

    private fun appNotificationPermissionSettingsIntent(): Intent {
        return Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, appContext.packageName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    }

    private fun requestAppNotificationSettings() {
        startSettingsActivity(appNotificationPermissionSettingsIntent())
    }

    private fun mutableResponse(vararg pairs: Pair<String, Any?>): MutableMap<String, Any?> {
        return mutableMapOf("schemaVersion" to SCHEMA_VERSION, *pairs)
    }

    private fun scheduleFailure(
        occurrenceId: String,
        wakePlanId: String,
        reason: String,
        message: String,
        reservationId: String = occurrenceId,
    ): MutableMap<String, Any?> {
        return mutableMapOf(
            "occurrenceId" to occurrenceId,
            "reservationId" to reservationId,
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
        reservationId: String = occurrenceId,
    ): MutableMap<String, Any?> {
        return mutableMapOf(
            "occurrenceId" to occurrenceId,
            "reservationId" to reservationId,
            "platformAlarmId" to platformAlarmId,
            "status" to "failure",
            "failureReason" to reason,
            "failureMessage" to message,
        )
    }

    private fun isSyntheticTestAlarm(request: AlarmRequest): Boolean {
        return request.isTest &&
            request.wakePlanId == "test" &&
            request.reservationId == request.occurrenceId &&
            request.occurrenceId.startsWith("test-") &&
            request.platformAlarmId == "android:test:${request.occurrenceId}"
    }

    private fun inventoryResponse(): InventoryResponse {
        val snapshot = store.inventory(appContext, System.currentTimeMillis())
        if (snapshot.corruptKeys.isNotEmpty()) {
            return InventoryResponse(
                response = null,
                failureCode = "CORRUPT",
                failureMessage = "Removed corrupt native alarm mirror rows: ${snapshot.corruptKeys.joinToString()}.",
            )
        }
        if (snapshot.duplicateIdentity != null) {
            return InventoryResponse(
                response = null,
                failureCode = "CORRUPT",
                failureMessage = snapshot.duplicateIdentity,
            )
        }
        return InventoryResponse(
            response = mutableResponse(
                "reservations" to snapshot.requests.map { request ->
                    mutableMapOf(
                        "reservationId" to request.reservationId,
                        "occurrenceId" to request.occurrenceId,
                        "wakePlanId" to request.wakePlanId,
                        "platformAlarmId" to request.platformAlarmId,
                        "status" to snapshot.status(request),
                    )
                },
            ),
        )
    }

    private data class InventoryResponse(
        val response: Map<String, Any?>?,
        val failureCode: String? = null,
        val failureMessage: String? = null,
    )

    companion object {
        const val CHANNEL_NAME = "net.xpadev.calarm/native_alarm"
        const val SCHEMA_VERSION = 1
        const val ALARM_CHANNEL_ID = AlarmNotificationChannel.ID
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 7103
        private const val PERMISSION_PREFERENCES = "native_alarm_permissions"
        private const val KEY_NOTIFICATION_PERMISSION_REQUESTED = "notification_requested"
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
    val reservationId: String = occurrenceId,
    val wakePlanId: String,
    val scheduledAtMillis: Long,
    val targetAtMillis: Long,
    val soundId: String,
    val vibrationEnabled: Boolean,
    val isTest: Boolean = false,
    val platformAlarmIdOverride: String? = null,
    val updatedAtMillis: Long = 0L,
    val state: AlarmState = AlarmState.SCHEDULED,
    val indexInPlan: Int? = null,
    val totalInPlan: Int? = null,
) {
    init {
        require((indexInPlan == null) == (totalInPlan == null)) {
            "Alarm position must include both indexInPlan and totalInPlan."
        }
        if (indexInPlan != null && totalInPlan != null) {
            require(indexInPlan >= 0) { "indexInPlan must not be negative." }
            require(totalInPlan > 0) { "totalInPlan must be positive." }
            require(indexInPlan < totalInPlan) { "indexInPlan must be less than totalInPlan." }
        }
    }

    val platformAlarmId: String
        get() = platformAlarmIdOverride ?: if (reservationId == occurrenceId) {
            legacyPlatformAlarmId(this)
        } else {
            stablePlatformAlarmId(this)
        }

    fun hasCanonicalPlatformAlarmId(): Boolean {
        return occurrenceId.isNotBlank() &&
            wakePlanId.isNotBlank() &&
            (platformAlarmId == stablePlatformAlarmId(this) ||
                platformAlarmId == legacyPlatformAlarmId(this) ||
                (isTest && platformAlarmId == "android:test:$occurrenceId"))
    }

    fun toJson(): JSONObject {
        val json = JSONObject()
            .put("occurrenceId", occurrenceId)
            .put("reservationId", reservationId)
            .put("wakePlanId", wakePlanId)
            .put("scheduledAtMillis", scheduledAtMillis)
            .put("targetAtMillis", targetAtMillis)
            .put("soundId", soundId)
            .put("vibrationEnabled", vibrationEnabled)
            .put("isTest", isTest)
            .put("platformAlarmId", platformAlarmId)
            .put("updatedAtMillis", updatedAtMillis)
            .put("state", state.value)
        indexInPlan?.let { json.put("indexInPlan", it) }
        totalInPlan?.let { json.put("totalInPlan", it) }
        return json
    }

    companion object {
        fun legacyPlatformAlarmId(request: AlarmRequest): String {
            return "android:${request.wakePlanId}:${request.occurrenceId}"
        }

        fun stablePlatformAlarmId(request: AlarmRequest): String {
            return "android:reservation:${request.reservationId}"
        }

        fun fromScheduleMap(map: Map<*, *>?): AlarmRequest? {
            if (map == null) return null
            val occurrenceId = (map["occurrenceId"] as? String)
                ?.takeIf { it.isNotBlank() }
                ?: return null
            val wakePlanId = (map["wakePlanId"] as? String)
                ?.takeIf { it.isNotBlank() }
                ?: return null
            val scheduledAt = map["scheduledAt"] as? String ?: return null
            val targetAt = map["targetAt"] as? String ?: return null
            val soundId = map["soundId"] as? String ?: return null
            val vibrationEnabled = map["vibrationEnabled"] as? Boolean ?: return null
            val reservationValue = map["reservationId"]
            val reservationId = when (reservationValue) {
                null -> occurrenceId
                is String -> reservationValue.takeIf { it.isNotBlank() } ?: return null
                else -> return null
            }
            return try {
                val (indexInPlan, totalInPlan) = parsePosition(
                    map["indexInPlan"],
                    map["totalInPlan"],
                )
                AlarmRequest(
                    occurrenceId = occurrenceId,
                    reservationId = reservationId,
                    wakePlanId = wakePlanId,
                    scheduledAtMillis = Instant.parse(scheduledAt).toEpochMilli(),
                    targetAtMillis = Instant.parse(targetAt).toEpochMilli(),
                    soundId = soundId,
                    vibrationEnabled = vibrationEnabled,
                    indexInPlan = indexInPlan,
                    totalInPlan = totalInPlan,
                )
            } catch (_: RuntimeException) {
                null
            }
        }

        fun fromJson(json: JSONObject): AlarmRequest {
            val occurrenceId = json.getString("occurrenceId")
                .takeIf { it.isNotBlank() }
                ?: throw IllegalArgumentException("occurrenceId must not be blank")
            val wakePlanId = json.getString("wakePlanId")
                .takeIf { it.isNotBlank() }
                ?: throw IllegalArgumentException("wakePlanId must not be blank")
            val reservationId = when {
                !json.has("reservationId") -> occurrenceId
                json.opt("reservationId") is String -> json.getString("reservationId")
                    .takeIf { it.isNotBlank() }
                    ?: throw IllegalArgumentException("reservationId must not be blank")
                else -> throw IllegalArgumentException("reservationId must be a string")
            }
            val (indexInPlan, totalInPlan) = parsePosition(
                json.opt("indexInPlan"),
                json.opt("totalInPlan"),
            )
            return AlarmRequest(
                occurrenceId = occurrenceId,
                reservationId = reservationId,
                wakePlanId = wakePlanId,
                scheduledAtMillis = json.getLong("scheduledAtMillis"),
                targetAtMillis = json.getLong("targetAtMillis"),
                soundId = json.getString("soundId"),
                vibrationEnabled = json.getBoolean("vibrationEnabled"),
                isTest = json.optBoolean("isTest", false),
                platformAlarmIdOverride = json.getString("platformAlarmId"),
                updatedAtMillis = json.optLong("updatedAtMillis", 0L),
                state = AlarmState.fromValue(json.optString("state", AlarmState.SCHEDULED.value)),
                indexInPlan = indexInPlan,
                totalInPlan = totalInPlan,
            )
        }

        private fun parsePosition(indexValue: Any?, totalValue: Any?): Pair<Int?, Int?> {
            if (indexValue == null && totalValue == null) return null to null
            val index = exactInt(indexValue)
                ?: throw IllegalArgumentException("indexInPlan must be an integer")
            val total = exactInt(totalValue)
                ?: throw IllegalArgumentException("totalInPlan must be an integer")
            if (index < 0 || total <= 0 || index >= total) {
                throw IllegalArgumentException("Alarm position is out of range")
            }
            return index to total
        }

        private fun exactInt(value: Any?): Int? {
            val number = value as? Number ?: return null
            val longValue = number.toLong()
            if (longValue !in Int.MIN_VALUE..Int.MAX_VALUE) return null
            if (number.toDouble() != longValue.toDouble()) return null
            return longValue.toInt()
        }
    }
}

enum class AlarmState(val value: String) {
    SCHEDULED("scheduled"),
    RINGING("ringing");

    companion object {
        fun fromValue(value: String): AlarmState {
            return entries.firstOrNull { it.value == value }
                ?: throw IllegalArgumentException("Unknown native alarm state: $value")
        }
    }
}

class AlarmStore(context: Context) {
    private val storageContext = deviceProtectedStorageContext(context)
    private val preferences: SharedPreferences =
        storageContext.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    init {
        migrateCredentialProtectedRows(context)
    }

    fun put(request: AlarmRequest): Boolean {
        val persistedRequest = request.copy(updatedAtMillis = System.currentTimeMillis())
        return preferences.edit()
            .putString(persistedRequest.platformAlarmId, persistedRequest.toJson().toString())
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

    fun markRinging(platformAlarmId: String): Boolean {
        val request = get(platformAlarmId) ?: return false
        if (
            request.platformAlarmId != platformAlarmId ||
            !request.hasCanonicalPlatformAlarmId()
        ) return false
        return put(request.copy(state = AlarmState.RINGING))
    }

    fun inventory(context: Context, nowMillis: Long): AlarmInventorySnapshot {
        val corruptKeys = mutableListOf<String>()
        val expiredKeys = mutableListOf<String>()
        val requests = mutableListOf<AlarmRequest>()
        preferences.all.forEach { (key, value) ->
            val request = try {
                (value as? String)?.let { AlarmRequest.fromJson(JSONObject(it)) }
            } catch (_: Exception) {
                null
            }
            if (
                request == null ||
                request.platformAlarmId != key ||
                !request.hasCanonicalPlatformAlarmId()
            ) {
                corruptKeys += key
            } else if (request.state != AlarmState.RINGING && request.scheduledAtMillis <= nowMillis) {
                expiredKeys += key
            } else {
                requests += request
            }
        }
        val cleanupKeys = corruptKeys + expiredKeys
        if (cleanupKeys.isNotEmpty()) {
            val editor = preferences.edit()
            cleanupKeys.forEach { key -> editor.remove(key) }
            if (!editor.commit()) {
                return AlarmInventorySnapshot(
                    requests = emptyList(),
                    corruptKeys = cleanupKeys,
                    duplicateIdentity = "Failed to clean native alarm mirror rows.",
                    context = context,
                )
            }
        }

        val duplicateReservation = requests.groupBy { it.reservationId }
            .values.firstOrNull { it.size > 1 }
        if (duplicateReservation != null) {
            return AlarmInventorySnapshot(
                requests = emptyList(),
                corruptKeys = corruptKeys,
                duplicateIdentity = "Duplicate native reservation identity: ${duplicateReservation.first().reservationId}.",
                context = context,
            )
        }
        val duplicateOccurrence = requests.groupBy { it.occurrenceId }
            .values.firstOrNull { it.size > 1 }
        if (duplicateOccurrence != null) {
            return AlarmInventorySnapshot(
                requests = emptyList(),
                corruptKeys = corruptKeys,
                duplicateIdentity = "Duplicate native occurrence identity: ${duplicateOccurrence.first().occurrenceId}.",
                context = context,
            )
        }
        return AlarmInventorySnapshot(
            requests = requests,
            corruptKeys = corruptKeys,
            context = context,
        )
    }

    fun all(): List<AlarmRequest> {
        val invalidKeys = mutableListOf<String>()
        val requestsById = linkedMapOf<String, AlarmRequest>()
        preferences.all.forEach { (key, value) ->
            val request = try {
                (value as? String)?.let { AlarmRequest.fromJson(JSONObject(it)) }
            } catch (_: Exception) {
                null
            }
            if (
                request == null ||
                request.platformAlarmId != key ||
                !request.hasCanonicalPlatformAlarmId()
            ) {
                invalidKeys += key
            } else if (!requestsById.containsKey(request.platformAlarmId)) {
                requestsById[request.platformAlarmId] = request
            }
        }
        if (invalidKeys.isNotEmpty()) {
            val editor = preferences.edit()
            invalidKeys.forEach { key -> editor.remove(key) }
            editor.commit()
        }
        return requestsById.values.toList()
    }

    fun nextScheduledAfter(wakePlanId: String, afterMillis: Long): AlarmRequest? {
        return all()
            .asSequence()
            .filter {
                it.wakePlanId == wakePlanId &&
                    !it.isTest &&
                    it.state == AlarmState.SCHEDULED &&
                    it.scheduledAtMillis > afterMillis
            }
            .minWithOrNull(
                compareBy<AlarmRequest> { it.scheduledAtMillis }
                    .thenBy { it.targetAtMillis }
                    .thenBy { it.platformAlarmId },
            )
    }

    private companion object {
        const val PREFERENCES_NAME = "native_alarm_store"

        fun migrateCredentialProtectedRows(context: Context) {
            if (
                Build.VERSION.SDK_INT < Build.VERSION_CODES.N ||
                context.isDeviceProtectedStorage ||
                !isUserUnlocked(context)
            ) {
                return
            }
            val applicationContext = context.applicationContext
            if (applicationContext.isDeviceProtectedStorage) return

            val credentialPreferences = applicationContext.getSharedPreferences(
                PREFERENCES_NAME,
                Context.MODE_PRIVATE,
            )
            val deviceProtectedPreferences = applicationContext
                .createDeviceProtectedStorageContext()
                .getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            val editor = deviceProtectedPreferences.edit()
            val copiedKeys = mutableListOf<String>()
            val deviceRows = deviceProtectedPreferences.all
            credentialPreferences.all.forEach { (key, value) ->
                val credentialRequest = parseAlarmRequest(value)
                val deviceRequest = parseAlarmRequest(deviceRows[key])
                val shouldCopyCredential = credentialRowIsNewer(credentialRequest, deviceRequest)
                if (shouldCopyCredential && putValue(editor, key, value)) {
                    copiedKeys += key
                } else if (deviceRows[key] == value || deviceRequest != null) {
                    copiedKeys += key
                }
            }
            if (copiedKeys.isEmpty() || !editor.commit()) return

            val cleanupEditor = credentialPreferences.edit()
            copiedKeys.forEach { key -> cleanupEditor.remove(key) }
            cleanupEditor.commit()
        }

        private fun credentialRowIsNewer(
            credentialRequest: AlarmRequest?,
            deviceRequest: AlarmRequest?,
        ): Boolean {
            if (deviceRequest == null) return true
            if (credentialRequest == null) return false
            return if (credentialRequest.updatedAtMillis != deviceRequest.updatedAtMillis) {
                credentialRequest.updatedAtMillis > deviceRequest.updatedAtMillis
            } else {
                credentialRequest.scheduledAtMillis > deviceRequest.scheduledAtMillis
            }
        }

        private fun parseAlarmRequest(value: Any?): AlarmRequest? {
            return try {
                (value as? String)?.let { AlarmRequest.fromJson(JSONObject(it)) }
            } catch (_: Exception) {
                null
            }
        }

        private fun isUserUnlocked(context: Context): Boolean {
            return context.getSystemService(UserManager::class.java)?.isUserUnlocked != false
        }

        private fun putValue(
            editor: SharedPreferences.Editor,
            key: String,
            value: Any?,
        ): Boolean {
            return when (value) {
                is Boolean -> {
                    editor.putBoolean(key, value)
                    true
                }
                is Float -> {
                    editor.putFloat(key, value)
                    true
                }
                is Int -> {
                    editor.putInt(key, value)
                    true
                }
                is Long -> {
                    editor.putLong(key, value)
                    true
                }
                is String -> {
                    editor.putString(key, value)
                    true
                }
                is Set<*> -> {
                    val strings = value.filterIsInstance<String>()
                    if (strings.size != value.size) {
                        false
                    } else {
                        editor.putStringSet(key, strings.toSet())
                        true
                    }
                }
                else -> false
            }
        }

        fun deviceProtectedStorageContext(context: Context): Context {
            val applicationContext = context.applicationContext
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                if (applicationContext.isDeviceProtectedStorage) {
                    applicationContext
                } else {
                    applicationContext.createDeviceProtectedStorageContext()
                }
            } else {
                applicationContext
            }
        }
    }
}

data class AlarmInventorySnapshot(
    val requests: List<AlarmRequest>,
    val corruptKeys: List<String> = emptyList(),
    val duplicateIdentity: String? = null,
    private val context: Context,
) {
    fun status(request: AlarmRequest): String {
        if (request.state == AlarmState.RINGING) return AlarmState.RINGING.value
        return if (AlarmIntents.existingReceiver(context, request.platformAlarmId) == null) {
            "unknown"
        } else {
            AlarmState.SCHEDULED.value
        }
    }
}

object AlarmRestore {
    private val restoreLock = Any()

    fun restore(context: Context) {
        restore(context, context.applicationContext)
    }

    fun restore(storageContext: Context, serviceContext: Context) {
        val appContext = serviceContext.applicationContext
        val alarmManager = appContext.getSystemService(AlarmManager::class.java)
        restoreInternal(storageContext, appContext) { request ->
            alarmManager.setAlarmClock(
                AlarmManager.AlarmClockInfo(
                    request.scheduledAtMillis,
                    AlarmIntents.showIntent(appContext, request.platformAlarmId),
                ),
                AlarmIntents.receiver(appContext, request.platformAlarmId),
            )
        }
    }

    internal fun restoreForTest(
        storageContext: Context,
        serviceContext: Context,
        schedule: (AlarmRequest) -> Unit,
    ) {
        restoreInternal(storageContext, serviceContext.applicationContext, schedule)
    }

    private fun restoreInternal(
        storageContext: Context,
        appContext: Context,
        schedule: (AlarmRequest) -> Unit,
    ) {
        synchronized(restoreLock) {
            val alarmManager = appContext.getSystemService(AlarmManager::class.java)
            val store = AlarmStore(storageContext)
            val now = System.currentTimeMillis()
            val requests = store.all()
            requests.forEach { request ->
                if (request.state != AlarmState.RINGING && request.scheduledAtMillis <= now) {
                    store.remove(request.platformAlarmId)
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
                return
            }
            requests.asSequence()
                .filter { it.state != AlarmState.RINGING && it.scheduledAtMillis > now }
                .forEach { request ->
                    try {
                        schedule(request)
                    } catch (_: RuntimeException) {
                        // Keep future rows for a later boot or permission-state retry.
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

    fun existingReceiver(context: Context, platformAlarmId: String): PendingIntent? {
        val intent = Intent(context, AlarmReceiver::class.java)
            .setAction(ACTION_ALARM_FIRE)
            .setData(identityUri(platformAlarmId))
            .putExtra(EXTRA_PLATFORM_ALARM_ID, platformAlarmId)
        return PendingIntent.getBroadcast(
            context,
            requestCode(platformAlarmId),
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
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
