package dev.xpa.calarm

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONException

internal object AndroidAlarmMutationTransaction {
    private val lock = Any()

    fun <T> run(block: () -> T): T = synchronized(lock) { block() }
}

class AndroidAlarmBridge(private val context: Context) : MethodChannel.MethodCallHandler {
    private val activity = context as? Activity
    private val appContext = context.applicationContext
    private val alarmManager = appContext.getSystemService(AlarmManager::class.java)
    private val notificationManager = appContext.getSystemService(NotificationManager::class.java)
    private val store = AlarmStore(appContext)
    private val authorityStore = ReservationAuthorityStore(appContext)
    private val activationCleanupStore = AlarmActivationCleanupStore(appContext)
    private val eventStore = AlarmEventStore(appContext)
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null
    private var requestNotificationRuntimePermission: (Activity, Array<String>, Int) -> Unit =
        { permissionActivity, permissions, requestCode ->
            permissionActivity.requestPermissions(permissions, requestCode)
        }
    private var launchSettingsActivity: (Intent) -> Unit = { intent ->
        appContext.startActivity(intent)
    }
    private var beforeAlarmManagerMutation: () -> Unit = {}

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

    internal fun setBeforeAlarmManagerMutationForTest(hook: () -> Unit) {
        beforeAlarmManagerMutation = hook
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

    private fun schedule(request: AlarmRequest): Map<String, Any?> =
        AndroidAlarmMutationTransaction.run { scheduleLocked(request) }

    private fun scheduleLocked(request: AlarmRequest): Map<String, Any?> {
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
        val authorityValidationFailure = authorityStore.validateAndSeedActive(
            identitySnapshot.requests.filterNot { it == adoptableLegacyIdentity },
        )
        if (authorityValidationFailure != null) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "nativeError",
                authorityValidationFailure,
                request.reservationId,
                request.reservationGeneration,
            )
        }
        val authorityFailure = authorityStore.admissionFailure(request)
        if (authorityFailure != null) {
            return scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                authorityFailure.failureReason,
                authorityFailure.message,
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
                existing.copy(
                    reservationId = request.reservationId,
                    indexInPlan = existing.indexInPlan ?: request.indexInPlan,
                    totalInPlan = existing.totalInPlan ?: request.totalInPlan,
                )
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
            if (legacyRequest != null && comparableExisting != existing) {
                val adoptedRingingRequest = comparableExisting.copy(
                    platformAlarmIdOverride = platformAlarmId,
                )
                if (!store.put(adoptedRingingRequest)) {
                    return scheduleFailure(
                        request.occurrenceId,
                        request.wakePlanId,
                        "nativeError",
                        "Failed to persist native alarm mirror state.",
                        request.reservationId,
                        request.reservationGeneration,
                    )
                }
                if (!authorityStore.recordActive(adoptedRingingRequest)) {
                    store.put(existing)
                    return scheduleFailure(
                        request.occurrenceId,
                        request.wakePlanId,
                        "nativeError",
                        "Failed to persist native reservation generation authority.",
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
                if (!store.put(adopted)) {
                    return scheduleFailure(
                        request.occurrenceId,
                        request.wakePlanId,
                        "nativeError",
                        "Failed to persist adopted native reservation generation.",
                        request.reservationId,
                        request.reservationGeneration,
                    )
                }
                if (!authorityStore.recordActive(adopted)) {
                    store.put(existing)
                    return scheduleFailure(
                        request.occurrenceId,
                        request.wakePlanId,
                        "nativeError",
                        "Failed to persist adopted native reservation generation authority.",
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
            beforeAlarmManagerMutation()
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
        cancel: () -> Boolean = { cancelReceiver(platformAlarmId) },
        recordActive: (AlarmRequest) -> Boolean = { authorityStore.recordActive(it) },
        recordRetired: (AlarmRequest) -> Boolean = {
            authorityStore.recordRetired(listOf(it))
        },
        removePersisted: () -> Boolean = { store.removeRaw(platformAlarmId) },
    ): MutableMap<String, Any?> {
        val persisted = request.copy(
            platformAlarmIdOverride = platformAlarmId,
            state = AlarmState.SCHEDULED,
        )
        return try {
            if (!activationCleanupStore.save(persisted)) {
                return scheduleFailure(
                    request.occurrenceId,
                    request.wakePlanId,
                    "nativeError",
                    "Failed to persist native alarm activation cleanup evidence.",
                    request.reservationId,
                    request.reservationGeneration,
                )
            }
            arm()
            if (!persist()) {
                val cleanupCompleted = cleanupStagedActivation(
                    persisted,
                    cancel,
                    removePersisted,
                    recordRetired,
                )
                return scheduleFailure(
                    request.occurrenceId,
                    request.wakePlanId,
                    "nativeError",
                    activationFailureMessage(
                        "Failed to persist native alarm mirror state.",
                        cleanupCompleted,
                    ),
                    request.reservationId,
                    request.reservationGeneration,
                )
            }
            if (!recordActive(persisted)) {
                val cleanupCompleted = cleanupStagedActivation(
                    persisted,
                    cancel,
                    removePersisted,
                    recordRetired,
                )
                return scheduleFailure(
                    request.occurrenceId,
                    request.wakePlanId,
                    "nativeError",
                    activationFailureMessage(
                        "Failed to persist native reservation generation authority.",
                        cleanupCompleted,
                    ),
                    request.reservationId,
                    request.reservationGeneration,
                )
            }
            if (!activationCleanupStore.clear()) {
                return scheduleFailure(
                    request.occurrenceId,
                    request.wakePlanId,
                    "nativeError",
                    activationFailureMessage(
                        "Failed to clear native alarm activation cleanup evidence.",
                        cleanupCompleted = false,
                    ),
                    request.reservationId,
                    request.reservationGeneration,
                )
            }
            scheduleSuccess(request, platformAlarmId)
        } catch (error: JSONException) {
            val cleanupCompleted = cleanupStagedActivation(
                persisted,
                cancel,
                removePersisted,
                recordRetired,
            )
            scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "nativeError",
                activationFailureMessage(
                    error.message ?: "Failed to persist native alarm mirror state.",
                    cleanupCompleted,
                ),
                request.reservationId,
                request.reservationGeneration,
            )
        } catch (error: RuntimeException) {
            val cleanupCompleted = cleanupStagedActivation(
                persisted,
                cancel,
                removePersisted,
                recordRetired,
            )
            scheduleFailure(
                request.occurrenceId,
                request.wakePlanId,
                "nativeError",
                activationFailureMessage(
                    error.message ?: "AlarmManager rejected the alarm.",
                    cleanupCompleted,
                ),
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
        cancel: () -> Boolean,
        recordActive: (AlarmRequest) -> Boolean = { authorityStore.recordActive(it) },
        recordRetired: (AlarmRequest) -> Boolean = {
            authorityStore.recordRetired(listOf(it))
        },
        removePersisted: () -> Boolean = { store.removeRaw(platformAlarmId) },
    ): Map<String, Any?> {
        return AndroidAlarmMutationTransaction.run {
            armAndPersist(
                request,
                platformAlarmId,
                arm,
                persist,
                cancel,
                recordActive,
                recordRetired,
                removePersisted,
            )
        }
    }

    private fun activationFailureMessage(
        message: String,
        cleanupCompleted: Boolean,
    ): String = if (cleanupCompleted) {
        message
    } else {
        "$message Activation cleanup remains pending durable recovery."
    }

    private fun cleanupStagedActivation(
        request: AlarmRequest,
        cancel: () -> Boolean,
        removePersisted: () -> Boolean,
        recordRetired: (AlarmRequest) -> Boolean,
    ): Boolean {
        if (!recordRetired(request)) return false
        val (cancelled, mirrorRemoved) = cleanupActivation(cancel, removePersisted)
        return cancelled && mirrorRemoved && activationCleanupStore.clear()
    }

    private fun cleanupActivation(
        cancel: () -> Boolean,
        removePersisted: () -> Boolean,
    ): Pair<Boolean, Boolean> {
        val cancelled = try {
            cancel()
        } catch (_: RuntimeException) {
            false
        }
        val mirrorRemoved = cancelled && try {
            removePersisted()
        } catch (_: RuntimeException) {
            false
        }
        return cancelled to mirrorRemoved
    }

    private fun cancelReceiver(platformAlarmId: String): Boolean {
        return try {
            alarmManager.cancel(AlarmIntents.receiver(appContext, platformAlarmId))
            true
        } catch (_: RuntimeException) {
            false
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
            beforeAlarmManagerMutation()
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

    private fun cancel(arguments: Map<*, *>): Map<String, Any?> =
        AndroidAlarmMutationTransaction.run { cancelLocked(arguments) }

    private fun cancelLocked(arguments: Map<*, *>): Map<String, Any?> {
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
        val identitySnapshot = store.inspectIdentities(appContext, System.currentTimeMillis())
        if (identitySnapshot.corruptKeys.isNotEmpty() || identitySnapshot.duplicateIdentity != null) {
            return cancelFailure(
                occurrenceId,
                platformAlarmId,
                "nativeError",
                identitySnapshot.duplicateIdentity
                    ?: "Native alarm mirror contains corrupt identity rows.",
                reservationId,
                reservationGeneration,
            )
        }
        val requestedRow = identitySnapshot.requests.singleOrNull {
            it.platformAlarmId == platformAlarmId
        }
        if (
            requestedRow != null &&
            !cancelIdentityMatches(
                requestedRow,
                occurrenceId,
                reservationId,
                reservationGeneration,
            )
        ) {
            return cancelFailure(
                occurrenceId,
                platformAlarmId,
                "invalidRequest",
                "Native alarm identity does not match the requested reservation.",
                reservationId,
                reservationGeneration,
            )
        }
        val exactRow = identitySnapshot.requests.singleOrNull {
            it.occurrenceId == occurrenceId &&
                it.reservationId == reservationId &&
                it.reservationGeneration == reservationGeneration
        } ?: requestedRow?.takeIf {
            cancelIdentityMatches(
                it,
                occurrenceId,
                reservationId,
                reservationGeneration,
            )
        }
        if (
            exactRow == null &&
            identitySnapshot.requests.any {
                it.occurrenceId == occurrenceId || it.reservationId == reservationId
            }
        ) {
            return cancelFailure(
                occurrenceId,
                platformAlarmId,
                "invalidRequest",
                "Native alarm identity does not match the requested reservation.",
                reservationId,
                reservationGeneration,
            )
        }
        val effectivePlatformAlarmId = exactRow?.platformAlarmId ?: platformAlarmId
        return try {
            val stored = store.get(effectivePlatformAlarmId)
            when {
                store.contains(effectivePlatformAlarmId) && stored == null -> cancelFailure(
                    occurrenceId,
                    platformAlarmId,
                    "nativeError",
                    "Native alarm mirror row is corrupt.",
                    reservationId,
                    reservationGeneration,
                )
                stored != null &&
                    (stored.platformAlarmId != effectivePlatformAlarmId ||
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
                    alarmManager.cancel(AlarmIntents.receiver(appContext, effectivePlatformAlarmId))
                    if (!store.removeRaw(effectivePlatformAlarmId)) {
                        cancelFailure(
                            occurrenceId,
                            platformAlarmId,
                            "nativeError",
                            "Failed to persist native alarm mirror removal.",
                            reservationId,
                            reservationGeneration,
                        )
                    } else {
                        notificationManager.cancel(effectivePlatformAlarmId.hashCode())
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
        return AndroidAlarmMutationTransaction.run inventory@ {
        val replacementRecovery = AndroidAlarmReplacementRecovery.reconcile(
            storageContext = appContext,
            serviceContext = appContext,
        )
        if (!replacementRecovery.isSuccess) {
            return@inventory InventoryResponse(
                response = null,
                failureCode = "NATIVE_ERROR",
                failureMessage = replacementRecovery.message,
            )
        }
        val snapshot = store.inventory(appContext, System.currentTimeMillis())
        if (snapshot.corruptKeys.isNotEmpty()) {
            return@inventory InventoryResponse(
                response = null,
                failureCode = "CORRUPT",
                failureMessage = "Removed corrupt native alarm mirror rows: ${snapshot.corruptKeys.joinToString()}.",
            )
        }
        if (snapshot.duplicateIdentity != null) {
            return@inventory InventoryResponse(
                response = null,
                failureCode = "CORRUPT",
                failureMessage = snapshot.duplicateIdentity,
            )
        }
        val authorityFailure = authorityStore.validateAndSeedActive(snapshot.requests)
        if (authorityFailure != null) {
            return@inventory InventoryResponse(
                response = null,
                failureCode = "CORRUPT",
                failureMessage = authorityFailure,
            )
        }
        InventoryResponse(
            response = mutableResponse(
                "reservations" to snapshot.requests.map { request ->
                    mutableMapOf(
                        "reservationId" to request.reservationId,
                        "reservationGeneration" to request.reservationGeneration,
                        "occurrenceId" to request.occurrenceId,
                        "wakePlanId" to request.wakePlanId,
                        "platformAlarmId" to request.platformAlarmId,
                        "status" to snapshot.status(appContext, request),
                    )
                },
            ),
        )
        }
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
