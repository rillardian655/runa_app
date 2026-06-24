import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:runa_app/core/services/call_island_platform.dart';
import 'package:runa_app/core/services/call_service.dart';

enum CallPhase { idle, ringing, connecting, connected, ended }

/// Owns the single active call so it can outlive [CallScreen]. Both the in-app
/// Dynamic Island and the native call notification observe this controller, and
/// the duration timer lives here so the call keeps running while minimized.
class CallSessionController extends ChangeNotifier {
  CallSessionController._();
  static final CallSessionController instance = CallSessionController._();

  CallService? _service;
  CallService? get service => _service;

  String callId = '';
  String currentUserId = '';
  String currentUserName = '';
  String friendUserId = '';
  String friendName = '';
  bool isIncoming = false;
  bool isVideo = false;

  CallPhase _phase = CallPhase.idle;
  CallPhase get phase => _phase;

  bool get hasActiveCall =>
      _phase != CallPhase.idle && _phase != CallPhase.ended;
  bool get isConnected => _phase == CallPhase.connected;

  bool _muted = false;
  bool get isMuted => _muted;

  bool _speakerOn = false;
  bool get isSpeakerOn => _speakerOn;

  /// True when the user has collapsed the call into the island.
  bool _minimized = false;
  bool get isMinimized => _minimized;

  Timer? _timer;
  int _durationSeconds = 0;
  int get durationSeconds => _durationSeconds;

  String? _error;
  String? get error => _error;

  String get formattedDuration {
    final m = (_durationSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_durationSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get statusLabel {
    switch (_phase) {
      case CallPhase.ringing:
        return isIncoming ? 'Answering…' : 'Ringing…';
      case CallPhase.connecting:
        return 'Connecting…';
      case CallPhase.connected:
        return formattedDuration;
      case CallPhase.ended:
        return 'Call ended';
      case CallPhase.idle:
        return '';
    }
  }

  Future<void> start({
    required String callId,
    required String currentUserId,
    required String currentUserName,
    required String friendUserId,
    required String friendName,
    required bool isIncoming,
    bool isVideo = false,
  }) async {
    // Only one concurrent call is supported.
    if (hasActiveCall) {
      debugPrint('[CallSession] Already has active call, ignoring start request');
      return;
    }

    debugPrint('[CallSession] Starting call: isIncoming=$isIncoming, isVideo=$isVideo');

    this.callId = callId;
    this.currentUserId = currentUserId;
    this.currentUserName = currentUserName;
    this.friendUserId = friendUserId;
    this.friendName = friendName;
    this.isIncoming = isIncoming;
    this.isVideo = isVideo;
    _muted = false;
    _speakerOn = false;
    _minimized = false;
    _durationSeconds = 0;
    _error = null;
    _phase = CallPhase.connecting;
    notifyListeners();

    CallService? service;
    try {
      service = CallService()..isAudioOnly = !isVideo;
      _service = service;

      service.onCallEnded = () => end();
      service.onCallAccepted = _handleConnected;
      service.onConnectionStateChanged = (state) {
        debugPrint('[CallSession] Connection state: $state');
        switch (state) {
          case RTCIceConnectionState.RTCIceConnectionStateConnected:
          case RTCIceConnectionState.RTCIceConnectionStateCompleted:
            _handleConnected();
            break;
          case RTCIceConnectionState.RTCIceConnectionStateFailed:
          case RTCIceConnectionState.RTCIceConnectionStateClosed:
            end();
            break;
          default:
            break;
        }
      };

      CallIslandPlatform.instance.onHangup = () => end();

      // Request permissions BEFORE starting the ongoing-call foreground service.
      // On Android 14+ a microphone-typed foreground service throws
      // SecurityException (a hard crash) unless RECORD_AUDIO is already granted,
      // so the permission request must complete first.
      // Skip on Linux and web (they handle permissions differently).
      if (!kIsWeb && !Platform.isLinux) {
        debugPrint('[CallSession] Requesting permissions on mobile');
        final required = isVideo
            ? [Permission.microphone, Permission.camera]
            : [Permission.microphone];
        final statuses = await required.request();
        debugPrint('[CallSession] Permission statuses: $statuses');
        if (statuses[Permission.microphone] != PermissionStatus.granted) {
          throw Exception('Microphone permission is required to call');
        }
      }

      await CallIslandPlatform.instance.startOngoingCall(
        callerName: friendName,
        callId: callId,
        isVideo: isVideo,
      );

      debugPrint('[CallSession] Initializing renderers');
      await service.initRenderers();
      
      _phase = isIncoming ? CallPhase.connecting : CallPhase.ringing;
      notifyListeners();

      if (isIncoming) {
        debugPrint('[CallSession] Answering incoming call: $callId');
        await service.answerCall(callId);
      } else {
        debugPrint('[CallSession] Starting outgoing call to: $friendUserId');
        final createdId = await service.startCallToUser(
          callerId: currentUserId,
          callerName: currentUserName,
          receiverId: friendUserId,
        );
        this.callId = createdId;
        debugPrint('[CallSession] Call created with ID: $createdId');
      }
    } catch (e, stackTrace) {
      _error = '$e';
      debugPrint('[CallSession] start error: $e');
      debugPrint('[CallSession] Stack trace: $stackTrace');
      await end();
    }
  }

  void _handleConnected() {
    if (_phase == CallPhase.connected) return;
    _phase = CallPhase.connected;
    // Force the audio route now that media is flowing (earpiece for voice,
    // loudspeaker for video) so the call is audible on every device.
    _service?.applyInitialAudioRoute();
    _speakerOn = _service?.isSpeakerOn ?? _speakerOn;
    _startTimer();
    CallIslandPlatform.instance.setCallConnected();
    notifyListeners();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _durationSeconds++;
      notifyListeners();
    });
  }

  void toggleMute() {
    _service?.toggleMute();
    _muted = _service?.isMuted ?? _muted;
    notifyListeners();
  }

  void toggleSpeaker() {
    _service?.toggleSpeaker();
    _speakerOn = _service?.isSpeakerOn ?? _speakerOn;
    notifyListeners();
  }

  void minimize() {
    if (_minimized) return;
    _minimized = true;
    notifyListeners();
  }

  void maximize() {
    if (!_minimized) return;
    _minimized = false;
    notifyListeners();
  }

  bool _ending = false;

  Future<void> end() async {
    if (_ending) {
      debugPrint('[CallSession] Already ending, ignoring end request');
      return;
    }
    _ending = true;
    debugPrint('[CallSession] Ending call');

    _timer?.cancel();
    _timer = null;
    _phase = CallPhase.ended;
    notifyListeners();

    try {
      if (_service != null) {
        debugPrint('[CallSession] Ending call service');
        await _service!.endCall();
      }
    } catch (e, stackTrace) {
      debugPrint('[CallSession] end error: $e');
      debugPrint('[CallSession] Stack trace: $stackTrace');
    }
    _service = null;

    try {
      CallIslandPlatform.instance.onHangup = null;
      await CallIslandPlatform.instance.endOngoingCall();
    } catch (e) {
      debugPrint('[CallSession] Error ending ongoing call: $e');
    }

    _phase = CallPhase.idle;
    _minimized = false;
    _durationSeconds = 0;
    _muted = false;
    _speakerOn = false;
    callId = '';
    friendName = '';
    _error = null;
    _ending = false;
    notifyListeners();
    debugPrint('[CallSession] Call ended successfully');
  }
}
