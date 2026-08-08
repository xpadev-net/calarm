package dev.xpa.calarm

import android.app.AlarmManager
import android.content.Context
import android.os.Build
import android.util.Log

object AlarmRestore {
    fun restore(context: Context) {
        restore(context, context.applicationContext)
    }

    fun restore(storageContext: Context, serviceContext: Context) {
        val appContext = serviceContext.applicationContext
        val alarmManager = appContext.getSystemService(AlarmManager::class.java)
        restoreInternal(storageContext, appContext) { request ->
            alarmManager.setAlarmClock(
                AlarmManager.AlarmClockInfo(
                    request.scheduledAtMillis,
                    AlarmIntents.showIntent(appContext, request.platformAlarmId),
                ),
                AlarmIntents.receiver(appContext, request.platformAlarmId),
            )
        }
    }

    internal fun restoreForTest(
        storageContext: Context,
        serviceContext: Context,
        schedule: (AlarmRequest) -> Unit,
    ) {
        restoreInternal(storageContext, serviceContext.applicationContext, schedule)
    }

    private fun restoreInternal(
        storageContext: Context,
        appContext: Context,
        schedule: (AlarmRequest) -> Unit,
    ) {
        AndroidAlarmMutationTransaction.run restore@ {
            val alarmManager = appContext.getSystemService(AlarmManager::class.java)
            val store = AlarmStore(storageContext)
            val replacementRecovery = AndroidAlarmReplacementRecovery.reconcile(
                storageContext,
                appContext,
            )
            if (!replacementRecovery.isSuccess) {
                Log.e(
                    TAG,
                    "Skipping native alarm restore because replacement recovery failed: " +
                        replacementRecovery.message,
                )
                return@restore
            }
            val now = System.currentTimeMillis()
            val requests = store.all()
            requests.forEach { request ->
                if (request.state != AlarmState.RINGING && request.scheduledAtMillis <= now) {
                    val platformAlarmId = request.platformAlarmId
                    if (now - request.scheduledAtMillis <= MISSED_ALARM_CATCH_UP_WINDOW_MILLIS) {
                        if (!store.markRinging(platformAlarmId)) {
                            // A concurrent broadcast delivery may have already claimed and rung
                            // this occurrence; only remove the row if it genuinely isn't there.
                            if (store.get(platformAlarmId)?.state != AlarmState.RINGING) {
                                Log.e(
                                    TAG,
                                    "Failed to deliver a missed native alarm; it was removed: " +
                                        platformAlarmId,
                                )
                                store.remove(platformAlarmId)
                            }
                        } else {
                            Log.w(
                                TAG,
                                "Delivering an alarm that was due while the device was off or " +
                                    "the app was killed instead of discarding it: $platformAlarmId",
                            )
                            if (!AlarmReceiver().deliverAlreadyRingingAlarm(appContext, store, request)) {
                                Log.e(
                                    TAG,
                                    "Failed to deliver a missed native alarm; it was removed: " +
                                        platformAlarmId,
                                )
                                store.remove(platformAlarmId)
                            }
                        }
                    } else {
                        Log.w(
                            TAG,
                            "Discarding a native alarm long overdue beyond the catch-up window: " +
                                platformAlarmId,
                        )
                        store.remove(platformAlarmId)
                    }
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
                Log.w(
                    TAG,
                    "Skipping restore of future native alarms because exact-alarm scheduling " +
                        "permission is missing; rows are kept for a permission-state retry.",
                )
                return@restore
            }
            requests.asSequence()
                .filter { it.state != AlarmState.RINGING && it.scheduledAtMillis > now }
                .forEach { request ->
                    try {
                        schedule(request)
                    } catch (error: RuntimeException) {
                        Log.w(
                            TAG,
                            "Failed to re-arm a future native alarm during restore; keeping " +
                                "the row for a later boot or permission-state retry: " +
                                request.platformAlarmId,
                            error,
                        )
                    }
                }
        }
    }

    private const val TAG = "CalarmAlarmRestore"
}
