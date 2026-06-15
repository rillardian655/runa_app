import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:runa_app/core/constants.dart';

class SignalingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  MediaStream? remoteStream;
  String? roomId;

  Function(MediaStream stream)? onAddRemoteStream;
  Function(RTCIceConnectionState state)? onConnectionState;
  Function()? onCallEnded;
  Function()? onCallAccepted;
  bool _remoteDescriptionSet = false;

  /// Creates a call room in Firestore and sets up WebRTC offer.
  /// Returns the roomId (call document ID).
  Future<String> createCall({
    required String callerId,
    required String callerName,
    required String receiverId,
  }) async {
    peerConnection = await createPeerConnection({
      'iceServers': Constants.iceServers,
    });

    registerPeerConnectionListeners();

    localStream?.getTracks().forEach((track) {
      peerConnection?.addTrack(track, localStream!);
    });

    final roomRef = _firestore.collection('calls').doc();
    final callerCandidatesCollection = roomRef.collection('callerCandidates');

    peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      callerCandidatesCollection.add(candidate.toMap());
    };

    RTCSessionDescription offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);

    await roomRef.set({
      'offer': offer.toMap(),
      'callerId': callerId,
      'callerName': callerName,
      'receiverId': receiverId,
      'status': 'ringing', // ringing → active → ended / rejected
      'timestamp': FieldValue.serverTimestamp(),
    });

    roomId = roomRef.id;

    // Listen for answer from callee
    roomRef.snapshots().listen((snapshot) async {
      if (snapshot.exists) {
        Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;
        
        // If callee answered, set remote description
        if (!_remoteDescriptionSet && data['answer'] != null) {
          _remoteDescriptionSet = true;
          var answer = RTCSessionDescription(
            data['answer']['sdp'],
            data['answer']['type'],
          );
          await peerConnection?.setRemoteDescription(answer);
          debugPrint('Caller: Remote description set from answer');
        }

        // If status changed to active (callee accepted)
        if (data['status'] == 'active') {
          onCallAccepted?.call();
        }

        // If call was rejected or ended by the other side
        if (data['status'] == 'ended' || data['status'] == 'rejected') {
          onCallEnded?.call();
        }
      }
    });

    // Listen for callee ICE candidates
    roomRef.collection('calleeCandidates').snapshots().listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          Map<String, dynamic> data = change.doc.data() as Map<String, dynamic>;
          peerConnection!.addCandidate(
            RTCIceCandidate(data['candidate'], data['sdpMid'], data['sdpMLineIndex']),
          );
        }
      }
    });

    return roomId!;
  }

  /// Called by callee to accept and join a call room.
  Future<void> joinCall(String callId) async {
    roomId = callId;
    final roomRef = _firestore.collection('calls').doc(callId);
    var roomSnapshot = await roomRef.get();

    if (roomSnapshot.exists) {
      peerConnection = await createPeerConnection({
        'iceServers': Constants.iceServers,
      });

      registerPeerConnectionListeners();

      localStream?.getTracks().forEach((track) {
        peerConnection?.addTrack(track, localStream!);
      });

      var calleeCandidatesCollection = roomRef.collection('calleeCandidates');
      peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        calleeCandidatesCollection.add(candidate.toMap());
      };

      var data = roomSnapshot.data() as Map<String, dynamic>;
      var offer = data['offer'];
      await peerConnection?.setRemoteDescription(
        RTCSessionDescription(offer['sdp'], offer['type']),
      );

      var answer = await peerConnection!.createAnswer();
      await peerConnection!.setLocalDescription(answer);

      await roomRef.update({
        'answer': {'type': answer.type, 'sdp': answer.sdp},
        'status': 'active',
      });

      // Listen for caller ICE candidates
      roomRef.collection('callerCandidates').snapshots().listen((snapshot) {
        for (var document in snapshot.docChanges) {
          if (document.type == DocumentChangeType.added) {
            var data = document.doc.data() as Map<String, dynamic>;
            peerConnection!.addCandidate(
              RTCIceCandidate(data['candidate'], data['sdpMid'], data['sdpMLineIndex']),
            );
          }
        }
      });

      // Listen for hang up from the other side
      roomRef.snapshots().listen((snapshot) {
        if (snapshot.exists) {
          final data = snapshot.data() as Map<String, dynamic>;
          if (data['status'] == 'ended') {
            onCallEnded?.call();
          }
        }
      });
    }
  }

  /// Listen for incoming calls for a specific user.
  Stream<QuerySnapshot> listenForIncomingCalls(String currentUid) {
    return _firestore
        .collection('calls')
        .where('receiverId', isEqualTo: currentUid)
        .where('status', isEqualTo: 'ringing')
        .snapshots();
  }

  /// Reject an incoming call.
  Future<void> rejectCall(String callId) async {
    await _firestore.collection('calls').doc(callId).update({
      'status': 'rejected',
    });
  }

  void registerPeerConnectionListeners() {
    peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
      debugPrint('ICE connection state: $state');
      onConnectionState?.call(state);
    };

    peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        remoteStream = event.streams[0];
        onAddRemoteStream?.call(remoteStream!);
      }
    };
  }

  Future<void> hangUp() async {
    localStream?.getTracks().forEach((track) => track.stop());
    remoteStream?.getTracks().forEach((track) => track.stop());
    peerConnection?.close();
    peerConnection = null;
    _remoteDescriptionSet = false;

    if (roomId != null) {
      try {
        var roomRef = _firestore.collection('calls').doc(roomId);
        // Set status to ended
        await roomRef.update({'status': 'ended'});
        
        // Clean up ICE candidates
        var calleeCandidates = await roomRef.collection('calleeCandidates').get();
        for (var document in calleeCandidates.docs) {
          document.reference.delete();
        }
        var callerCandidates = await roomRef.collection('callerCandidates').get();
        for (var document in callerCandidates.docs) {
          document.reference.delete();
        }
      } catch (e) {
        debugPrint('Error during hangup cleanup: $e');
      }
    }
  }
}
