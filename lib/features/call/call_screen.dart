import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:runa_app/core/services/call_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class CallScreen extends StatefulWidget {
  final String callId;        // Firestore doc ID (for incoming) or empty for outgoing
  final String currentUserId;
  final String currentUserName;
  final String friendUserId;
  final String friendName;
  final bool isIncoming;

  const CallScreen({
    super.key,
    required this.callId,
    required this.currentUserId,
    required this.currentUserName,
    required this.friendUserId,
    required this.friendName,
    required this.isIncoming,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final CallService _callService = CallService();
  String _callStatus = 'Connecting...';
  bool _isMuted = false;
  bool _isSpeaker = false;
  bool _isConnected = false;
  Timer? _durationTimer;
  int _callDurationSeconds = 0;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _initCall();
  }

  Future<void> _initCall() async {
    try {
      await _callService.initRenderers();

      _callService.onCallEnded = () {
        if (!_isDisposed && mounted) {
          _endCallAndGoBack();
        }
      };

      _callService.onCallAccepted = () {
        if (!mounted) return;
        setState(() {
          _callStatus = 'Connected';
          _isConnected = true;
          _startDurationTimer();
        });
      };

      _callService.onConnectionStateChanged = (RTCIceConnectionState state) {
        if (!mounted) return;
        setState(() {
          switch (state) {
            case RTCIceConnectionState.RTCIceConnectionStateConnected:
            case RTCIceConnectionState.RTCIceConnectionStateCompleted:
              _callStatus = 'Connected';
              _isConnected = true;
              _startDurationTimer();
              break;
            case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
              _callStatus = 'Reconnecting...';
              break;
            case RTCIceConnectionState.RTCIceConnectionStateFailed:
            case RTCIceConnectionState.RTCIceConnectionStateClosed:
              _callStatus = 'Call Ended';
              _endCallAndGoBack();
              break;
            default:
              break;
          }
        });
      };

      if (widget.isIncoming) {
        // Callee: answer the existing call
        setState(() => _callStatus = 'Answering...');
        await _callService.answerCall(widget.callId);
      } else {
        // Caller: start a new call
        setState(() => _callStatus = 'Ringing...');
        await _callService.startCallToUser(
          callerId: widget.currentUserId,
          callerName: widget.currentUserName,
          receiverId: widget.friendUserId,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _callStatus = 'Failed to connect');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Call error: $e')),
        );
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _endCallAndGoBack();
        });
      }
    }
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _callDurationSeconds++;
        });
      }
    });
  }

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _endCallAndGoBack() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _durationTimer?.cancel();
    try {
      await _callService.endCall();
    } catch (e) {
      debugPrint('Error ending call: $e');
    }
    if (mounted) {
      context.pop();
    }
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    if (!_isDisposed) {
      _isDisposed = true;
      _callService.endCall();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(flex: 2),
            // Profile avatar
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _isConnected ? Colors.greenAccent : Colors.blueAccent,
                  width: 3,
                ),
              ),
              child: const CircleAvatar(
                radius: 55,
                backgroundColor: Colors.blueAccent,
                child: Icon(Icons.person, size: 55, color: Colors.white),
              ),
            ),
            const SizedBox(height: 24),
            // Friend name
            Text(
              widget.friendName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            // Status or duration
            Text(
              _isConnected ? _formatDuration(_callDurationSeconds) : _callStatus,
              style: TextStyle(
                color: _isConnected ? Colors.greenAccent : Colors.white70,
                fontSize: 16,
                fontWeight: _isConnected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const Spacer(flex: 3),
            // Control buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 40.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Mute button
                  _buildCallButton(
                    icon: _isMuted ? Iconsax.microphone_slash : Iconsax.microphone,
                    color: _isMuted ? Colors.white : Colors.white24,
                    iconColor: _isMuted ? Colors.black : Colors.white,
                    label: _isMuted ? 'Unmute' : 'Mute',
                    onTap: () {
                      _callService.toggleMute();
                      setState(() {
                        _isMuted = _callService.isMuted;
                      });
                    },
                  ),
                  // Hang up button
                  _buildCallButton(
                    icon: Icons.call_end,
                    color: Colors.redAccent,
                    iconColor: Colors.white,
                    size: 68,
                    label: 'End',
                    onTap: _endCallAndGoBack,
                  ),
                  // Speaker button
                  _buildCallButton(
                    icon: _isSpeaker ? Icons.volume_up : Icons.volume_down,
                    color: _isSpeaker ? Colors.white : Colors.white24,
                    iconColor: _isSpeaker ? Colors.black : Colors.white,
                    label: _isSpeaker ? 'Speaker' : 'Speaker',
                    onTap: () {
                      _callService.toggleSpeaker();
                      setState(() {
                        _isSpeaker = _callService.isSpeakerOn;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildCallButton({
    required IconData icon,
    required Color color,
    required Color iconColor,
    required VoidCallback onTap,
    required String label,
    double size = 56,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: size * 0.45),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
