import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  final List<RTCIceCandidate> _pendingRemoteCandidates = [];

  StreamSubscription? _callSubscription;
  StreamSubscription? _candidatesSubscription;

  Future<List<Map<String, dynamic>>> _fetchIceServers() async {
    return Constants.iceServers;
  }

  Future<String> createCall({
    required String callerId,
    required String callerName,
    required String receiverId,
  }) async {
    final iceServers = await _fetchIceServers();
    peerConnection = await createPeerConnection({
      'iceServers': iceServers,
    });

    registerPeerConnectionListeners();

    localStream?.getTracks().forEach((track) {
      peerConnection?.addTrack(track, localStream!);
    });

    final callRef = await _firestore.collection('calls').add({
      'caller_id': callerId,
      'caller_name': callerName,
      'receiver_id': receiverId,
      'status': 'ringing',
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });

    roomId = callRef.id;

    peerConnection?.onIceCandidate = (RTCIceCandidate candidate) async {
      await callRef.collection('candidates').add({
        'role': 'caller',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
        'created_at': FieldValue.serverTimestamp(),
      });
    };

    final offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);

    await callRef.update({
      'offer': {'type': offer.type, 'sdp': offer.sdp},
    });

    _callSubscription = callRef.snapshots().listen((snapshot) async {
      if (!snapshot.exists) return;
      final data = snapshot.data() as Map<String, dynamic>;
      
      if (!_remoteDescriptionSet && data['answer'] != null) {
        _remoteDescriptionSet = true;
        final answer = data['answer'] as Map<String, dynamic>;
        try {
          await peerConnection?.setRemoteDescription(
            RTCSessionDescription(answer['sdp'] as String, answer['type'] as String),
          );
          await _flushPendingCandidates();
        } catch (e) {
          debugPrint('[Signaling] Error setting remote description: $e');
        }
      }
      final status = data['status'] as String?;
      if (status == 'active') onCallAccepted?.call();
      if (status == 'ended' || status == 'rejected') {
        onCallEnded?.call();
      }
    });

    _candidatesSubscription = callRef
        .collection('candidates')
        .where('role', isEqualTo: 'callee')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null) {
            _addOrQueueCandidate(RTCIceCandidate(
              data['candidate'] as String?,
              data['sdpMid'] as String?,
              data['sdpMLineIndex'] as int?,
            ));
          }
        }
      }
    });

    return roomId!;
  }

  Future<void> joinCall(String callId) async {
    roomId = callId;
    final callRef = _firestore.collection('calls').doc(callId);
    final callDoc = await callRef.get();

    if (!callDoc.exists) return;

    final iceServers = await _fetchIceServers();
    peerConnection = await createPeerConnection({
      'iceServers': iceServers,
    });

    registerPeerConnectionListeners();

    localStream?.getTracks().forEach((track) {
      peerConnection?.addTrack(track, localStream!);
    });

    peerConnection?.onIceCandidate = (RTCIceCandidate candidate) async {
      await callRef.collection('candidates').add({
        'role': 'callee',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
        'created_at': FieldValue.serverTimestamp(),
      });
    };

    final offer = callDoc.data()!['offer'] as Map<String, dynamic>;
    await peerConnection?.setRemoteDescription(
      RTCSessionDescription(offer['sdp'] as String, offer['type'] as String),
    );
    _remoteDescriptionSet = true;
    await _flushPendingCandidates();

    final answer = await peerConnection!.createAnswer();
    await peerConnection!.setLocalDescription(answer);

    await callRef.update({
      'answer': {'type': answer.type, 'sdp': answer.sdp},
      'status': 'active',
      'updated_at': FieldValue.serverTimestamp(),
    });

    _candidatesSubscription = callRef
        .collection('candidates')
        .where('role', isEqualTo: 'caller')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null) {
            _addOrQueueCandidate(RTCIceCandidate(
              data['candidate'] as String?,
              data['sdpMid'] as String?,
              data['sdpMLineIndex'] as int?,
            ));
          }
        }
      }
    });

    _callSubscription = callRef.snapshots().listen((snapshot) {
      if (!snapshot.exists) return;
      final status = snapshot.data()!['status'] as String?;
      if (status == 'ended') onCallEnded?.call();
    });
  }

  Stream<List<Map<String, dynamic>>> listenForIncomingCalls(String currentUid) {
    return _firestore
        .collection('calls')
        .where('receiver_id', isEqualTo: currentUid)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  Future<void> rejectCall(String callId) async {
    await _firestore.collection('calls').doc(callId).update({
      'status': 'rejected',
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _addOrQueueCandidate(RTCIceCandidate candidate) async {
    if (_remoteDescriptionSet) {
      try {
        await peerConnection?.addCandidate(candidate);
      } catch (e) {
        debugPrint('[Signaling] Error adding ICE candidate: $e');
      }
    } else {
      _pendingRemoteCandidates.add(candidate);
    }
  }

  Future<void> _flushPendingCandidates() async {
    if (_pendingRemoteCandidates.isEmpty) return;
    final pending = List<RTCIceCandidate>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidate in pending) {
      try {
        await peerConnection?.addCandidate(candidate);
      } catch (e) {
        debugPrint('[Signaling] Error flushing ICE candidate: $e');
      }
    }
  }

  void registerPeerConnectionListeners() {
    peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
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
    
    await peerConnection?.close();
    peerConnection = null;
    _remoteDescriptionSet = false;
    _pendingRemoteCandidates.clear();

    if (roomId != null) {
      try {
        await _firestore.collection('calls').doc(roomId!).update({
          'status': 'ended',
          'updated_at': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('[Signaling] Error during hangup cleanup: $e');
      }
    }

    _callSubscription?.cancel();
    _candidatesSubscription?.cancel();
  }
}
