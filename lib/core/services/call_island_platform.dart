import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Bridges Flutter call state to the native Android foreground service that
/// posts a `Notification.CallStyle` ongoing-call notification. HyperOS (and
/// stock Android) surface that notification in the Dynamic Island / status-bar
/// call chip and on the lock screen.
///
/// No-op on web and non-Android platforms.
class CallIslandPlatform {
  CallIslandPlatform._() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static final CallIslandPlatform instance = CallIslandPlatform._();

  static const MethodChannel _channel = MethodChannel('runa/call_island');

  /// Invoked when the user taps "Hang up" on the system call notification.
  VoidCallback? onHangup;

  bool get _supported => !kIsWeb && Platform.isAndroid;

  Future<void> startOngoingCall({
    required String callerName,
    required String callId,
    bool isVideo = false,
  }) async {
    if (!_supported) return;

    try {
      // Android 13+ requires runtime permission to post notifications.
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }

      await _channel.invokeMethod('startCall', {
        'callerName': callerName,
        'callId': callId,
        'isVideo': isVideo,
      });
    } catch (e, stackTrace) {
      debugPrint('[CallIsland] startCall failed: $e');
      debugPrint('[CallIsland] Stack: $stackTrace');
    }
  }

  /// Switch the notification from "calling" to a live, chronometer-backed
  /// ongoing call (the native side owns the ticking timer).
  Future<void> setCallConnected() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod('setConnected');
    } catch (e) {
      debugPrint('[CallIsland] setConnected failed: $e');
    }
  }

  Future<void> endOngoingCall() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod('endCall');
    } catch (e) {
      debugPrint('[CallIsland] endCall failed: $e');
    }
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onHangupFromNotification') {
      onHangup?.call();
    }
    return null;
  }
}
