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
import android.util.Log
import java.text.DateFormat
import java.util.Date

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val platformAlarmId = intent.getStringExtra(AlarmIntents.EXTRA_PLATFORM_ALARM_ID) ?: return
        val store = AlarmStore(context)
        val request = store.get(platformAlarmId)
        if (request == null) return
        if (
            request.platformAlarmId != platformAlarmId ||
            !request.hasCanonicalPlatformAlarmId()
        ) return
        if (!store.markRinging(platformAlarmId)) return
        deliverAlarm(
            store = store,
            platformAlarmId = platformAlarmId,
            notification = {
                showAlarmNotification(
                    context,
                    platformAlarmId,
                    request,
                    store.nextScheduledAfter(
                        request.wakePlanId,
                        request.scheduledAtMillis,
                    ),
                )
            },
            screen = { openAlarmScreen(context, platformAlarmId) },
            vibration = if (request.vibrationEnabled) ({ vibrate(context) }) else null,
            recordDelivered = {
                if (!AlarmEventStore(context).appendDelivered(platformAlarmId, System.currentTimeMillis())) {
                    Log.e(TAG, "Failed to persist a delivered native alarm event.")
                }
            },
        )
    }

    internal fun deliverAlarm(
        store: AlarmStore,
        platformAlarmId: String,
        notification: () -> Unit,
        screen: () -> Unit,
        vibration: (() -> Unit)?,
        recordDelivered: () -> Unit = {},
    ): Boolean {
        if (deliverFallbacks(notification, screen, vibration, recordDelivered)) return true
        if (!store.remove(platformAlarmId)) {
            Log.e(TAG, "Failed to remove an undeliverable ringing alarm from native storage.")
        }
        return false
    }

    internal fun deliverFallbacks(
        notification: () -> Unit,
        screen: () -> Unit,
        vibration: (() -> Unit)?,
        recordFirstDelivery: () -> Unit = {},
    ): Boolean {
        var delivered = false
        fun markDelivered() {
            if (delivered) return
            delivered = true
            recordFirstDelivery()
        }
        try {
            notification()
            markDelivered()
        } catch (error: SecurityException) {
            Log.w(TAG, "Notification permission was revoked while delivering an alarm.", error)
        } catch (error: RuntimeException) {
            Log.w(TAG, "Alarm notification delivery failed.", error)
        }
        try {
            screen()
            markDelivered()
        } catch (error: SecurityException) {
            Log.w(TAG, "Full-screen alarm access was revoked while delivering an alarm.", error)
        } catch (error: RuntimeException) {
            Log.w(TAG, "Alarm screen delivery failed.", error)
        }
        if (vibration != null) {
            try {
                vibration()
                markDelivered()
            } catch (error: SecurityException) {
                Log.w(TAG, "Vibration permission was unavailable while delivering an alarm.", error)
            } catch (error: RuntimeException) {
                Log.w(TAG, "Alarm vibration failed.", error)
            }
        }
        return delivered
    }

    private fun showAlarmNotification(
        context: Context,
        platformAlarmId: String,
        request: AlarmRequest,
        nextAlarm: AlarmRequest?,
    ) {
        val notificationManager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationManager.createNotificationChannel(AlarmNotificationChannel.create())
        }

        val stopIntent = AlarmIntents.stopActivity(context, platformAlarmId)
        val timeFormat = DateFormat.getTimeInstance(DateFormat.SHORT)
        val scheduledTime = timeFormat.format(Date(request.scheduledAtMillis))
        val targetTime = timeFormat.format(Date(request.targetAtMillis))
        val privateText = buildString {
            append("Scheduled: $scheduledTime\nWake target: $targetTime")
            request.positionLabel()?.let { append("\n$it") }
            nextAlarm?.let {
                append("\nNext alarm: ${timeFormat.format(Date(it.scheduledAtMillis))}")
            }
        }
        val publicNotification = notificationBuilder(context)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Wake alarm")
            .setContentText("Alarm is ringing")
            .setPriority(Notification.PRIORITY_MAX)
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(stopIntent)
            .setOngoing(true)
            .setAutoCancel(false)
            .build()
        val notification = notificationBuilder(context)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Wake alarm ringing now")
            .setContentText("Scheduled $scheduledTime · wake target $targetTime")
            .setStyle(Notification.BigTextStyle().bigText(privateText))
            .setPriority(Notification.PRIORITY_MAX)
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(publicNotification)
            .setFullScreenIntent(stopIntent, true)
            .setContentIntent(stopIntent)
            .setWhen(System.currentTimeMillis())
            .setShowWhen(true)
            .setOngoing(true)
            .setAutoCancel(false)
            .build()

        notificationManager.notify(platformAlarmId.hashCode(), notification)
    }

    private fun notificationBuilder(context: Context): Notification.Builder {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, AlarmNotificationChannel.ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
    }

    private fun openAlarmScreen(context: Context, platformAlarmId: String) {
        context.startActivity(AlarmIntents.stopActivityIntent(context, platformAlarmId))
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

    private companion object {
        const val TAG = "CalarmAlarmReceiver"
    }
}
