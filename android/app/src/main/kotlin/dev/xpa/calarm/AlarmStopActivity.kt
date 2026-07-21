package dev.xpa.calarm

import android.app.Activity
import android.app.NotificationManager
import android.content.Intent
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
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
    private var vibrator: Vibrator? = null
    private var isRinging = true
    private var titleView: TextView? = null
    private var currentTimeView: TextView? = null
    private var actionButton: Button? = null
    private var contentLayout: LinearLayout? = null
    private val clockHandler = Handler(Looper.getMainLooper())
    private val clockTick = object : Runnable {
        override fun run() {
            updateCurrentTime()
            clockHandler.postDelayed(this, CLOCK_TICK_MILLIS)
        }
    }

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
        if (isRinging) {
            val currentTime = TextView(this).apply {
                textSize = 20f
                gravity = Gravity.CENTER
            }
            currentTimeView = currentTime
            layout.addView(currentTime)

            val info = TextView(this).apply {
                text = ringingSummary()
                textSize = 24f
                gravity = Gravity.CENTER
            }
            titleView = info
            layout.addView(info)
        } else {
            val title = TextView(this).apply {
                text = detailSummary()
                textSize = 28f
                gravity = Gravity.CENTER
            }
            titleView = title
            layout.addView(title)
        }
        val button = Button(this).apply {
            text = if (isRinging) "Stop current alarm" else "Close"
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
        contentLayout = layout
        setContentView(layout)
        if (isRinging) {
            startAlarmSound()
            startClockTick()
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
        if (currentTimeView == null) {
            val currentTime = TextView(this).apply {
                textSize = 20f
                gravity = Gravity.CENTER
            }
            currentTimeView = currentTime
            contentLayout?.addView(currentTime, 0)
        }
        titleView?.text = ringingSummary()
        actionButton?.text = "Stop current alarm"
        startAlarmSound()
        startClockTick()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean(STATE_IS_RINGING, isRinging)
        outState.putString(STATE_PLATFORM_ALARM_ID, platformAlarmId)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        stopClockTick()
        if (isChangingConfigurations) {
            stopAlarmSound()
        } else {
            cleanupAlarm()
        }
        super.onDestroy()
    }

    private fun ringingSummary(): String {
        val request = platformAlarmId?.let { AlarmStore(this).get(it) }
            ?: return "Wake alarm"
        val timeFormat = DateFormat.getTimeInstance(DateFormat.SHORT)
        val scheduledTime = timeFormat.format(Date(request.scheduledAtMillis))
        val targetTime = timeFormat.format(Date(request.targetAtMillis))
        val nextAlarm = AlarmStore(this)
            .nextScheduledAfter(
                request.wakePlanId,
                maxOf(request.scheduledAtMillis, System.currentTimeMillis()),
            )
        return buildString {
            append("Wake alarm\n")
            append("Scheduled: $scheduledTime\n")
            append("Wake target: $targetTime")
            request.positionLabel()?.let { append("\n$it") }
            nextAlarm?.let {
                append("\nNext alarm: ${timeFormat.format(Date(it.scheduledAtMillis))}")
            }
        }
    }

    private fun updateCurrentTime() {
        val time = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date())
        currentTimeView?.text = "Current time: $time"
    }

    private fun startClockTick() {
        clockHandler.removeCallbacks(clockTick)
        updateCurrentTime()
        clockHandler.postDelayed(clockTick, CLOCK_TICK_MILLIS)
    }

    private fun stopClockTick() {
        clockHandler.removeCallbacks(clockTick)
    }

    private fun detailSummary(): String {
        val request = platformAlarmId?.let { AlarmStore(this).get(it) }
            ?: return "Calarm alarm scheduled\nDetails unavailable"
        val dateTimeFormat = DateFormat.getDateTimeInstance(
            DateFormat.MEDIUM,
            DateFormat.SHORT,
        )
        val scheduledAt = dateTimeFormat.format(Date(request.scheduledAtMillis))
        val targetAt = dateTimeFormat.format(Date(request.targetAtMillis))
        return buildString {
            append("Calarm alarm scheduled\n")
            append("Scheduled: $scheduledAt\n")
            append("Wake target: $targetAt")
            request.positionLabel()?.let { append("\n$it") }
        }
    }

    private fun cleanupAlarm() {
        if (!isRinging) return
        if (alarmCleanedUp) return

        alarmCleanedUp = true
        stopClockTick()
        stopAlarmSound()
        val alarmId = platformAlarmId ?: return
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
        startVibration()
    }

    private fun stopAlarmSound() {
        ringtone?.stop()
        ringtone = null
        stopVibration()
    }

    private fun startVibration() {
        stopVibration()
        val alarmId = platformAlarmId ?: return
        val request = AlarmStore(this).get(alarmId) ?: return
        if (!request.vibrationEnabled) return

        val alarmVibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Vibrator::class.java)
        }
        vibrator = alarmVibrator
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val effect = VibrationEffect.createWaveform(longArrayOf(0, 800, 400), 0)
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .build()
            alarmVibrator.vibrate(effect, attributes)
        } else {
            @Suppress("DEPRECATION")
            alarmVibrator.vibrate(longArrayOf(0, 800, 400), 0)
        }
    }

    private fun stopVibration() {
        vibrator?.cancel()
        vibrator = null
    }

    private fun AlarmRequest.positionLabel(): String? {
        val index = indexInPlan ?: return null
        val total = totalInPlan ?: return null
        return "Alarm ${index + 1} of $total"
    }

    private companion object {
        const val STATE_IS_RINGING = "is_ringing"
        const val STATE_PLATFORM_ALARM_ID = "platform_alarm_id"
        const val CLOCK_TICK_MILLIS = 60_000L
    }
}
