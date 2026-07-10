package dev.xpa.calarm

import android.app.Notification
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val platformAlarmId = intent.getStringExtra(AlarmIntents.EXTRA_PLATFORM_ALARM_ID) ?: return
        val store = AlarmStore(context)
        val request = store.get(platformAlarmId)
        if (request == null && !store.contains(platformAlarmId)) return
        showAlarmNotification(context, platformAlarmId)
        openAlarmScreen(context, platformAlarmId)
        if (request?.vibrationEnabled == true) {
            vibrate(context)
        }
    }

    private fun showAlarmNotification(context: Context, platformAlarmId: String) {
        val notificationManager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationManager.createNotificationChannel(AlarmNotificationChannel.create())
        }

        val stopIntent = AlarmIntents.stopActivity(context, platformAlarmId)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, AlarmNotificationChannel.ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Calarm")
            .setContentText("Wake alarm")
            .setPriority(Notification.PRIORITY_MAX)
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setFullScreenIntent(stopIntent, true)
            .setContentIntent(stopIntent)
            .setOngoing(true)
            .setAutoCancel(false)
            .build()

        notificationManager.notify(platformAlarmId.hashCode(), notification)
    }

    private fun openAlarmScreen(context: Context, platformAlarmId: String) {
        try {
            context.startActivity(AlarmIntents.stopActivityIntent(context, platformAlarmId))
        } catch (_: RuntimeException) {
            // Keep the full-screen notification pending intent as the supported
            // fallback when the OS blocks a background activity launch.
        }
    }

    private fun vibrate(context: Context) {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Vibrator::class.java)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createOneShot(1_000, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(1_000)
        }
    }
}
