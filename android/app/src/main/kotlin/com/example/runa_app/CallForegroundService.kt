package com.example.runa_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/// Foreground service that posts a `Notification.CallStyle` ongoing-call
/// notification. On HyperOS this is surfaced in the Dynamic Island / status-bar
/// call chip; on stock Android it shows the call template on the lock screen.
class CallForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "runa_ongoing_call"
        const val NOTIF_ID = 4711

        const val ACTION_START = "com.example.runa_app.action.START_CALL"
        const val ACTION_CONNECTED = "com.example.runa_app.action.CALL_CONNECTED"
        const val ACTION_STOP = "com.example.runa_app.action.STOP_CALL"
        const val ACTION_HANGUP = "com.example.runa_app.action.HANGUP_CALL"

        /// Broadcast emitted when the user taps "Hang up" on the notification.
        const val BROADCAST_HANGUP = "com.example.runa_app.CALL_HANGUP"

        const val EXTRA_NAME = "caller_name"
        const val EXTRA_CALL_ID = "call_id"
    }

    private var callerName: String = "Call"
    private var connected: Boolean = false
    private var connectedSince: Long = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                callerName = intent.getStringExtra(EXTRA_NAME) ?: "Call"
                connected = false
                startForegroundWithNotification()
            }
            ACTION_CONNECTED -> {
                if (!connected) {
                    connected = true
                    connectedSince = System.currentTimeMillis()
                }
                updateNotification()
            }
            ACTION_HANGUP -> {
                sendBroadcast(Intent(BROADCAST_HANGUP).setPackage(packageName))
                stopSelfAndRemove()
            }
            ACTION_STOP -> stopSelfAndRemove()
        }
        return START_NOT_STICKY
    }

    private fun stopSelfAndRemove() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    private fun notificationManager(): NotificationManager =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = notificationManager()
            if (mgr.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Ongoing calls",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Shows the active voice/video call"
                    setShowBadge(false)
                }
                mgr.createNotificationChannel(channel)
            }
        }
    }

    private fun contentIntent(): PendingIntent {
        val launch = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
        } ?: Intent()
        return PendingIntent.getActivity(
            this, 0, launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    private fun hangupIntent(): PendingIntent {
        val intent = Intent(this, CallForegroundService::class.java).setAction(ACTION_HANGUP)
        return PendingIntent.getService(
            this, 1, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    private fun buildNotification(): Notification {
        ensureChannel()
        val hangup = hangupIntent()
        val content = contentIntent()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val person = Person.Builder().setName(callerName).build()
            val style = Notification.CallStyle.forOngoingCall(person, hangup)
            val builder = Notification.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.mipmap.launcher_icon)
                .setStyle(style)
                .setContentIntent(content)
                .setOngoing(true)
                .setCategory(Notification.CATEGORY_CALL)
            if (connected) {
                builder.setUsesChronometer(true)
                builder.setWhen(connectedSince)
                builder.setShowWhen(true)
            } else {
                builder.setShowWhen(false)
            }
            return builder.build()
        }

        // Fallback for Android < 12: ongoing notification with a hang-up action.
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.launcher_icon)
            .setContentTitle(callerName)
            .setContentText(if (connected) "Ongoing call" else "Calling…")
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(content)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Hang up", hangup)
        if (connected) {
            builder.setUsesChronometer(true)
            builder.setWhen(connectedSince)
            builder.setShowWhen(true)
        }
        return builder.build()
    }

    private fun startForegroundWithNotification() {
        val notification = buildNotification()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIF_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                )
            } else {
                startForeground(NOTIF_ID, notification)
            }
        } catch (e: Exception) {
            // Android 14+ throws SecurityException when promoting a microphone-typed
            // FGS without RECORD_AUDIO granted; background starts can also be blocked.
            // The call works without this notification, so stop rather than crash.
            stopSelfAndRemove()
        }
    }

    private fun updateNotification() {
        notificationManager().notify(NOTIF_ID, buildNotification())
    }
}
