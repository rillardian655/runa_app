package com.example.runa_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "runa/call_island"
    private var channel: MethodChannel? = null

    private val hangupReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            channel?.invokeMethod("onHangupFromNotification", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "startCall" -> {
                    val name = call.argument<String>("callerName") ?: "Call"
                    val callId = call.argument<String>("callId") ?: ""
                    val intent = Intent(this, CallForegroundService::class.java).apply {
                        action = CallForegroundService.ACTION_START
                        putExtra(CallForegroundService.EXTRA_NAME, name)
                        putExtra(CallForegroundService.EXTRA_CALL_ID, callId)
                    }
                    startCallService(intent, foreground = true)
                    result.success(null)
                }
                "setConnected" -> {
                    startCallService(
                        Intent(this, CallForegroundService::class.java)
                            .setAction(CallForegroundService.ACTION_CONNECTED),
                        foreground = false
                    )
                    result.success(null)
                }
                "endCall" -> {
                    startCallService(
                        Intent(this, CallForegroundService::class.java)
                            .setAction(CallForegroundService.ACTION_STOP),
                        foreground = false
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        registerHangupReceiver()
    }

    /// `foreground = true` (call start) must use startForegroundService so the
    /// service may promote itself. Update/stop target an already-running service
    /// and can fail harmlessly if the app is backgrounded, so they're guarded.
    private fun startCallService(intent: Intent, foreground: Boolean) {
        try {
            if (foreground && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) {
            // Background-start restrictions can throw; the service is already
            // gone in the stop/update cases, so this is safe to ignore.
        }
    }

    private fun registerHangupReceiver() {
        val filter = IntentFilter(CallForegroundService.BROADCAST_HANGUP)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(hangupReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(hangupReceiver, filter)
        }
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(hangupReceiver)
        } catch (_: Exception) {
        }
        super.onDestroy()
    }
}
