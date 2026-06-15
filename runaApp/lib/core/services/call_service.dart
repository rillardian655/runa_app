import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:runa_app/core/services/signaling_service.dart';

class CallService {
  final SignalingService signaling = SignalingService();
  RTCVideoRenderer localRenderer = RTCVideoRenderer();
  RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  bool isAudioOnly = true;

  Future<void> initRenderers() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
  }

  Future<void> openUserMedia() async {
    var stream = await navigator.mediaDevices.getUserMedia({
      'video': !isAudioOnly,
      'audio': true,
    });

    localRenderer.srcObject = stream;
    signaling.localStream = stream;

    signaling.onAddRemoteStream = (MediaStream stream) {
      remoteRenderer.srcObject = stream;
    };
  }

  Future<String> startCall() async {
    await openUserMedia();
    return await signaling.createRoom();
  }

  Future<void> joinCall(String roomId) async {
    await openUserMedia();
    await signaling.joinRoom(roomId);
  }

  Future<void> endCall() async {
    await signaling.hangUp();
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    await localRenderer.dispose();
    await remoteRenderer.dispose();
  }
}
