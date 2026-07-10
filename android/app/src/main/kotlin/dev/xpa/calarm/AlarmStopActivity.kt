package dev.xpa.calarm

import android.app.Activity
import android.app.NotificationManager
import android.content.Intent
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
import java.text.DateFormat
import java.util.Date

class AlarmStopActivity : Activity() {
    private var platformAlarmId: String? = null
    private var alarmCleanedUp = false
    private var ringtone: Ringtone? = null
    private var isRinging = true
    private var titleView: TextView? = null
    private var actionButton: Button? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState != null) {
            isRinging = savedInstanceState.getBoolean(STATE_IS_RINGING)
            platformAlarmId = savedInstanceState.getString(STATE_PLATFORM_ALARM_ID)
        } else {
            isRinging = intent.action != AlarmIntents.ACTION_ALARM_SHOW
            platformAlarmId = intent.getStringExtra(AlarmIntents.EXTRA_PLATFORM_ALARM_ID)
        }
        if (isRinging) {
            configureRingingPresentation()
        } else {
            configureDetailPresentation()
        }

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(48, 48, 48, 48)
        }
        val title = TextView(this).apply {
            text = if (isRinging) "Calarm" else detailSummary()
            textSize = 28f
            gravity = Gravity.CENTER
        }
        titleView = title
        layout.addView(title)
        val button = Button(this).apply {
            text = if (isRinging) "Stop" else "Close"
            setOnClickListener {
                if (isRinging) {
                    cleanupAlarm()
                    finishAndRemoveTask()
                } else {
                    finish()
                }
            }
        }
        actionButton = button
        layout.addView(button)
        setContentView(layout)
        if (isRinging) {
            startAlarmSound()
        }
    }

    public override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action != AlarmIntents.ACTION_ALARM_STOP) return
        if (isRinging) return

        setIntent(intent)
        platformAlarmId = intent.getStringExtra(AlarmIntents.EXTRA_PLATFORM_ALARM_ID)

        isRinging = true
        configureRingingPresentation()
        titleView?.text = "Calarm"
        actionButton?.text = "Stop"
        startAlarmSound()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean(STATE_IS_RINGING, isRinging)
        outState.putString(STATE_PLATFORM_ALARM_ID, platformAlarmId)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        if (!isChangingConfigurations) {
            cleanupAlarm()
        }
        super.onDestroy()
    }

    private fun detailSummary(): String {
        val request = platformAlarmId?.let { AlarmStore(this).get(it) }
            ?: return "Calarm alarm scheduled\nDetails unavailable"
        val scheduledAt = DateFormat.getDateTimeInstance(
            DateFormat.MEDIUM,
            DateFormat.SHORT,
        ).format(Date(request.scheduledAtMillis))
        return "Calarm alarm scheduled\nWake plan: ${request.wakePlanId}\nScheduled: $scheduledAt"
    }

    private fun cleanupAlarm() {
        if (!isRinging) return
        val alarmId = platformAlarmId ?: return
        if (alarmCleanedUp) return

        alarmCleanedUp = true
        stopAlarmSound()
        getSystemService(NotificationManager::class.java).cancel(alarmId.hashCode())
        AlarmStore(this).remove(alarmId)
    }

    private fun configureRingingPresentation() {
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
    }

    private fun configureDetailPresentation() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(false)
            setTurnScreenOn(false)
        }
        window.clearFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
        )
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

    private companion object {
        const val STATE_IS_RINGING = "is_ringing"
        const val STATE_PLATFORM_ALARM_ID = "platform_alarm_id"
    }
}
