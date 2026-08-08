package dev.xpa.calarm

import android.content.Context
import java.security.MessageDigest
import java.time.Instant
import org.json.JSONObject

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
