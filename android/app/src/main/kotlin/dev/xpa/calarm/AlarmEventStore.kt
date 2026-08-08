package dev.xpa.calarm

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import org.json.JSONObject

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
