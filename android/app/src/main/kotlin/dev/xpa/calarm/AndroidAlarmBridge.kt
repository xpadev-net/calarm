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
import java.security.MessageDigest
import java.time.Instant
import org.json.JSONException
import org.json.JSONObject

class AndroidAlarmBridge(private val context: Context) : MethodChannel.MethodCallHandler {
    private val activity = context as? Activity
    private val appContext = context.applicationContext
    private val alarmManager = appContext.getSystemService(AlarmManager::class.java)
    private val notificationManager = appContext.getSystemService(NotificationManager::class.java)
    private val store = AlarmStore(appContext)
    private val eventStore = AlarmEventStore(appContext)
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
            "fetchAlarmEvents" -> fetchAlarmEvents(result)
            "acknowledgeAlarmEvents" -> acknowledgeAlarmEvents(arguments, result)
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
        val replacementRecovery = AndroidAlarmReplacementRecovery.reconcile(
            storageContext = appContext,
            serviceContext = appContext,
        )
        if (!replacementRecovery.isSuccess) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "nativeError",
                replacementRecovery.message ?: "Native alarm replacement recovery failed.",
                request.reservationId,
            )
        }
        val requestedPlatformAlarmId = request.platformAlarmId
        val legacyPlatformAlarmId = AlarmRequest.legacyPlatformAlarmId(request)
        val identitySnapshot = store.inspectIdentities(appContext, System.currentTimeMillis())
        if (identitySnapshot.corruptKeys.isNotEmpty() || identitySnapshot.duplicateIdentity != null) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "nativeError",
                identitySnapshot.duplicateIdentity
                    ?: "Native alarm mirror contains corrupt identity rows.",
                request.reservationId,
            )
        }
        val reservationOwner = identitySnapshot.requests.firstOrNull {
            it.reservationId == request.reservationId
        }
        val occurrenceOwner = identitySnapshot.requests.firstOrNull {
            it.occurrenceId == request.occurrenceId && it.reservationId != request.reservationId
        }
        val isAdoptableLegacyOwner = occurrenceOwner != null &&
            occurrenceOwner.platformAlarmId == legacyPlatformAlarmId &&
            occurrenceOwner.reservationId == occurrenceOwner.occurrenceId &&
            occurrenceOwner.wakePlanId == request.wakePlanId
        if (occurrenceOwner != null && !isAdoptableLegacyOwner) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "invalidRequest",
                "Native occurrence identity is already owned by another reservation.",
                request.reservationId,
            )
        }
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

        if (
            legacyRequest != null &&
            reservationOwner != null &&
            reservationOwner.platformAlarmId != legacyPlatformAlarmId
        ) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "invalidRequest",
                "Stable and legacy native alarm identities both exist for the occurrence.",
                request.reservationId,
            )
        }

        val platformAlarmId = when {
            legacyRequest != null -> legacyPlatformAlarmId
            reservationOwner != null -> reservationOwner.platformAlarmId
            else -> requestedPlatformAlarmId
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
            !sameStableReservation(existing, request)
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

        return if (existing != null && existing.occurrenceId != request.occurrenceId) {
            replaceStableReservation(existing, request)
        } else {
            armAndPersist(request, platformAlarmId)
        }
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

    private fun sameStableReservation(left: AlarmRequest, right: AlarmRequest): Boolean {
        return left.reservationId == right.reservationId &&
            left.wakePlanId == right.wakePlanId
    }

    private fun replaceStableReservation(
        existing: AlarmRequest,
        request: AlarmRequest,
    ): MutableMap<String, Any?> {
        val replacementPlatformAlarmId = AlarmRequest.replacementPlatformAlarmId(request)
        val replacement = request.copy(
            platformAlarmIdOverride = replacementPlatformAlarmId,
            state = AlarmState.SCHEDULED,
        )
        val journalStore = AlarmReplacementJournalStore(appContext)
        var journal = AlarmReplacementJournal(old = existing, new = replacement)
        if (!journalStore.save(journal)) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "nativeError",
                "Failed to persist native alarm replacement intent.",
                request.reservationId,
            )
        }
        try {
            alarmManager.setAlarmClock(
                AlarmManager.AlarmClockInfo(
                    replacement.scheduledAtMillis,
                    AlarmIntents.showIntent(appContext, replacementPlatformAlarmId),
                ),
                AlarmIntents.receiver(appContext, replacementPlatformAlarmId),
            )
            journal = journal.copy(phase = AlarmReplacementPhase.CANDIDATE_ARMED)
            if (!journalStore.save(journal)) {
                AndroidAlarmReplacementRecovery.reconcile(appContext, appContext)
                return scheduleFailure(
                    request.occurrenceId,
                    request.wakePlanId,
                    "nativeError",
                    "Failed to persist the armed replacement generation.",
                    request.reservationId,
                )
            }
        } catch (error: RuntimeException) {
            AndroidAlarmReplacementRecovery.reconcile(appContext, appContext)
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "nativeError",
                error.message ?: "AlarmManager rejected the replacement alarm.",
                request.reservationId,
            )
        }

        journal = journal.copy(phase = AlarmReplacementPhase.OLD_RETIRED)
        if (!journalStore.save(journal)) {
            AndroidAlarmReplacementRecovery.reconcile(appContext, appContext)
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "nativeError",
                "Failed to persist retirement of the prior generation.",
                request.reservationId,
            )
        }
        val recovery = AndroidAlarmReplacementRecovery.reconcile(appContext, appContext)
        val committed = store.get(replacementPlatformAlarmId)
        return if (
            recovery.isSuccess &&
            committed?.reservationId == request.reservationId &&
            committed.occurrenceId == request.occurrenceId &&
            committed.wakePlanId == request.wakePlanId
        ) {
            scheduleSuccess(request, replacementPlatformAlarmId)
        } else {
            scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "nativeError",
                recovery.message ?: "Native alarm replacement retained the prior occurrence.",
                request.reservationId,
            )
        }
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
        val replacementRecovery = AndroidAlarmReplacementRecovery.reconcile(
            storageContext = appContext,
            serviceContext = appContext,
        )
        if (!replacementRecovery.isSuccess) {
            return cancelFailure(
                occurrenceId,
                platformAlarmId,
                "nativeError",
                replacementRecovery.message ?: "Native alarm replacement recovery failed.",
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
        val replacementRecovery = AndroidAlarmReplacementRecovery.reconcile(
            storageContext = appContext,
            serviceContext = appContext,
        )
        if (!replacementRecovery.isSuccess) {
            return InventoryResponse(
                response = null,
                failureCode = "NATIVE_ERROR",
                failureMessage = replacementRecovery.message,
            )
        }
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

    private fun fetchAlarmEvents(result: MethodChannel.Result) {
        val snapshot = eventStore.fetch()
        if (snapshot.corruptKeys.isNotEmpty() || snapshot.unsupportedSchemaKeys.isNotEmpty()) {
            result.error(
                "CORRUPT",
                "Native alarm event rows are corrupt or use an unsupported storage schema.",
                null,
            )
            return
        }
        result.success(
            mutableResponse(
                "events" to snapshot.events.map { event ->
                    mutableMapOf(
                        "eventId" to event.eventId,
                        "platformAlarmId" to event.platformAlarmId,
                        "type" to event.type.value,
                        "timestampMillis" to event.timestampMillis,
                    )
                },
            ),
        )
    }

    private fun acknowledgeAlarmEvents(
        arguments: Map<*, *>,
        result: MethodChannel.Result,
    ) {
        val eventIds = validatedEventIds(arguments["eventIds"])
        if (eventIds == null) {
            result.error(
                "INVALID_REQUEST",
                "eventIds must be a list of unique non-empty strings.",
                null,
            )
            return
        }
        if (!eventStore.acknowledge(eventIds)) {
            result.error("NATIVE_ERROR", "Failed to acknowledge native alarm events.", null)
            return
        }
        result.success(mutableResponse("status" to "success"))
    }

    private fun validatedEventIds(value: Any?): List<String>? {
        val values = value as? List<*> ?: return null
        val eventIds = values.map { it as? String ?: return null }
        return eventIds.takeIf { ids ->
            ids.all { it.isNotBlank() } && ids.toSet().size == ids.size
        }
    }

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
                platformAlarmId == replacementPlatformAlarmId(this) ||
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

        fun replacementPlatformAlarmId(request: AlarmRequest): String {
            val digest = MessageDigest.getInstance("SHA-256")
                .digest("${request.reservationId}\u0000${request.occurrenceId}".toByteArray())
                .joinToString("") { byte -> "%02x".format(byte) }
            return "android:replacement:$digest"
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

internal fun AlarmRequest.positionLabel(): String? {
    val index = indexInPlan ?: return null
    val total = totalInPlan ?: return null
    return "Alarm ${index + 1} of $total"
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

enum class AlarmEventType(val value: String) {
    DELIVERED("delivered"),
    DISMISSED("dismissed");

    companion object {
        fun fromValue(value: String): AlarmEventType {
            return entries.firstOrNull { it.value == value }
                ?: throw IllegalArgumentException("Unknown native alarm event type: $value")
        }
    }
}

data class AlarmEvent(
    val eventId: String,
    val platformAlarmId: String,
    val type: AlarmEventType,
    val timestampMillis: Long,
) {
    fun toJson(): JSONObject {
        return JSONObject()
            .put("schemaVersion", STORAGE_SCHEMA_VERSION)
            .put("eventId", eventId)
            .put("platformAlarmId", platformAlarmId)
            .put("type", type.value)
            .put("timestampMillis", timestampMillis)
    }

    companion object {
        internal const val STORAGE_SCHEMA_VERSION = 1

        fun fromJson(json: JSONObject): AlarmEvent {
            require(json.getInt("schemaVersion") == STORAGE_SCHEMA_VERSION) {
                "Unsupported native alarm event storage schema."
            }
            val eventId = json.getString("eventId").takeIf { it.isNotBlank() }
                ?: throw IllegalArgumentException("eventId must not be blank")
            val platformAlarmId = json.getString("platformAlarmId").takeIf { it.isNotBlank() }
                ?: throw IllegalArgumentException("platformAlarmId must not be blank")
            val type = AlarmEventType.fromValue(json.getString("type"))
            val timestampMillis = json.getLong("timestampMillis")
            require(timestampMillis >= 0L) { "timestampMillis must not be negative" }
            require(eventId == idFor(platformAlarmId, type)) {
                "eventId does not match the event identity"
            }
            return AlarmEvent(eventId, platformAlarmId, type, timestampMillis)
        }

        fun idFor(platformAlarmId: String, type: AlarmEventType): String {
            return "$platformAlarmId:${type.value}"
        }
    }
}

data class AlarmEventSnapshot(
    val events: List<AlarmEvent>,
    val corruptKeys: List<String> = emptyList(),
    val unsupportedSchemaKeys: List<String> = emptyList(),
)

/**
 * Device-protected journal for the native delivery/dismissal events that Dart
 * has not yet acknowledged after durably applying their effects.
 */
class AlarmEventStore(context: Context) {
    private val preferences: SharedPreferences = deviceProtectedStorageContext(context)
        .getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    fun appendDelivered(platformAlarmId: String, timestampMillis: Long): Boolean {
        return append(platformAlarmId, AlarmEventType.DELIVERED, timestampMillis)
    }

    fun appendDismissed(platformAlarmId: String, timestampMillis: Long): Boolean {
        return append(platformAlarmId, AlarmEventType.DISMISSED, timestampMillis)
    }

    fun fetch(): AlarmEventSnapshot = synchronized(lock) {
        val parsed = readRows()
        if (parsed.corruptKeys.isNotEmpty()) {
            val editor = preferences.edit()
            parsed.corruptKeys.forEach(editor::remove)
            if (!editor.commit()) {
                return@synchronized AlarmEventSnapshot(
                    events = emptyList(),
                    corruptKeys = parsed.corruptKeys,
                    unsupportedSchemaKeys = parsed.unsupportedSchemaKeys,
                )
            }
        }
        AlarmEventSnapshot(
            events = parsed.events.sortedWith(EVENT_ORDER),
            corruptKeys = parsed.corruptKeys,
            unsupportedSchemaKeys = parsed.unsupportedSchemaKeys,
        )
    }

    fun acknowledge(eventIds: Collection<String>): Boolean = synchronized(lock) {
        if (
            eventIds.any { it.isBlank() } ||
            eventIds.toSet().size != eventIds.size
        ) return@synchronized false
        if (eventIds.isEmpty()) return@synchronized true
        val supportedEventIds = readRows().events.mapTo(mutableSetOf(), AlarmEvent::eventId)
        val removableEventIds = eventIds.filter(supportedEventIds::contains)
        if (removableEventIds.isEmpty()) return@synchronized true
        val editor = preferences.edit()
        removableEventIds.forEach(editor::remove)
        editor.commit()
    }

    private fun append(
        platformAlarmId: String,
        type: AlarmEventType,
        timestampMillis: Long,
    ): Boolean = synchronized(lock) {
        if (platformAlarmId.isBlank() || timestampMillis < 0L) return@synchronized false

        val eventId = AlarmEvent.idFor(platformAlarmId, type)
        val event = AlarmEvent(eventId, platformAlarmId, type, timestampMillis)
        val parsed = readRows()
        val existing = parsed.events
            .filterNot { it.eventId == eventId }
            .sortedWith(EVENT_ORDER)
        val overflow = (existing.size + 1 - MAX_EVENTS).coerceAtLeast(0)
        val editor = preferences.edit()
        parsed.corruptKeys.forEach(editor::remove)
        existing.take(overflow).forEach { editor.remove(it.eventId) }
        if (eventId in parsed.unsupportedSchemaKeys) {
            val unsupportedPayload = preferences.getString(eventId, null)
                ?: return@synchronized false
            editor.putString(
                nextUnsupportedArchiveKey(eventId),
                JSONObject()
                    .put("archiveSchemaVersion", UNSUPPORTED_ARCHIVE_SCHEMA_VERSION)
                    .put("eventId", eventId)
                    .put("payload", unsupportedPayload)
                    .toString(),
            )
        }
        editor.putString(eventId, event.toJson().toString())
        editor.commit()
    }

    private fun readRows(): AlarmEventSnapshot {
        val events = mutableListOf<AlarmEvent>()
        val corruptKeys = mutableListOf<String>()
        val unsupportedSchemaKeys = mutableListOf<String>()
        preferences.all.forEach { (key, value) ->
            if (isUnsupportedArchive(key, value)) return@forEach
            val json = try {
                (value as? String)?.let(::JSONObject)
            } catch (_: Exception) {
                null
            }
            if (json == null) {
                corruptKeys += key
                return@forEach
            }
            val schemaVersion = try {
                json.getInt("schemaVersion")
            } catch (_: Exception) {
                null
            }
            if (schemaVersion == null) {
                corruptKeys += key
                return@forEach
            }
            if (schemaVersion != AlarmEvent.STORAGE_SCHEMA_VERSION) {
                unsupportedSchemaKeys += key
                return@forEach
            }
            val event = try {
                AlarmEvent.fromJson(json)
            } catch (_: Exception) {
                null
            }
            if (event == null || event.eventId != key) {
                corruptKeys += key
            } else {
                events += event
            }
        }
        return AlarmEventSnapshot(
            events = events,
            corruptKeys = corruptKeys.sorted(),
            unsupportedSchemaKeys = unsupportedSchemaKeys.sorted(),
        )
    }

    private fun nextUnsupportedArchiveKey(eventId: String): String {
        var sequence = 0
        var key: String
        do {
            key = "$UNSUPPORTED_ARCHIVE_PREFIX$sequence:$eventId"
            sequence += 1
        } while (preferences.contains(key))
        return key
    }

    private fun isUnsupportedArchive(key: String, value: Any?): Boolean {
        if (!key.startsWith(UNSUPPORTED_ARCHIVE_PREFIX)) return false
        return try {
            val archive = JSONObject(value as? String ?: return false)
            if (archive.getInt("archiveSchemaVersion") != UNSUPPORTED_ARCHIVE_SCHEMA_VERSION) {
                return false
            }
            val eventId = archive.getString("eventId")
            val payload = JSONObject(archive.getString("payload"))
            eventId.isNotBlank() &&
                key.endsWith(":$eventId") &&
                payload.getInt("schemaVersion") != AlarmEvent.STORAGE_SCHEMA_VERSION
        } catch (_: Exception) {
            false
        }
    }

    private companion object {
        const val PREFERENCES_NAME = "native_alarm_events"
        const val MAX_EVENTS = 200
        const val UNSUPPORTED_ARCHIVE_PREFIX = "__calarm_unsupported_event__:"
        const val UNSUPPORTED_ARCHIVE_SCHEMA_VERSION = 1
        val lock = Any()
        val EVENT_ORDER = compareBy<AlarmEvent> { it.timestampMillis }.thenBy { it.eventId }

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

    fun replace(
        oldPlatformAlarmId: String,
        newPlatformAlarmId: String,
        winner: AlarmRequest,
    ): Boolean {
        val persistedWinner = winner.copy(updatedAtMillis = System.currentTimeMillis())
        return preferences.edit()
            .remove(oldPlatformAlarmId)
            .remove(newPlatformAlarmId)
            .putString(
                persistedWinner.platformAlarmId,
                persistedWinner.toJson().toString(),
            )
            .commit()
    }

    fun removeAll(platformAlarmIds: Set<String>): Boolean {
        val editor = preferences.edit()
        platformAlarmIds.forEach { platformAlarmId -> editor.remove(platformAlarmId) }
        return editor.commit()
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

    fun inspectIdentities(context: Context, nowMillis: Long): AlarmInventorySnapshot {
        val corruptKeys = mutableListOf<String>()
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
            } else if (
                request.state == AlarmState.RINGING ||
                request.scheduledAtMillis > nowMillis
            ) {
                requests += request
            }
        }
        val duplicateReservation = requests.groupBy { it.reservationId }
            .values.firstOrNull { it.size > 1 }
        val duplicateOccurrence = requests.groupBy { it.occurrenceId }
            .values.firstOrNull { it.size > 1 }
        return AlarmInventorySnapshot(
            requests = if (duplicateReservation == null && duplicateOccurrence == null) {
                requests
            } else {
                emptyList()
            },
            corruptKeys = corruptKeys,
            duplicateIdentity = when {
                duplicateReservation != null ->
                    "Duplicate native reservation identity: ${duplicateReservation.first().reservationId}."
                duplicateOccurrence != null ->
                    "Duplicate native occurrence identity: ${duplicateOccurrence.first().occurrenceId}."
                else -> null
            },
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

internal enum class AlarmReplacementPhase {
    STAGING,
    CANDIDATE_ARMED,
    OLD_RETIRED,
}

internal data class AlarmReplacementJournal(
    val old: AlarmRequest,
    val new: AlarmRequest,
    val phase: AlarmReplacementPhase = AlarmReplacementPhase.STAGING,
) {
    init {
        require(old.reservationId == new.reservationId)
        require(old.wakePlanId == new.wakePlanId)
        require(old.occurrenceId != new.occurrenceId)
        require(old.platformAlarmId != new.platformAlarmId)
        require(old.hasCanonicalPlatformAlarmId())
        require(new.platformAlarmId == AlarmRequest.replacementPlatformAlarmId(new))
    }

    fun toJson(): JSONObject {
        return JSONObject()
            .put("schemaVersion", 1)
            .put("old", old.toJson())
            .put("new", new.toJson())
            .put("phase", phase.name)
    }

    companion object {
        fun fromJson(json: JSONObject): AlarmReplacementJournal {
            require(json.getInt("schemaVersion") == 1)
            return AlarmReplacementJournal(
                old = AlarmRequest.fromJson(json.getJSONObject("old")),
                new = AlarmRequest.fromJson(json.getJSONObject("new")),
                phase = AlarmReplacementPhase.valueOf(json.getString("phase")),
            )
        }
    }
}

internal class AlarmReplacementJournalStore(context: Context) {
    private val preferences = (if (
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && !context.isDeviceProtectedStorage
    ) {
        context.createDeviceProtectedStorageContext()
    } else {
        context
    })
        .getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    fun load(): AlarmReplacementJournal? {
        val value = preferences.getString(JOURNAL_KEY, null) ?: return null
        return AlarmReplacementJournal.fromJson(JSONObject(value))
    }

    fun save(journal: AlarmReplacementJournal): Boolean {
        return preferences.edit()
            .putString(JOURNAL_KEY, journal.toJson().toString())
            .commit()
    }

    fun clear(): Boolean = preferences.edit().remove(JOURNAL_KEY).commit()

    private companion object {
        const val PREFERENCES_NAME = "native_alarm_replacement_journal"
        const val JOURNAL_KEY = "active"
    }
}

internal data class AlarmReplacementRecoveryResult(
    val isSuccess: Boolean,
    val message: String? = null,
)

internal object AndroidAlarmReplacementRecovery {
    private val lock = Any()

    fun reconcile(
        storageContext: Context,
        serviceContext: Context,
    ): AlarmReplacementRecoveryResult = synchronized(lock) {
        val appContext = serviceContext.applicationContext
        val journalStore = AlarmReplacementJournalStore(storageContext)
        val journal = try {
            journalStore.load()
        } catch (error: Exception) {
            return@synchronized AlarmReplacementRecoveryResult(
                isSuccess = false,
                message = error.message ?: "Native alarm replacement journal is corrupt.",
            )
        } ?: return@synchronized AlarmReplacementRecoveryResult(isSuccess = true)

        val alarmManager = appContext.getSystemService(AlarmManager::class.java)
        val store = AlarmStore(storageContext)
        val now = System.currentTimeMillis()
        val winner = when {
            journal.phase == AlarmReplacementPhase.OLD_RETIRED -> journal.new
            journal.old.scheduledAtMillis > now -> journal.old
            journal.new.scheduledAtMillis > now -> journal.new
            else -> null
        }
        if (winner == null) {
            val expiredPlatformAlarmIds = setOf(
                journal.old.platformAlarmId,
                journal.new.platformAlarmId,
            )
            if (!store.removeAll(expiredPlatformAlarmIds)) {
                return@synchronized AlarmReplacementRecoveryResult(
                    isSuccess = false,
                    message = "Failed to retire expired native alarm replacement rows.",
                )
            }
            try {
                cancel(appContext, alarmManager, journal.old.platformAlarmId)
                cancel(appContext, alarmManager, journal.new.platformAlarmId)
            } catch (error: RuntimeException) {
                return@synchronized AlarmReplacementRecoveryResult(
                    isSuccess = false,
                    message = error.message ?: "Failed to retire expired native alarms.",
                )
            }
            if (!journalStore.clear()) {
                return@synchronized AlarmReplacementRecoveryResult(
                    isSuccess = false,
                    message = "Failed to clear expired native alarm replacement journal.",
                )
            }
            return@synchronized AlarmReplacementRecoveryResult(isSuccess = true)
        }
        val loser = if (winner == journal.new) journal.old else journal.new

        if (!store.replace(
                journal.old.platformAlarmId,
                journal.new.platformAlarmId,
                winner,
            )
        ) {
            return@synchronized AlarmReplacementRecoveryResult(
                isSuccess = false,
                message = "Failed to persist native alarm replacement winner.",
            )
        }
        try {
            arm(appContext, alarmManager, winner)
            cancel(appContext, alarmManager, loser.platformAlarmId)
        } catch (error: RuntimeException) {
            return@synchronized AlarmReplacementRecoveryResult(
                isSuccess = false,
                message = error.message ?: "Native alarm replacement recovery failed.",
            )
        }
        if (!journalStore.clear()) {
            return@synchronized AlarmReplacementRecoveryResult(
                isSuccess = false,
                message = "Failed to clear native alarm replacement journal.",
            )
        }
        AlarmReplacementRecoveryResult(isSuccess = true)
    }

    private fun arm(
        context: Context,
        alarmManager: AlarmManager,
        request: AlarmRequest,
    ) {
        alarmManager.setAlarmClock(
            AlarmManager.AlarmClockInfo(
                request.scheduledAtMillis,
                AlarmIntents.showIntent(context, request.platformAlarmId),
            ),
            AlarmIntents.receiver(context, request.platformAlarmId),
        )
    }

    private fun cancel(
        context: Context,
        alarmManager: AlarmManager,
        platformAlarmId: String,
    ) {
        val receiver = AlarmIntents.receiver(context, platformAlarmId)
        alarmManager.cancel(receiver)
        receiver.cancel()
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
            val replacementRecovery = AndroidAlarmReplacementRecovery.reconcile(
                storageContext,
                appContext,
            )
            if (!replacementRecovery.isSuccess) {
                return
            }
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
