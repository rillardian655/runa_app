import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:runa_app/core/services/signaling_service.dart';

class CallService {
  final SignalingService signaling = SignalingService();
  RTCVideoRenderer localRenderer = RTCVideoRenderer();
  RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  bool isAudioOnly = true;
  bool isMuted = false;
  bool isSpeakerOn = false;

  Function()? onCallEnded;
  Function()? onCallAccepted;
  Function(RTCIceConnectionState)? onConnectionStateChanged;

  Future<void> initRenderers() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
  }

  Future<void> openUserMedia() async {
    try {
      var stream = await navigator.mediaDevices.getUserMedia({
        'video': !isAudioOnly,
        'audio': true,
      });

      localRenderer.srcObject = stream;
      signaling.localStream = stream;

      signaling.onAddRemoteStream = (MediaStream stream) {
        remoteRenderer.srcObject = stream;
      };

      signaling.onCallEnded = () {
        onCallEnded?.call();
      };

      signaling.onCallAccepted = () {
        onCallAccepted?.call();
      };

      signaling.onConnectionState = (RTCIceConnectionState state) {
        onConnectionStateChanged?.call(state);
      };
    } catch (e) {
      debugPrint('Error opening user media: $e');
      rethrow;
    }
  }

  /// Start a call TO another user. Returns the call room ID.
  Future<String> startCallToUser({
    required String callerId,
    required String callerName,
    required String receiverId,
  }) async {
    await openUserMedia();
    return await signaling.createCall(
      callerId: callerId,
      callerName: callerName,
      receiverId: receiverId,
    );
  }

  /// Answer an incoming call by joining the room.
  Future<void> answerCall(String callId) async {
    await openUserMedia();
    await signaling.joinCall(callId);
  }

  /// Toggle microphone mute.
  void toggleMute() {
    isMuted = !isMuted;
    signaling.localStream?.getAudioTracks().forEach((track) {
      track.enabled = !isMuted;
    });
  }

  /// Toggle speaker (on web this is a no-op, on mobile it switches audio route).
  void toggleSpeaker() {
    isSpeakerOn = !isSpeakerOn;
    // On mobile, this would use a platform channel to switch audio route.
    // On web, speaker is the default output.
    if (!kIsWeb) {
      signaling.localStream?.getAudioTracks().forEach((track) {
        // Helper.setSpeakerphoneOn(isSpeakerOn); // Requires platform-specific code
      });
    }
  }

  Future<void> endCall() async {
    await signaling.hangUp();
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    try {
      await localRenderer.dispose();
      await remoteRenderer.dispose();
    } catch (e) {
      debugPrint('Error disposing renderers: $e');
    }
  }
}
