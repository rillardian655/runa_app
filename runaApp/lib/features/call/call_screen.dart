import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:runa_app/core/services/call_service.dart';

class CallScreen extends StatefulWidget {
  final String callId;

  const CallScreen({super.key, required this.callId});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final CallService _callService = CallService();
  bool isMuted = false;
  bool isSpeaker = false;

  @override
  void initState() {
    super.initState();
    _initCall();
  }

  Future<void> _initCall() async {
    await _callService.initRenderers();
    // In a real app, logic here depends on caller vs callee
    // For now, assume this attempts to start a call.
  }

  @override
  void dispose() {
    _callService.endCall();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            const CircleAvatar(
              radius: 60,
              backgroundColor: Colors.blueAccent,
              child: Icon(Icons.person, size: 60, color: Colors.white),
            ),
            const SizedBox(height: 24),
            Text(
              'Calling \${widget.callId}...',
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ringing',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 40.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildCallButton(
                    icon: isMuted ? Iconsax.microphone_slash : Iconsax.microphone,
                    color: isMuted ? Colors.white : Colors.white24,
                    iconColor: isMuted ? Colors.black : Colors.white,
                    onTap: () {
                      setState(() {
                        isMuted = !isMuted;
                      });
                    },
                  ),
                  _buildCallButton(
                    icon: Icons.call_end,
                    color: Colors.redAccent,
                    iconColor: Colors.white,
                    size: 64,
                    onTap: () {
                      context.pop();
                    },
                  ),
                  _buildCallButton(
                    icon: isSpeaker ? Icons.volume_up : Icons.volume_down,
                    color: isSpeaker ? Colors.white : Colors.white24,
                    iconColor: isSpeaker ? Colors.black : Colors.white,
                    onTap: () {
                      setState(() {
                        isSpeaker = !isSpeaker;
                      });
                    },
                  ),
                ],
              ),
            ),
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
    double size = 56,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: iconColor, size: size * 0.5),
      ),
    );
  }
}
