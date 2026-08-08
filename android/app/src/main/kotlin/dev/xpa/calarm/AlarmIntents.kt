package dev.xpa.calarm

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri

object AlarmIntents {
    const val EXTRA_PLATFORM_ALARM_ID = "platformAlarmId"
    const val EXTRA_OCCURRENCE_ID = "occurrenceId"
    const val ACTION_ALARM_FIRE = "dev.xpa.calarm.ALARM_FIRE"
    const val ACTION_ALARM_STOP = "dev.xpa.calarm.ALARM_STOP"
    const val ACTION_ALARM_SHOW = "dev.xpa.calarm.ALARM_SHOW"

    fun receiver(context: Context, platformAlarmId: String): PendingIntent {
        val intent = Intent(context, AlarmReceiver::class.java)
            .setAction(ACTION_ALARM_FIRE)
            .setData(identityUri(platformAlarmId))
            .putExtra(EXTRA_PLATFORM_ALARM_ID, platformAlarmId)
        return PendingIntent.getBroadcast(
            context,
            requestCode(platformAlarmId),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun existingReceiver(context: Context, platformAlarmId: String): PendingIntent? {
        val intent = Intent(context, AlarmReceiver::class.java)
            .setAction(ACTION_ALARM_FIRE)
            .setData(identityUri(platformAlarmId))
            .putExtra(EXTRA_PLATFORM_ALARM_ID, platformAlarmId)
        return PendingIntent.getBroadcast(
            context,
            requestCode(platformAlarmId),
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun stopActivity(context: Context, platformAlarmId: String): PendingIntent {
        val intent = stopActivityIntent(context, platformAlarmId)
        return PendingIntent.getActivity(
            context,
            requestCode(platformAlarmId),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun showIntent(context: Context, platformAlarmId: String): PendingIntent {
        val intent = Intent(context, AlarmStopActivity::class.java)
            .setAction(ACTION_ALARM_SHOW)
            .setData(identityUri(platformAlarmId))
            .putExtra(EXTRA_PLATFORM_ALARM_ID, platformAlarmId)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            context,
            requestCode(platformAlarmId),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun stopActivityIntent(context: Context, platformAlarmId: String): Intent {
        return Intent(context, AlarmStopActivity::class.java)
            .setAction(ACTION_ALARM_STOP)
            .setData(identityUri(platformAlarmId))
            .putExtra(EXTRA_PLATFORM_ALARM_ID, platformAlarmId)
            .addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
    }

    private fun requestCode(platformAlarmId: String): Int {
        return platformAlarmId.hashCode()
    }

    private fun identityUri(platformAlarmId: String): Uri {
        return Uri.Builder()
            .scheme("calarm")
            .authority("native-alarm")
            .appendPath(platformAlarmId)
            .build()
    }
}
