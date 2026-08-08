package dev.xpa.calarm

import android.content.Context
import android.os.Build
import org.json.JSONObject

internal class AlarmActivationCleanupStore(context: Context) {
    private val preferences = (if (
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && !context.isDeviceProtectedStorage
    ) {
        context.createDeviceProtectedStorageContext()
    } else {
        context
    }).getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    fun load(): AlarmRequest? = synchronized(lock) {
        val value = preferences.getString(JOURNAL_KEY, null) ?: return@synchronized null
        val json = JSONObject(value)
        require(json.getInt("schemaVersion") == STORAGE_SCHEMA_VERSION)
        AlarmRequest.fromJson(json.getJSONObject("request"))
    }

    fun save(request: AlarmRequest): Boolean = synchronized(lock) {
        if (preferences.contains(JOURNAL_KEY)) return@synchronized false
        val encoded = JSONObject()
            .put("schemaVersion", STORAGE_SCHEMA_VERSION)
            .put("request", request.toJson())
            .toString()
        preferences.edit().putString(JOURNAL_KEY, encoded).commit()
    }

    fun clear(): Boolean = synchronized(lock) {
        preferences.edit().remove(JOURNAL_KEY).commit()
    }

    private companion object {
        const val PREFERENCES_NAME = "native_alarm_activation_cleanup"
        const val JOURNAL_KEY = "active"
        const val STORAGE_SCHEMA_VERSION = 1
        val lock = Any()
    }
}
