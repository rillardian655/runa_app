import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:runa_app/core/services/call_session_controller.dart';

class CallScreen extends StatefulWidget {
  final String callId;
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
  final CallSessionController _controller = CallSessionController.instance;
  bool _closed = false;
  bool _errorShown = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureStarted());
  }

  Future<void> _ensureStarted() async {
    if (_controller.hasActiveCall) {
      // Re-opened from the island: just hide the island while we're on screen.
      _controller.maximize();
      return;
    }
    await _controller.start(
      callId: widget.callId,
      currentUserId: widget.currentUserId,
      currentUserName: widget.currentUserName,
      friendUserId: widget.friendUserId,
      friendName: widget.friendName,
      isIncoming: widget.isIncoming,
      isVideo: false,
    );
  }

  void _onControllerChange() {
    if (!mounted || _closed) return;

    final error = _controller.error;
    if (error != null && !_errorShown) {
      _errorShown = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Call error: $error')),
      );
    }

    // The call ended (remote hang-up, failure, or hang-up from the island).
    if (!_controller.hasActiveCall) {
      _closed = true;
      if (context.canPop()) context.pop();
    }
  }

  @override
  void dispose() {
    // Do NOT end the call here — the controller owns its lifecycle so the call
    // can keep running while minimized into the island.
    _controller.removeListener(_onControllerChange);
    super.dispose();
  }

  void _minimizeAndClose() {
    if (_closed) return;
    _closed = true;
    _controller.minimize();
    if (context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _minimizeAndClose();
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final connected = _controller.isConnected;
          return Scaffold(
            backgroundColor: const Color(0xFF1A1A2E),
            body: SafeArea(
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down,
                          color: Colors.white, size: 32),
                      tooltip: 'Minimize',
                      onPressed: _minimizeAndClose,
                    ),
                  ),
                  const Spacer(flex: 2),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: connected ? Colors.greenAccent : Colors.blueAccent,
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
                  Text(
                    _controller.friendName.isNotEmpty
                        ? _controller.friendName
                        : widget.friendName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _controller.statusLabel,
                    style: TextStyle(
                      color: connected ? Colors.greenAccent : Colors.white70,
                      fontSize: 16,
                      fontWeight: connected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const Spacer(flex: 3),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 40.0, vertical: 40.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildCallButton(
                          icon: _controller.isMuted
                              ? Iconsax.microphone_slash
                              : Iconsax.microphone,
                          color: _controller.isMuted
                              ? Colors.white
                              : Colors.white24,
                          iconColor:
                              _controller.isMuted ? Colors.black : Colors.white,
                          label: _controller.isMuted ? 'Unmute' : 'Mute',
                          onTap: _controller.toggleMute,
                        ),
                        _buildCallButton(
                          icon: Icons.call_end,
                          color: Colors.redAccent,
                          iconColor: Colors.white,
                          size: 68,
                          label: 'End',
                          onTap: _controller.end,
                        ),
                        _buildCallButton(
                          icon: _controller.isSpeakerOn
                              ? Icons.volume_up
                              : Icons.volume_down,
                          color: _controller.isSpeakerOn
                              ? Colors.white
                              : Colors.white24,
                          iconColor: _controller.isSpeakerOn
                              ? Colors.black
                              : Colors.white,
                          label: 'Speaker',
                          onTap: _controller.toggleSpeaker,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
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
