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
    private val authorityStore = ReservationAuthorityStore(appContext)
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
                val invalidReservationGeneration = when (
                    val value = map?.get("reservationGeneration")
                ) {
                    is Byte -> value.toLong()
                    is Short -> value.toLong()
                    is Int -> value.toLong()
                    is Long -> value
                    else -> 0L
                }.coerceAtLeast(0L)
                scheduleFailure(
                    map?.get("occurrenceId") as? String ?: "",
                    map?.get("wakePlanId") as? String ?: "",
                    "invalidRequest",
                    "Invalid schedule occurrence.",
                    invalidReservationId,
                    invalidReservationGeneration,
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
                request.reservationGeneration,
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
                request.reservationGeneration,
            )
        }
        val adoptableLegacyIdentity = identitySnapshot.requests.firstOrNull {
            it.occurrenceId == request.occurrenceId &&
                it.platformAlarmId == legacyPlatformAlarmId &&
                it.reservationId == it.occurrenceId &&
                it.wakePlanId == request.wakePlanId
        }
        val authorityFailure = authorityStore.validateAndSeedActive(
            identitySnapshot.requests.filterNot { it == adoptableLegacyIdentity },
        ) ?: authorityStore.admissionFailure(request)
        if (authorityFailure != null) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "invalidRequest",
                authorityFailure,
                request.reservationId,
                request.reservationGeneration,
            )
        }
        val reservationOwner = identitySnapshot.requests.firstOrNull {
            it.reservationId == request.reservationId
        }
        val persistedAuthority = try {
            authorityStore.load().reservations[request.reservationId]
        } catch (_: Exception) {
            null
        }
        if (
            reservationOwner == null &&
            persistedAuthority?.state == ReservationAuthorityState.ACTIVE
        ) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "invalidRequest",
                "Native reservation generation has no authoritative mirror row.",
                request.reservationId,
                request.reservationGeneration,
            )
        }
        val occurrenceOwner = identitySnapshot.requests.firstOrNull {
            it.occurrenceId == request.occurrenceId && it.reservationId != request.reservationId
        }
        val isAdoptableLegacyOwner = occurrenceOwner != null &&
            occurrenceOwner == adoptableLegacyIdentity
        if (occurrenceOwner != null && !isAdoptableLegacyOwner) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "invalidRequest",
                "Native occurrence identity is already owned by another reservation.",
                request.reservationId,
                request.reservationGeneration,
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
                request.reservationGeneration,
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
                request.reservationGeneration,
            )
        }
        if (legacyRequest != null && !legacyRequest.hasCanonicalPlatformAlarmId()) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "nativeError",
                "Legacy native alarm mirror row is corrupt.",
                request.reservationId,
                request.reservationGeneration,
            )
        }
        if (legacyRequest != null && !legacyIdentityMatches) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "invalidRequest",
                "Legacy native alarm identity conflicts with the requested reservation.",
                request.reservationId,
                request.reservationGeneration,
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
                request.reservationGeneration,
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
                request.reservationGeneration,
            )
        }
        if (existing != null && !existing.hasCanonicalPlatformAlarmId()) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "nativeError",
                "Native alarm mirror row is corrupt.",
                request.reservationId,
                request.reservationGeneration,
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
                request.reservationGeneration,
            )
        }
        if (existing?.state == AlarmState.RINGING) {
            val comparableExisting = if (
                legacyRequest != null && legacyIdentityMatches
            ) {
                existing.copy(reservationId = request.reservationId)
            } else {
                existing
            }
            if (
                !sameSchedulePayload(comparableExisting, request)
            ) {
                return scheduleFailure(
                    request.occurrenceId,
                    request.wakePlanId,
                    "invalidRequest",
                    "Cannot replace an actively ringing native alarm.",
                    request.reservationId,
                    request.reservationGeneration,
                )
            }
            if (legacyRequest != null && existing.reservationId != request.reservationId) {
                val adoptedRingingRequest = existing.copy(
                    reservationId = request.reservationId,
                    platformAlarmIdOverride = platformAlarmId,
                )
                if (
                    !store.put(adoptedRingingRequest) ||
                    !authorityStore.recordActive(adoptedRingingRequest)
                ) {
                    return scheduleFailure(
                        request.occurrenceId,
                        request.wakePlanId,
                        "nativeError",
                        "Failed to persist native alarm mirror state.",
                        request.reservationId,
                        request.reservationGeneration,
                    )
                }
            }
            return scheduleSuccess(request, platformAlarmId)
        }
        if (existing != null && existing.reservationGeneration == request.reservationGeneration) {
            if (legacyRequest != null && legacyIdentityMatches) {
                val adopted = request.copy(
                    platformAlarmIdOverride = platformAlarmId,
                    state = existing.state,
                )
                if (!store.put(adopted) || !authorityStore.recordActive(adopted)) {
                    return scheduleFailure(
                        request.occurrenceId,
                        request.wakePlanId,
                        "nativeError",
                        "Failed to persist adopted native reservation generation.",
                        request.reservationId,
                        request.reservationGeneration,
                    )
                }
                return scheduleSuccess(request, platformAlarmId)
            }
            if (!sameSchedulePayload(existing, request)) {
                return scheduleFailure(
                    request.occurrenceId,
                    request.wakePlanId,
                    "invalidRequest",
                    "Native reservation generation does not match its persisted payload.",
                    request.reservationId,
                    request.reservationGeneration,
                )
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
                request.reservationGeneration,
            )
        }
        if (!notificationsAllowed()) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "permissionMissing",
                "Notification permission is not granted.",
                request.reservationId,
                request.reservationGeneration,
            )
        }
        if (!canUseFullScreenIntent()) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "permissionMissing",
                "Full-screen intent permission is not granted.",
                request.reservationId,
                request.reservationGeneration,
            )
        }
        if (!notificationChannelReady()) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "osConstraint",
                "Wake alarm notification channel is disabled.",
                request.reservationId,
                request.reservationGeneration,
            )
        }
        if (request.scheduledAtMillis <= System.currentTimeMillis()) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "invalidRequest",
                "scheduledAt must be in the future.",
                request.reservationId,
                request.reservationGeneration,
            )
        }

        return if (existing != null) {
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
                    request.reservationGeneration,
                )
            }
            val persisted = request.copy(
                platformAlarmIdOverride = platformAlarmId,
                state = AlarmState.SCHEDULED,
            )
            if (!authorityStore.recordActive(persisted)) {
                return scheduleFailure(
                    request.occurrenceId,
                    request.wakePlanId,
                    "nativeError",
                    "Failed to persist native reservation generation authority.",
                    request.reservationId,
                    request.reservationGeneration,
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
                request.reservationGeneration,
            )
        } catch (error: RuntimeException) {
            cancel()
            scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "nativeError",
                error.message ?: "AlarmManager rejected the alarm.",
                request.reservationId,
                request.reservationGeneration,
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
            "reservationGeneration" to request.reservationGeneration,
            "wakePlanId" to request.wakePlanId,
            "status" to "success",
            "platformAlarmId" to platformAlarmId,
        )
    }

    private fun sameStableReservation(left: AlarmRequest, right: AlarmRequest): Boolean {
        return left.reservationId == right.reservationId &&
            left.wakePlanId == right.wakePlanId
    }

    private fun sameSchedulePayload(left: AlarmRequest, right: AlarmRequest): Boolean {
        return left.reservationId == right.reservationId &&
            left.reservationGeneration == right.reservationGeneration &&
            left.occurrenceId == right.occurrenceId &&
            left.wakePlanId == right.wakePlanId &&
            left.scheduledAtMillis == right.scheduledAtMillis &&
            left.targetAtMillis == right.targetAtMillis &&
            left.soundId == right.soundId &&
            left.vibrationEnabled == right.vibrationEnabled &&
            left.indexInPlan == right.indexInPlan &&
            left.totalInPlan == right.totalInPlan
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
                request.reservationGeneration,
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
                    request.reservationGeneration,
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
                request.reservationGeneration,
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
                request.reservationGeneration,
            )
        }
        val recovery = AndroidAlarmReplacementRecovery.reconcile(appContext, appContext)
        val committed = store.get(replacementPlatformAlarmId)
        return if (
            recovery.isSuccess &&
            committed?.reservationId == request.reservationId &&
            committed.reservationGeneration == request.reservationGeneration &&
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
                request.reservationGeneration,
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
            val reservationGeneration = when (val value = map?.get("reservationGeneration")) {
                null -> 0L
                is Byte -> value.toLong()
                is Short -> value.toLong()
                is Int -> value.toLong()
                is Long -> value
                else -> -1L
            }
            val platformAlarmId = map?.get("platformAlarmId") as? String ?: ""
            cancelOne(occurrenceId, reservationId, reservationGeneration, platformAlarmId)
        }
        return mutableResponse("alarms" to results)
    }

    private fun cancelOne(
        occurrenceId: String,
        reservationId: String,
        reservationGeneration: Long,
        platformAlarmId: String,
    ): MutableMap<String, Any?> {
        if (
            occurrenceId.isBlank() ||
            reservationId.isBlank() ||
            reservationGeneration < 0L ||
            platformAlarmId.isBlank()
        ) {
            return cancelFailure(
                occurrenceId,
                platformAlarmId,
                if (platformAlarmId.isBlank()) "missingPlatformAlarmId" else "invalidRequest",
                if (platformAlarmId.isBlank()) "Missing platformAlarmId." else "Invalid cancel identity.",
                reservationId,
                reservationGeneration.coerceAtLeast(0L),
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
                reservationGeneration,
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
                    reservationGeneration,
                )
                stored != null &&
                    (stored.platformAlarmId != platformAlarmId ||
                        !stored.hasCanonicalPlatformAlarmId()) -> cancelFailure(
                    occurrenceId,
                    platformAlarmId,
                    "nativeError",
                    "Native alarm mirror row is corrupt.",
                    reservationId,
                    reservationGeneration,
                )
                stored != null &&
                    !cancelIdentityMatches(
                        stored,
                        occurrenceId,
                        reservationId,
                        reservationGeneration,
                    ) ->
                    cancelFailure(
                        occurrenceId,
                        platformAlarmId,
                        "invalidRequest",
                        "Native alarm identity does not match the requested reservation.",
                        reservationId,
                        reservationGeneration,
                    )
                else -> {
                    if (stored != null && !authorityStore.recordRetired(listOf(stored))) {
                        return cancelFailure(
                            occurrenceId,
                            platformAlarmId,
                            "nativeError",
                            "Failed to persist native alarm generation retirement.",
                            reservationId,
                            reservationGeneration,
                        )
                    }
                    alarmManager.cancel(AlarmIntents.receiver(appContext, platformAlarmId))
                    if (!store.remove(platformAlarmId)) {
                        cancelFailure(
                            occurrenceId,
                            platformAlarmId,
                            "nativeError",
                            "Failed to persist native alarm mirror removal.",
                            reservationId,
                            reservationGeneration,
                        )
                    } else {
                        notificationManager.cancel(platformAlarmId.hashCode())
                        mutableMapOf(
                            "occurrenceId" to occurrenceId,
                            "reservationId" to reservationId,
                            "reservationGeneration" to reservationGeneration,
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
                reservationGeneration,
            )
        }
    }

    private fun cancelIdentityMatches(
        stored: AlarmRequest,
        occurrenceId: String,
        reservationId: String,
        reservationGeneration: Long,
    ): Boolean {
        if (isSyntheticTestAlarm(stored)) return true
        if (stored.occurrenceId != occurrenceId) return false
        if (stored.reservationGeneration != reservationGeneration) return false
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
        reservationGeneration: Long = 0L,
    ): MutableMap<String, Any?> {
        return mutableMapOf(
            "occurrenceId" to occurrenceId,
            "reservationId" to reservationId,
            "reservationGeneration" to reservationGeneration,
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
        reservationGeneration: Long = 0L,
    ): MutableMap<String, Any?> {
        return mutableMapOf(
            "occurrenceId" to occurrenceId,
            "reservationId" to reservationId,
            "reservationGeneration" to reservationGeneration,
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
        val authorityFailure = authorityStore.validateAndSeedActive(snapshot.requests)
        if (authorityFailure != null) {
            return InventoryResponse(
                response = null,
                failureCode = "CORRUPT",
                failureMessage = authorityFailure,
            )
        }
        return InventoryResponse(
            response = mutableResponse(
                "reservations" to snapshot.requests.map { request ->
                    mutableMapOf(
                        "reservationId" to request.reservationId,
                        "reservationGeneration" to request.reservationGeneration,
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
    val reservationGeneration: Long = 0L,
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
        require(reservationGeneration >= 0L) { "reservationGeneration must not be negative." }
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
                (reservationGeneration == 0L &&
                    platformAlarmId == legacyReplacementPlatformAlarmId(this)) ||
                (isTest && platformAlarmId == "android:test:$occurrenceId"))
    }

    fun toJson(): JSONObject {
        val json = JSONObject()
            .put("occurrenceId", occurrenceId)
            .put("reservationId", reservationId)
            .put("reservationGeneration", reservationGeneration)
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
            if (request.reservationGeneration == 0L) {
                return legacyReplacementPlatformAlarmId(request)
            }
            val digest = MessageDigest.getInstance("SHA-256")
                .digest(
                    "${request.reservationId}\u0000${request.reservationGeneration}\u0000${request.occurrenceId}"
                        .toByteArray(),
                )
                .joinToString("") { byte -> "%02x".format(byte) }
            return "android:replacement:$digest"
        }

        fun legacyReplacementPlatformAlarmId(request: AlarmRequest): String {
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
            val reservationGeneration = exactNonNegativeLong(
                map["reservationGeneration"] ?: 0L,
            ) ?: return null
            return try {
                val (indexInPlan, totalInPlan) = parsePosition(
                    map["indexInPlan"],
                    map["totalInPlan"],
                )
                AlarmRequest(
                    occurrenceId = occurrenceId,
                    reservationId = reservationId,
                    reservationGeneration = reservationGeneration,
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
            val reservationGeneration = if (json.has("reservationGeneration")) {
                exactNonNegativeLong(json.opt("reservationGeneration"))
                    ?: throw IllegalArgumentException(
                        "reservationGeneration must be a non-negative integer",
                    )
            } else {
                0L
            }
            val (indexInPlan, totalInPlan) = parsePosition(
                json.opt("indexInPlan"),
                json.opt("totalInPlan"),
            )
            return AlarmRequest(
                occurrenceId = occurrenceId,
                reservationId = reservationId,
                reservationGeneration = reservationGeneration,
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

        private fun exactNonNegativeLong(value: Any?): Long? {
            val result = when (value) {
                is Byte -> value.toLong()
                is Short -> value.toLong()
                is Int -> value.toLong()
                is Long -> value
                else -> return null
            }
            return result.takeIf { it >= 0L }
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
        val request = get(platformAlarmId)
        if (request != null && !ReservationAuthorityStore(storageContext).recordRetired(listOf(request))) {
            return false
        }
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
        val expiredRequests = mutableListOf<AlarmRequest>()
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
                expiredRequests += request
            } else {
                requests += request
            }
        }
        val cleanupKeys = corruptKeys + expiredKeys
        if (cleanupKeys.isNotEmpty()) {
            if (
                expiredRequests.isNotEmpty() &&
                !ReservationAuthorityStore(storageContext).recordRetired(expiredRequests)
            ) {
                return AlarmInventorySnapshot(
                    requests = emptyList(),
                    corruptKeys = cleanupKeys,
                    duplicateIdentity = "Failed to persist expired native alarm generation retirement.",
                    context = context,
                )
            }
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
            } else {
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
        val requests = requestsById.values.toList()
        return if (
            ReservationAuthorityStore(storageContext).validateAndSeedActive(requests) == null
        ) {
            requests
        } else {
            emptyList()
        }
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

internal enum class ReservationAuthorityState {
    ACTIVE,
    RETIRED,
}

internal data class ReservationAuthority(
    val reservationId: String,
    val wakePlanId: String,
    val reservationGeneration: Long,
    val occurrenceId: String,
    val state: ReservationAuthorityState,
) {
    init {
        require(reservationId.isNotBlank())
        require(wakePlanId.isNotBlank())
        require(reservationGeneration >= 0L)
        require(occurrenceId.isNotBlank())
    }

    fun toJson(): JSONObject = JSONObject()
        .put("reservationId", reservationId)
        .put("wakePlanId", wakePlanId)
        .put("reservationGeneration", reservationGeneration)
        .put("occurrenceId", occurrenceId)
        .put("state", state.name)

    companion object {
        fun fromJson(json: JSONObject): ReservationAuthority {
            val generation = json.opt("reservationGeneration")
            require(generation is Long || generation is Int)
            val exactGeneration = (generation as Number).toLong()
            require(exactGeneration >= 0L)
            return ReservationAuthority(
                reservationId = json.getString("reservationId"),
                wakePlanId = json.getString("wakePlanId"),
                reservationGeneration = exactGeneration,
                occurrenceId = json.getString("occurrenceId"),
                state = ReservationAuthorityState.valueOf(json.getString("state")),
            )
        }
    }
}

internal data class ReservationAuthoritySnapshot(
    val reservations: Map<String, ReservationAuthority> = emptyMap(),
    val occurrenceOwners: Map<String, Pair<String, String>> = emptyMap(),
)

internal class ReservationAuthorityStore(context: Context) {
    private val preferences = (if (
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && !context.isDeviceProtectedStorage
    ) {
        context.createDeviceProtectedStorageContext()
    } else {
        context
    }).getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    fun load(): ReservationAuthoritySnapshot = synchronized(lock) {
        loadUnlocked()
    }

    fun validateAndSeedActive(requests: Collection<AlarmRequest>): String? = synchronized(lock) {
        val snapshot = try {
            loadUnlocked()
        } catch (_: Exception) {
            return@synchronized "Native reservation generation authority is corrupt."
        }
        val reservations = snapshot.reservations.toMutableMap()
        val occurrenceOwners = snapshot.occurrenceOwners.toMutableMap()
        var changed = false
        for (request in requests) {
            val occurrenceOwner = occurrenceOwners[request.occurrenceId]
            if (
                occurrenceOwner != null &&
                occurrenceOwner != (request.reservationId to request.wakePlanId)
            ) {
                return@synchronized "Native occurrence generation ownership conflicts."
            }
            val authority = reservations[request.reservationId]
            if (authority == null) {
                reservations[request.reservationId] = request.activeAuthority()
                occurrenceOwners[request.occurrenceId] =
                    request.reservationId to request.wakePlanId
                changed = true
                continue
            }
            if (
                authority.wakePlanId != request.wakePlanId ||
                request.reservationGeneration != authority.reservationGeneration ||
                authority.occurrenceId != request.occurrenceId ||
                authority.state != ReservationAuthorityState.ACTIVE
            ) {
                return@synchronized "Native reservation generation authority does not match its mirror."
            }
            if (occurrenceOwner == null) {
                occurrenceOwners[request.occurrenceId] =
                    request.reservationId to request.wakePlanId
                changed = true
            }
        }
        if (
            changed &&
            !saveUnlocked(ReservationAuthoritySnapshot(reservations, occurrenceOwners))
        ) {
            return@synchronized "Failed to persist native reservation generation authority."
        }
        null
    }

    fun admissionFailure(request: AlarmRequest): String? = synchronized(lock) {
        val snapshot = try {
            loadUnlocked()
        } catch (_: Exception) {
            return@synchronized "Native reservation generation authority is corrupt."
        }
        val occurrenceOwner = snapshot.occurrenceOwners[request.occurrenceId]
        if (
            occurrenceOwner != null &&
            occurrenceOwner != (request.reservationId to request.wakePlanId)
        ) {
            return@synchronized "Native occurrence identity is already owned by another reservation."
        }
        val authority = snapshot.reservations[request.reservationId] ?: return@synchronized null
        when {
            authority.wakePlanId != request.wakePlanId ->
                "Native reservation identity is already owned by another wake plan."
            request.reservationGeneration < authority.reservationGeneration ->
                "Native reservation generation is stale."
            request.reservationGeneration == authority.reservationGeneration &&
                authority.state == ReservationAuthorityState.RETIRED ->
                "Native reservation generation has been retired."
            request.reservationGeneration == authority.reservationGeneration &&
                authority.occurrenceId != request.occurrenceId ->
                "Native reservation generation does not match its occurrence."
            else -> null
        }
    }

    fun recordActive(request: AlarmRequest): Boolean = synchronized(lock) {
        val snapshot = try {
            loadUnlocked()
        } catch (_: Exception) {
            return@synchronized false
        }
        val occurrenceOwner = snapshot.occurrenceOwners[request.occurrenceId]
        if (
            occurrenceOwner != null &&
            occurrenceOwner != (request.reservationId to request.wakePlanId)
        ) return@synchronized false
        val current = snapshot.reservations[request.reservationId]
        if (current != null) {
            if (current.wakePlanId != request.wakePlanId) return@synchronized false
            if (request.reservationGeneration < current.reservationGeneration) {
                return@synchronized false
            }
            if (
                request.reservationGeneration == current.reservationGeneration &&
                (current.state != ReservationAuthorityState.ACTIVE ||
                    current.occurrenceId != request.occurrenceId)
            ) return@synchronized false
        }
        val reservations = snapshot.reservations.toMutableMap()
        val occurrenceOwners = snapshot.occurrenceOwners.toMutableMap()
        reservations[request.reservationId] = request.activeAuthority()
        occurrenceOwners[request.occurrenceId] = request.reservationId to request.wakePlanId
        saveUnlocked(ReservationAuthoritySnapshot(reservations, occurrenceOwners))
    }

    fun recordRetired(requests: Collection<AlarmRequest>): Boolean = synchronized(lock) {
        if (requests.isEmpty()) return@synchronized true
        val snapshot = try {
            loadUnlocked()
        } catch (_: Exception) {
            return@synchronized false
        }
        val reservations = snapshot.reservations.toMutableMap()
        val occurrenceOwners = snapshot.occurrenceOwners.toMutableMap()
        for (request in requests.sortedBy { it.reservationGeneration }) {
            val owner = occurrenceOwners[request.occurrenceId]
            if (owner != null && owner != (request.reservationId to request.wakePlanId)) {
                return@synchronized false
            }
            occurrenceOwners[request.occurrenceId] = request.reservationId to request.wakePlanId
            val current = reservations[request.reservationId]
            if (current != null && current.wakePlanId != request.wakePlanId) {
                return@synchronized false
            }
            if (current == null || request.reservationGeneration >= current.reservationGeneration) {
                reservations[request.reservationId] = ReservationAuthority(
                    reservationId = request.reservationId,
                    wakePlanId = request.wakePlanId,
                    reservationGeneration = request.reservationGeneration,
                    occurrenceId = request.occurrenceId,
                    state = ReservationAuthorityState.RETIRED,
                )
            }
        }
        saveUnlocked(ReservationAuthoritySnapshot(reservations, occurrenceOwners))
    }

    private fun loadUnlocked(): ReservationAuthoritySnapshot {
        val encoded = preferences.getString(AUTHORITY_KEY, null)
            ?: return ReservationAuthoritySnapshot()
        val json = JSONObject(encoded)
        require(json.getInt("schemaVersion") == STORAGE_SCHEMA_VERSION)
        val reservationsJson = json.getJSONObject("reservations")
        val reservations = linkedMapOf<String, ReservationAuthority>()
        val reservationKeys = reservationsJson.keys()
        while (reservationKeys.hasNext()) {
            val key = reservationKeys.next()
            val authority = ReservationAuthority.fromJson(reservationsJson.getJSONObject(key))
            require(authority.reservationId == key)
            require(reservations.put(key, authority) == null)
        }
        val ownersJson = json.getJSONObject("occurrenceOwners")
        val occurrenceOwners = linkedMapOf<String, Pair<String, String>>()
        val ownerKeys = ownersJson.keys()
        while (ownerKeys.hasNext()) {
            val occurrenceId = ownerKeys.next()
            require(occurrenceId.isNotBlank())
            val ownerJson = ownersJson.getJSONObject(occurrenceId)
            val owner = ownerJson.getString("reservationId") to
                ownerJson.getString("wakePlanId")
            require(owner.first.isNotBlank() && owner.second.isNotBlank())
            require(occurrenceOwners.put(occurrenceId, owner) == null)
        }
        reservations.values.forEach { authority ->
            require(
                occurrenceOwners[authority.occurrenceId] ==
                    (authority.reservationId to authority.wakePlanId),
            )
        }
        return ReservationAuthoritySnapshot(reservations, occurrenceOwners)
    }

    private fun saveUnlocked(snapshot: ReservationAuthoritySnapshot): Boolean {
        val reservations = JSONObject()
        snapshot.reservations.toSortedMap().forEach { (key, value) ->
            reservations.put(key, value.toJson())
        }
        val occurrenceOwners = JSONObject()
        snapshot.occurrenceOwners.toSortedMap().forEach { (occurrenceId, owner) ->
            occurrenceOwners.put(
                occurrenceId,
                JSONObject().put("reservationId", owner.first).put("wakePlanId", owner.second),
            )
        }
        val encoded = JSONObject()
            .put("schemaVersion", STORAGE_SCHEMA_VERSION)
            .put("reservations", reservations)
            .put("occurrenceOwners", occurrenceOwners)
            .toString()
        return preferences.edit().putString(AUTHORITY_KEY, encoded).commit()
    }

    private fun AlarmRequest.activeAuthority() = ReservationAuthority(
        reservationId = reservationId,
        wakePlanId = wakePlanId,
        reservationGeneration = reservationGeneration,
        occurrenceId = occurrenceId,
        state = ReservationAuthorityState.ACTIVE,
    )

    private companion object {
        const val PREFERENCES_NAME = "native_alarm_reservation_authority"
        const val AUTHORITY_KEY = "authority"
        const val STORAGE_SCHEMA_VERSION = 1
        val lock = Any()
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
    val schemaVersion: Int = if (
        new.reservationGeneration > old.reservationGeneration
    ) 2 else 1,
) {
    init {
        require(old.reservationId == new.reservationId)
        require(old.wakePlanId == new.wakePlanId)
        require(
            old.occurrenceId != new.occurrenceId ||
                schemaVersion == 2 &&
                new.reservationGeneration > old.reservationGeneration,
        )
        require(old.platformAlarmId != new.platformAlarmId)
        require(old.hasCanonicalPlatformAlarmId())
        require(
            schemaVersion == 1 &&
                old.reservationGeneration == 0L &&
                new.reservationGeneration == 0L &&
                new.platformAlarmId == AlarmRequest.legacyReplacementPlatformAlarmId(new) ||
                schemaVersion == 2 &&
                new.reservationGeneration > old.reservationGeneration &&
                new.platformAlarmId == AlarmRequest.replacementPlatformAlarmId(new),
        )
    }

    fun toJson(): JSONObject {
        val oldJson = old.toJson()
        val newJson = new.toJson()
        if (schemaVersion == 1) {
            oldJson.remove("reservationGeneration")
            newJson.remove("reservationGeneration")
        }
        return JSONObject()
            .put("schemaVersion", schemaVersion)
            .put("old", oldJson)
            .put("new", newJson)
            .put("phase", phase.name)
    }

    companion object {
        fun fromJson(json: JSONObject): AlarmReplacementJournal {
            val schemaVersion = json.getInt("schemaVersion")
            require(schemaVersion == 1 || schemaVersion == 2)
            val oldJson = json.getJSONObject("old")
            val newJson = json.getJSONObject("new")
            require(
                schemaVersion == 1 &&
                    !oldJson.has("reservationGeneration") &&
                    !newJson.has("reservationGeneration") ||
                    schemaVersion == 2 &&
                    oldJson.has("reservationGeneration") &&
                    newJson.has("reservationGeneration"),
            )
            return AlarmReplacementJournal(
                old = AlarmRequest.fromJson(oldJson),
                new = AlarmRequest.fromJson(newJson),
                phase = AlarmReplacementPhase.valueOf(json.getString("phase")),
                schemaVersion = schemaVersion,
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
        admittingPlatformAlarmId: String? = null,
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
        val authorityStore = ReservationAuthorityStore(storageContext)
        if (
            admittingPlatformAlarmId != null &&
            admittingPlatformAlarmId != journal.old.platformAlarmId &&
            admittingPlatformAlarmId != journal.new.platformAlarmId
        ) {
            return@synchronized AlarmReplacementRecoveryResult(
                isSuccess = false,
                message = "Alarm admission identity does not match the active replacement journal.",
            )
        }
        val winner = selectWinner(
            journal,
            System.currentTimeMillis(),
            admittingPlatformAlarmId,
        ) ?: return@synchronized retireExpired(
            journal,
            appContext,
            alarmManager,
            store,
            journalStore,
            authorityStore,
        )
        val loser = if (winner == journal.new) journal.old else journal.new

        if (!authorityStore.recordActive(winner)) {
            return@synchronized AlarmReplacementRecoveryResult(
                isSuccess = false,
                message = "Failed to persist native alarm replacement generation authority.",
            )
        }
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
            if (winner.platformAlarmId != admittingPlatformAlarmId) {
                arm(appContext, alarmManager, winner)
            }
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

    private fun selectWinner(
        journal: AlarmReplacementJournal,
        nowMillis: Long,
        admittingPlatformAlarmId: String?,
    ): AlarmRequest? {
        val isAdmittingOld = admittingPlatformAlarmId == journal.old.platformAlarmId
        val isAdmittingNew = admittingPlatformAlarmId == journal.new.platformAlarmId
        val oldMayWin = journal.phase != AlarmReplacementPhase.OLD_RETIRED
        return when {
            journal.phase == AlarmReplacementPhase.OLD_RETIRED &&
                (journal.new.scheduledAtMillis > nowMillis || isAdmittingNew) -> journal.new
            oldMayWin && isAdmittingOld -> journal.old
            oldMayWin && isAdmittingNew -> journal.new
            oldMayWin && journal.old.scheduledAtMillis > nowMillis -> journal.old
            oldMayWin && journal.new.scheduledAtMillis > nowMillis -> journal.new
            else -> null
        }
    }

    private fun retireExpired(
        journal: AlarmReplacementJournal,
        appContext: Context,
        alarmManager: AlarmManager,
        store: AlarmStore,
        journalStore: AlarmReplacementJournalStore,
        authorityStore: ReservationAuthorityStore,
    ): AlarmReplacementRecoveryResult {
        val expiredPlatformAlarmIds = setOf(
            journal.old.platformAlarmId,
            journal.new.platformAlarmId,
        )
        if (!authorityStore.recordRetired(listOf(journal.old, journal.new))) {
            return AlarmReplacementRecoveryResult(
                isSuccess = false,
                message = "Failed to persist expired native alarm generation retirement.",
            )
        }
        if (!store.removeAll(expiredPlatformAlarmIds)) {
            return AlarmReplacementRecoveryResult(
                isSuccess = false,
                message = "Failed to retire expired native alarm replacement rows.",
            )
        }
        try {
            cancel(appContext, alarmManager, journal.old.platformAlarmId)
            cancel(appContext, alarmManager, journal.new.platformAlarmId)
        } catch (error: RuntimeException) {
            return AlarmReplacementRecoveryResult(
                isSuccess = false,
                message = error.message ?: "Failed to retire expired native alarms.",
            )
        }
        if (!journalStore.clear()) {
            return AlarmReplacementRecoveryResult(
                isSuccess = false,
                message = "Failed to clear expired native alarm replacement journal.",
            )
        }
        return AlarmReplacementRecoveryResult(isSuccess = true)
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
