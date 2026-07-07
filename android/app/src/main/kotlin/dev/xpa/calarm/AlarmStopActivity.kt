package dev.xpa.calarm

import android.app.Activity
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

class AlarmStopActivity : Activity() {
    private var platformAlarmId: String? = null
    private var alarmCleanedUp = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
        platformAlarmId = intent.getStringExtra(AlarmIntents.EXTRA_PLATFORM_ALARM_ID)

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(48, 48, 48, 48)
        }
        layout.addView(TextView(this).apply {
            text = "Calarm"
            textSize = 28f
            gravity = Gravity.CENTER
        })
        layout.addView(Button(this).apply {
            text = "Stop"
            setOnClickListener {
                cleanupAlarm()
                finishAndRemoveTask()
            }
        })
        setContentView(layout)
    }

    override fun onDestroy() {
        cleanupAlarm()
        super.onDestroy()
    }

    private fun cleanupAlarm() {
        val alarmId = platformAlarmId ?: return
        if (alarmCleanedUp) return

        alarmCleanedUp = true
        getSystemService(NotificationManager::class.java).cancel(alarmId.hashCode())
        AlarmStore(this).remove(alarmId)
    }
}
