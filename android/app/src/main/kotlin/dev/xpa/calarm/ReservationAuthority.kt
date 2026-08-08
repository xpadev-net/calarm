package dev.xpa.calarm

import android.content.Context
import android.os.Build
import org.json.JSONObject


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
        require(reservationId.isNotBlank()) { "reservationId must not be blank" }
        require(wakePlanId.isNotBlank()) { "wakePlanId must not be blank" }
        require(reservationGeneration >= 0L) { "reservationGeneration must not be negative" }
        require(occurrenceId.isNotBlank()) { "occurrenceId must not be blank" }
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
            require(generation is Long || generation is Int) {
                "reservationGeneration must be an integral number"
            }
            val exactGeneration = (generation as Number).toLong()
            require(exactGeneration >= 0L) { "reservationGeneration must not be negative" }
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

internal data class ReservationAdmissionFailure(
    val failureReason: String,
    val message: String,
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
        if (requests.groupBy { it.reservationId }.values.any { it.size > 1 }) {
            return@synchronized "Duplicate native reservation identity."
        }
        if (requests.groupBy { it.occurrenceId }.values.any { it.size > 1 }) {
            return@synchronized "Duplicate native occurrence identity."
        }
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
                authority.wakePlanId == request.wakePlanId &&
                request.reservationGeneration > authority.reservationGeneration
            ) {
                if (
                    authority.occurrenceId != request.occurrenceId &&
                    occurrenceOwners[authority.occurrenceId] ==
                        (request.reservationId to request.wakePlanId)
                ) {
                    occurrenceOwners.remove(authority.occurrenceId)
                }
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

    fun admissionFailure(request: AlarmRequest): ReservationAdmissionFailure? = synchronized(lock) {
        val snapshot = try {
            loadUnlocked()
        } catch (_: Exception) {
            return@synchronized ReservationAdmissionFailure(
                failureReason = "nativeError",
                message = "Native reservation generation authority is corrupt.",
            )
        }
        val occurrenceOwner = snapshot.occurrenceOwners[request.occurrenceId]
        if (
            occurrenceOwner != null &&
            occurrenceOwner != (request.reservationId to request.wakePlanId)
        ) {
            return@synchronized ReservationAdmissionFailure(
                failureReason = "invalidRequest",
                message = "Native occurrence identity is already owned by another reservation.",
            )
        }
        val authority = snapshot.reservations[request.reservationId] ?: return@synchronized null
        val message = when {
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
        message?.let {
            ReservationAdmissionFailure(
                failureReason = "invalidRequest",
                message = it,
            )
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
        if (
            current != null &&
            current.occurrenceId != request.occurrenceId &&
            occurrenceOwners[current.occurrenceId] ==
                (request.reservationId to request.wakePlanId)
        ) {
            occurrenceOwners.remove(current.occurrenceId)
        }
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
            val current = reservations[request.reservationId]
            if (current != null && current.wakePlanId != request.wakePlanId) {
                return@synchronized false
            }
            if (current == null || request.reservationGeneration >= current.reservationGeneration) {
                if (
                    current != null &&
                    current.occurrenceId != request.occurrenceId &&
                    occurrenceOwners[current.occurrenceId] ==
                        (request.reservationId to request.wakePlanId)
                ) {
                    occurrenceOwners.remove(current.occurrenceId)
                }
                occurrenceOwners[request.occurrenceId] =
                    request.reservationId to request.wakePlanId
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
        require(json.getInt("schemaVersion") == STORAGE_SCHEMA_VERSION) {
            "unsupported native reservation authority schema version"
        }
        val reservationsJson = json.getJSONObject("reservations")
        val reservations = linkedMapOf<String, ReservationAuthority>()
        val reservationKeys = reservationsJson.keys()
        while (reservationKeys.hasNext()) {
            val key = reservationKeys.next()
            val authority = ReservationAuthority.fromJson(reservationsJson.getJSONObject(key))
            require(authority.reservationId == key) {
                "reservation authority key does not match its reservationId"
            }
            require(reservations.put(key, authority) == null) {
                "duplicate reservation authority key: $key"
            }
        }
        val ownersJson = json.getJSONObject("occurrenceOwners")
        val occurrenceOwners = linkedMapOf<String, Pair<String, String>>()
        val ownerKeys = ownersJson.keys()
        while (ownerKeys.hasNext()) {
            val occurrenceId = ownerKeys.next()
            require(occurrenceId.isNotBlank()) { "occurrenceId key must not be blank" }
            val ownerJson = ownersJson.getJSONObject(occurrenceId)
            val owner = ownerJson.getString("reservationId") to
                ownerJson.getString("wakePlanId")
            require(owner.first.isNotBlank() && owner.second.isNotBlank()) {
                "occurrence owner reservationId/wakePlanId must not be blank"
            }
            require(occurrenceOwners.put(occurrenceId, owner) == null) {
                "duplicate occurrence owner key: $occurrenceId"
            }
        }
        reservations.values.forEach { authority ->
            require(
                occurrenceOwners[authority.occurrenceId] ==
                    (authority.reservationId to authority.wakePlanId),
            ) {
                "occurrence owner does not match reservation authority for ${authority.reservationId}"
            }
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
