import 'dart:io';
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
    try {
      await localRenderer.initialize();
      await remoteRenderer.initialize();
    } catch (e) {
      debugPrint('[CallService] Error initializing renderers: $e');
      rethrow;
    }
  }

  Future<void> openUserMedia() async {
    try {
      // On Android the audio session must be switched into communication mode
      // BEFORE the WebRTC session starts. Many OEM ROMs (Xiaomi/HyperOS) route
      // call audio nowhere otherwise — you hear nothing and the remote hears
      // nothing. This cannot be changed mid-call, so it must run here, before
      // createPeerConnection().
      if (!kIsWeb && Platform.isAndroid) {
        try {
          await Helper.setAndroidAudioConfiguration(
            AndroidAudioConfiguration.communication,
          );
        } catch (e) {
          debugPrint('[CallService] setAndroidAudioConfiguration failed: $e');
        }
      }

      debugPrint('[CallService] Requesting user media (audio: true, video: ${!isAudioOnly})');

      var stream = await navigator.mediaDevices.getUserMedia({
        'video': !isAudioOnly,
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
      });

      debugPrint('[CallService] Got media stream successfully');
      localRenderer.srcObject = stream;
      signaling.localStream = stream;

      signaling.onAddRemoteStream = (MediaStream stream) {
        debugPrint('[CallService] Remote stream received');
        remoteRenderer.srcObject = stream;
      };

      signaling.onCallEnded = () {
        debugPrint('[CallService] Call ended signal received');
        onCallEnded?.call();
      };

      signaling.onCallAccepted = () {
        debugPrint('[CallService] Call accepted signal received');
        onCallAccepted?.call();
      };

      signaling.onConnectionState = (RTCIceConnectionState state) {
        debugPrint('[CallService] Connection state changed: $state');
        onConnectionStateChanged?.call(state);
      };
    } catch (e, stackTrace) {
      debugPrint('[CallService] Error opening user media: $e');
      debugPrint('[CallService] Stack trace: $stackTrace');
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

  /// Toggle speaker between loudspeaker and earpiece (mobile only).
  void toggleSpeaker() {
    isSpeakerOn = !isSpeakerOn;
    _applySpeaker();
  }

  /// Apply the default audio route once the call connects: voice calls start on
  /// the earpiece, video calls on the loudspeaker. Also forces the route to be
  /// set explicitly so audio is guaranteed to reach an output device.
  void applyInitialAudioRoute() {
    isSpeakerOn = !isAudioOnly;
    _applySpeaker();
  }

  void _applySpeaker() {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    Helper.setSpeakerphoneOn(isSpeakerOn).catchError((Object e) {
      debugPrint('[CallService] setSpeakerphoneOn failed: $e');
    });
  }

  Future<void> endCall() async {
    debugPrint('[CallService] Ending call');
    try {
      await signaling.hangUp();
    } catch (e, stackTrace) {
      debugPrint('[CallService] Error during signaling hangup: $e');
      debugPrint('[CallService] Stack trace: $stackTrace');
    }
    
    try {
      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;
    } catch (e) {
      debugPrint('[CallService] Error clearing renderer srcObjects: $e');
    }
    
    try {
      await localRenderer.dispose();
    } catch (e) {
      debugPrint('[CallService] Error disposing local renderer: $e');
    }
    
    try {
      await remoteRenderer.dispose();
    } catch (e) {
      debugPrint('[CallService] Error disposing remote renderer: $e');
    }

    // Release the communication audio device so normal media playback resumes.
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await Helper.clearAndroidCommunicationDevice();
      } catch (e) {
        debugPrint('[CallService] clearAndroidCommunicationDevice failed: $e');
      }
    }

    debugPrint('[CallService] Call ended');
  }
}
