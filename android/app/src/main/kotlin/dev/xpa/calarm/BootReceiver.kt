package dev.xpa.calarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.app.AlarmManager
import android.os.Build
import android.os.UserManager

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED,
            -> AlarmRestore.restore(
                restoreContext(context, intent.action),
                context.applicationContext,
            )
        }
    }

    private fun restoreContext(context: Context, action: String?): Context {
        return if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
                (action == Intent.ACTION_LOCKED_BOOT_COMPLETED || !isUserUnlocked(context))
        ) {
            context.createDeviceProtectedStorageContext()
        } else {
            context
        }
    }

    private fun isUserUnlocked(context: Context): Boolean {
        return context.getSystemService(UserManager::class.java)?.isUserUnlocked != false
    }
}
