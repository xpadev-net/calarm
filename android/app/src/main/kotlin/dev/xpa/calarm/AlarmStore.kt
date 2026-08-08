package dev.xpa.calarm

import android.app.AlarmManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.os.UserManager
import android.util.Log
import org.json.JSONObject

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
        return removeRaw(platformAlarmId)
    }

    internal fun removeRaw(platformAlarmId: String): Boolean =
        preferences.edit().remove(platformAlarmId).commit()

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

    /**
     * Transitions [platformAlarmId] to [AlarmState.RINGING], or returns `false` if it is already
     * ringing. The read-check-write runs under [AndroidAlarmMutationTransaction] so a broadcast
     * delivery racing an inventory or restore catch-up can't both win this transition and
     * deliver the same occurrence twice — exactly one caller sees `true`.
     */
    fun markRinging(platformAlarmId: String): Boolean {
        return AndroidAlarmMutationTransaction.run {
            val request = get(platformAlarmId) ?: return@run false
            if (
                request.platformAlarmId != platformAlarmId ||
                !request.hasCanonicalPlatformAlarmId() ||
                request.state == AlarmState.RINGING
            ) {
                return@run false
            }
            put(request.copy(state = AlarmState.RINGING))
        }
    }

    fun inventory(context: Context, nowMillis: Long): AlarmInventorySnapshot {
        val corruptKeys = mutableListOf<String>()
        val staleKeys = mutableListOf<String>()
        val staleRequests = mutableListOf<AlarmRequest>()
        val missedRequests = mutableListOf<AlarmRequest>()
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
                if (nowMillis - request.scheduledAtMillis <= MISSED_ALARM_CATCH_UP_WINDOW_MILLIS) {
                    missedRequests += request
                } else {
                    staleKeys += key
                    staleRequests += request
                }
            } else {
                requests += request
            }
        }
        // Identity validation runs before any irreversible side effect below — including
        // cancelling a missed alarm's pending AlarmManager entry, which (unlike removing a
        // stale row) can't simply be redone if we bail out here — so a corrupt/duplicate
        // inventory is reported as a failure first rather than discovered afterward.
        val candidateRequests = requests + missedRequests
        val duplicateReservation = candidateRequests.groupBy { it.reservationId }
            .values.firstOrNull { it.size > 1 }
        if (duplicateReservation != null) {
            return AlarmInventorySnapshot(
                requests = emptyList(),
                corruptKeys = corruptKeys,
                duplicateIdentity = "Duplicate native reservation identity: ${duplicateReservation.first().reservationId}.",
            )
        }
        val duplicateOccurrence = candidateRequests.groupBy { it.occurrenceId }
            .values.firstOrNull { it.size > 1 }
        if (duplicateOccurrence != null) {
            return AlarmInventorySnapshot(
                requests = emptyList(),
                corruptKeys = corruptKeys,
                duplicateIdentity = "Duplicate native occurrence identity: ${duplicateOccurrence.first().occurrenceId}.",
            )
        }
        val cleanupKeys = corruptKeys + staleKeys
        if (cleanupKeys.isNotEmpty() || staleRequests.isNotEmpty()) {
            if (
                staleRequests.isNotEmpty() &&
                !ReservationAuthorityStore(storageContext).recordRetired(staleRequests)
            ) {
                return AlarmInventorySnapshot(
                    requests = emptyList(),
                    corruptKeys = cleanupKeys,
                    duplicateIdentity = "Failed to persist expired native alarm generation retirement.",
                )
            }
            try {
                val alarmManager = context.getSystemService(AlarmManager::class.java)
                staleRequests.forEach { request ->
                    alarmManager.cancel(AlarmIntents.receiver(context, request.platformAlarmId))
                }
            } catch (error: RuntimeException) {
                return AlarmInventorySnapshot(
                    requests = emptyList(),
                    corruptKeys = cleanupKeys,
                    duplicateIdentity = error.message
                        ?: "Failed to cancel expired native alarm rows.",
                )
            }
            if (cleanupKeys.isNotEmpty()) {
                val editor = preferences.edit()
                cleanupKeys.forEach { key -> editor.remove(key) }
                if (!editor.commit()) {
                    return AlarmInventorySnapshot(
                        requests = emptyList(),
                        corruptKeys = cleanupKeys,
                        duplicateIdentity = "Failed to clean native alarm mirror rows.",
                    )
                }
            }
        }
        missedRequests.forEach { request ->
            val platformAlarmId = request.platformAlarmId
            try {
                context.getSystemService(AlarmManager::class.java)
                    .cancel(AlarmIntents.receiver(context, platformAlarmId))
            } catch (error: RuntimeException) {
                Log.w(
                    TAG,
                    "Failed to cancel a missed native alarm's pending AlarmManager entry; " +
                        "proceeding with catch-up delivery regardless: $platformAlarmId",
                    error,
                )
            }
            if (!markRinging(platformAlarmId)) {
                val current = get(platformAlarmId)
                if (current?.state == AlarmState.RINGING) {
                    // A concurrent broadcast delivery already claimed and rang this occurrence.
                    requests += current
                } else {
                    Log.e(
                        TAG,
                        "Failed to deliver a missed native alarm during inventory " +
                            "reconciliation; it was removed: $platformAlarmId",
                    )
                    remove(platformAlarmId)
                }
                return@forEach
            }
            Log.w(
                TAG,
                "Delivering a native alarm missed while the app was killed instead of " +
                    "discarding it: $platformAlarmId",
            )
            if (AlarmReceiver().deliverAlreadyRingingAlarm(context, this, request)) {
                requests += request.copy(state = AlarmState.RINGING)
            } else {
                Log.e(
                    TAG,
                    "Failed to deliver a missed native alarm during inventory reconciliation; " +
                        "it was removed: $platformAlarmId",
                )
                remove(platformAlarmId)
            }
        }
        return AlarmInventorySnapshot(
            requests = requests,
            corruptKeys = corruptKeys,
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
        const val TAG = "CalarmAlarmStore"

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
