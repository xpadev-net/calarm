package dev.xpa.calarm

import android.app.Activity
import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
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
    private var ringtone: Ringtone? = null

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
        startAlarmSound()
    }

    override fun onDestroy() {
        cleanupAlarm()
        super.onDestroy()
    }

    private fun cleanupAlarm() {
        val alarmId = platformAlarmId ?: return
        if (alarmCleanedUp) return

        alarmCleanedUp = true
        stopAlarmSound()
        getSystemService(NotificationManager::class.java).cancel(alarmId.hashCode())
        AlarmStore(this).remove(alarmId)
    }

    private fun startAlarmSound() {
        val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        ringtone = RingtoneManager.getRingtone(this, alarmUri)?.apply {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                isLooping = true
            }
            play()
        }
    }

    private fun stopAlarmSound() {
        ringtone?.stop()
        ringtone = null
    }
}
