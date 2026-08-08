package dev.xpa.calarm

import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import org.json.JSONObject

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
    fun reconcile(
        storageContext: Context,
        serviceContext: Context,
        admittingPlatformAlarmId: String? = null,
    ): AlarmReplacementRecoveryResult = AndroidAlarmMutationTransaction.run transaction@ {
        val appContext = serviceContext.applicationContext
        val journalStore = AlarmReplacementJournalStore(storageContext)
        val activationCleanupStore = AlarmActivationCleanupStore(storageContext)
        val journal = try {
            journalStore.load()
        } catch (error: Exception) {
            return@transaction AlarmReplacementRecoveryResult(
                isSuccess = false,
                message = error.message ?: "Native alarm replacement journal is corrupt.",
            )
        }
        val activationCleanup = try {
            activationCleanupStore.load()
        } catch (error: Exception) {
            return@transaction AlarmReplacementRecoveryResult(
                isSuccess = false,
                message = error.message ?: "Native alarm activation cleanup journal is corrupt.",
            )
        }
        if (journal != null && activationCleanup != null) {
            return@transaction AlarmReplacementRecoveryResult(
                isSuccess = false,
                message = "Native alarm replacement and activation cleanup journals conflict.",
            )
        }

        val alarmManager = appContext.getSystemService(AlarmManager::class.java)
        val store = AlarmStore(storageContext)
        val authorityStore = ReservationAuthorityStore(storageContext)
        if (
            activationCleanup != null &&
            (admittingPlatformAlarmId == null ||
                admittingPlatformAlarmId == activationCleanup.platformAlarmId)
        ) {
            val cleanup = reconcileActivationCleanup(
                activationCleanup,
                appContext,
                alarmManager,
                store,
                authorityStore,
                activationCleanupStore,
            )
            if (!cleanup.isSuccess) return@transaction cleanup
        }
        if (journal == null) {
            return@transaction reconcileRetiredMirrors(
                appContext,
                alarmManager,
                store,
                authorityStore,
                admittingPlatformAlarmId,
            )
        }
        if (
            admittingPlatformAlarmId != null &&
            admittingPlatformAlarmId != journal.old.platformAlarmId &&
            admittingPlatformAlarmId != journal.new.platformAlarmId
        ) {
            return@transaction AlarmReplacementRecoveryResult(
                isSuccess = false,
                message = "Alarm admission identity does not match the active replacement journal.",
            )
        }
        val winner = selectWinner(
            journal,
            System.currentTimeMillis(),
            admittingPlatformAlarmId,
        )
        if (winner == null) {
            val retired = retireExpired(
                journal,
                appContext,
                alarmManager,
                store,
                journalStore,
                authorityStore,
            )
            return@transaction if (retired.isSuccess) {
                reconcileRetiredMirrors(
                    appContext,
                    alarmManager,
                    store,
                    authorityStore,
                    admittingPlatformAlarmId,
                )
            } else {
                retired
            }
        }
        val loser = if (winner == journal.new) journal.old else journal.new

        if (!authorityStore.recordActive(winner)) {
            return@transaction AlarmReplacementRecoveryResult(
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
            return@transaction AlarmReplacementRecoveryResult(
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
            return@transaction AlarmReplacementRecoveryResult(
                isSuccess = false,
                message = error.message ?: "Native alarm replacement recovery failed.",
            )
        }
        if (!journalStore.clear()) {
            return@transaction AlarmReplacementRecoveryResult(
                isSuccess = false,
                message = "Failed to clear native alarm replacement journal.",
            )
        }
        reconcileRetiredMirrors(
            appContext,
            alarmManager,
            store,
            authorityStore,
            admittingPlatformAlarmId,
        )
    }

    private fun reconcileActivationCleanup(
        request: AlarmRequest,
        appContext: Context,
        alarmManager: AlarmManager,
        store: AlarmStore,
        authorityStore: ReservationAuthorityStore,
        cleanupStore: AlarmActivationCleanupStore,
    ): AlarmReplacementRecoveryResult {
        val authority = try {
            authorityStore.load().reservations[request.reservationId]
        } catch (error: Exception) {
            return AlarmReplacementRecoveryResult(
                isSuccess = false,
                message = error.message ?: "Native reservation generation authority is corrupt.",
            )
        }
        if (
            authority?.state == ReservationAuthorityState.ACTIVE &&
            authority.wakePlanId == request.wakePlanId &&
            authority.reservationGeneration == request.reservationGeneration &&
            authority.occurrenceId == request.occurrenceId
        ) {
            val snapshot = store.inspectIdentities(appContext, System.currentTimeMillis())
            if (snapshot.duplicateIdentity != null || snapshot.corruptKeys.isNotEmpty()) {
                return AlarmReplacementRecoveryResult(
                    isSuccess = false,
                    message = snapshot.duplicateIdentity
                        ?: "Native alarm mirror state is corrupt during activation recovery.",
                )
            }
            val mirror = snapshot.requests.singleOrNull {
                it.platformAlarmId == request.platformAlarmId
            }
            if (mirror?.copy(updatedAtMillis = request.updatedAtMillis) == request) {
                return if (cleanupStore.clear()) {
                    AlarmReplacementRecoveryResult(isSuccess = true)
                } else {
                    AlarmReplacementRecoveryResult(
                        isSuccess = false,
                        message = "Failed to clear committed native alarm activation evidence.",
                    )
                }
            }
        }
        if (!authorityStore.recordRetired(listOf(request))) {
            return AlarmReplacementRecoveryResult(
                isSuccess = false,
                message = "Failed to persist pending native alarm activation retirement.",
            )
        }
        val retired = try {
            authorityStore.load().reservations[request.reservationId]
        } catch (error: Exception) {
            return AlarmReplacementRecoveryResult(
                isSuccess = false,
                message = error.message ?: "Native reservation generation authority is corrupt.",
            )
        }
        if (
            retired?.state != ReservationAuthorityState.RETIRED ||
            retired.wakePlanId != request.wakePlanId ||
            retired.reservationGeneration != request.reservationGeneration ||
            retired.occurrenceId != request.occurrenceId
        ) {
            return AlarmReplacementRecoveryResult(
                isSuccess = false,
                message = "Pending native alarm activation retirement is non-monotonic.",
            )
        }
        try {
            cancel(appContext, alarmManager, request.platformAlarmId)
        } catch (error: RuntimeException) {
            return AlarmReplacementRecoveryResult(
                isSuccess = false,
                message = error.message ?: "Failed to cancel a pending native alarm activation.",
            )
        }
        if (!store.removeRaw(request.platformAlarmId)) {
            return AlarmReplacementRecoveryResult(
                isSuccess = false,
                message = "Failed to remove a pending native alarm activation mirror.",
            )
        }
        appContext.getSystemService(NotificationManager::class.java)
            .cancel(request.platformAlarmId.hashCode())
        if (!cleanupStore.clear()) {
            return AlarmReplacementRecoveryResult(
                isSuccess = false,
                message = "Failed to clear native alarm activation cleanup evidence.",
            )
        }
        return AlarmReplacementRecoveryResult(isSuccess = true)
    }

    private fun reconcileRetiredMirrors(
        appContext: Context,
        alarmManager: AlarmManager,
        store: AlarmStore,
        authorityStore: ReservationAuthorityStore,
        admittingPlatformAlarmId: String?,
    ): AlarmReplacementRecoveryResult {
        var authority = try {
            authorityStore.load()
        } catch (error: Exception) {
            return AlarmReplacementRecoveryResult(
                isSuccess = false,
                message = error.message ?: "Native reservation generation authority is corrupt.",
            )
        }
        val snapshot = store.inspectIdentities(appContext, System.currentTimeMillis())
        val admittedMirrorIsCorrupt = admittingPlatformAlarmId != null &&
            snapshot.corruptKeys.contains(admittingPlatformAlarmId)
        if (snapshot.duplicateIdentity != null || admittedMirrorIsCorrupt) {
            return AlarmReplacementRecoveryResult(
                isSuccess = false,
                message = snapshot.duplicateIdentity
                    ?: "Native alarm mirror state is corrupt during reservation recovery.",
            )
        }
        val relevantRequests = snapshot.requests.filter { request ->
            admittingPlatformAlarmId == null ||
                request.platformAlarmId == admittingPlatformAlarmId
        }
        for (request in relevantRequests) {
            val persisted = authority.reservations[request.reservationId] ?: continue
            val samePlan = persisted.wakePlanId == request.wakePlanId
            val exactTuple = samePlan &&
                persisted.reservationGeneration == request.reservationGeneration &&
                persisted.occurrenceId == request.occurrenceId
            val recoverableAdvance = samePlan &&
                request.reservationGeneration > persisted.reservationGeneration
            if (!exactTuple && !recoverableAdvance) {
                return AlarmReplacementRecoveryResult(
                    isSuccess = false,
                    message = "Native alarm mirror conflicts with reservation generation authority.",
                )
            }
        }
        val pendingActivations = snapshot.requests.filter { request ->
            val persisted = authority.reservations[request.reservationId]
            val matchesAdmission = admittingPlatformAlarmId == null ||
                request.platformAlarmId == admittingPlatformAlarmId
            val advancesAuthority = persisted != null &&
                persisted.wakePlanId == request.wakePlanId &&
                request.reservationGeneration > persisted.reservationGeneration
            val seedsStableAuthority = persisted == null &&
                request.reservationId != request.occurrenceId &&
                request.platformAlarmId != AlarmRequest.legacyPlatformAlarmId(request)
            matchesAdmission && (advancesAuthority || seedsStableAuthority)
        }
        for (request in pendingActivations) {
            if (
                request.state != AlarmState.RINGING &&
                request.platformAlarmId != admittingPlatformAlarmId
            ) {
                try {
                    arm(appContext, alarmManager, request)
                } catch (error: RuntimeException) {
                    return AlarmReplacementRecoveryResult(
                        isSuccess = false,
                        message = error.message ?: "Failed to restore native alarm activation.",
                    )
                }
            }
            if (!authorityStore.recordActive(request)) {
                return AlarmReplacementRecoveryResult(
                    isSuccess = false,
                    message = "Failed to finish native alarm generation activation.",
                )
            }
        }
        if (pendingActivations.isNotEmpty()) {
            authority = try {
                authorityStore.load()
            } catch (error: Exception) {
                return AlarmReplacementRecoveryResult(
                    isSuccess = false,
                    message = error.message
                        ?: "Native reservation generation authority is corrupt.",
                )
            }
        }
        val pendingRetirements = snapshot.requests.filter { request ->
            val persisted = authority.reservations[request.reservationId]
            (admittingPlatformAlarmId == null ||
                request.platformAlarmId == admittingPlatformAlarmId) &&
                persisted?.state == ReservationAuthorityState.RETIRED &&
                persisted.wakePlanId == request.wakePlanId &&
                persisted.reservationGeneration == request.reservationGeneration &&
                persisted.occurrenceId == request.occurrenceId
        }
        for (request in pendingRetirements) {
            try {
                cancel(appContext, alarmManager, request.platformAlarmId)
            } catch (error: RuntimeException) {
                return AlarmReplacementRecoveryResult(
                    isSuccess = false,
                    message = error.message ?: "Failed to finish native alarm retirement.",
                )
            }
            if (!store.removeRaw(request.platformAlarmId)) {
                return AlarmReplacementRecoveryResult(
                    isSuccess = false,
                    message = "Failed to remove a retired native alarm mirror row.",
                )
            }
            appContext.getSystemService(NotificationManager::class.java)
                .cancel(request.platformAlarmId.hashCode())
        }
        return AlarmReplacementRecoveryResult(isSuccess = true)
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
        try {
            cancel(appContext, alarmManager, journal.old.platformAlarmId)
            cancel(appContext, alarmManager, journal.new.platformAlarmId)
        } catch (error: RuntimeException) {
            return AlarmReplacementRecoveryResult(
                isSuccess = false,
                message = error.message ?: "Failed to retire expired native alarms.",
            )
        }
        if (!store.removeAll(expiredPlatformAlarmIds)) {
            return AlarmReplacementRecoveryResult(
                isSuccess = false,
                message = "Failed to retire expired native alarm replacement rows.",
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
