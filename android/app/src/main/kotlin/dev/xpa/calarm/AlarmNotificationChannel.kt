package dev.xpa.calarm

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.RingtoneManager

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
