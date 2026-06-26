import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:runa_app/app/routes.dart';
import 'package:runa_app/core/services/call_session_controller.dart';

/// An iOS/HyperOS-style "Dynamic Island": a floating pill near the top cutout
/// that appears whenever a call is active but minimized. Collapsed it shows a
/// live timer; tapped it expands to caller info + mute / open / hang-up.
///
/// Mounted once, globally, above the router so it floats over every screen.
class DynamicIsland extends StatefulWidget {
  const DynamicIsland({super.key});

  @override
  State<DynamicIsland> createState() => _DynamicIslandState();
}

class _DynamicIslandState extends State<DynamicIsland> {
  final CallSessionController _controller = CallSessionController.instance;
  bool _expanded = false;

  void _maximize() {
    _expanded = false;
    _controller.maximize();
    context.push('/call', extra: {
      'callId': _controller.callId,
      'currentUserId': _controller.currentUserId,
      'currentUserName': _controller.currentUserName,
      'friendUserId': _controller.friendUserId,
      'friendName': _controller.friendName,
      'isIncoming': _controller.isIncoming,
    });
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final visible = _controller.hasActiveCall && _controller.isMinimized;
        if (!visible) {
          _expanded = false;
          return const SizedBox.shrink();
        }
        return Positioned(
          top: topInset + 6,
          left: 0,
          right: 0,
          child: Align(
            alignment: Alignment.topCenter,
            child: _IslandPill(
              controller: _controller,
              expanded: _expanded,
              onToggle: () => setState(() => _expanded = !_expanded),
              onMaximize: _maximize,
              onHangup: _controller.end,
              onMute: _controller.toggleMute,
            ),
          ),
        );
      },
    );
  }
}

class _IslandPill extends StatelessWidget {
  const _IslandPill({
    required this.controller,
    required this.expanded,
    required this.onToggle,
    required this.onMaximize,
    required this.onHangup,
    required this.onMute,
  });

  final CallSessionController controller;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onMaximize;
  final VoidCallback onHangup;
  final VoidCallback onMute;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = math.min(screenWidth - 24.0, 380.0);

    return Material(
      color: Colors.transparent,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF0B0B0F),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: expanded ? _buildExpanded(context) : _buildCollapsed(),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsed() {
    final connected = controller.isConnected;
    return InkWell(
      borderRadius: BorderRadius.circular(30),
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PulsingDot(color: connected ? Colors.greenAccent : Colors.amber),
            const SizedBox(width: 10),
            const Icon(Icons.call, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(
              connected ? controller.formattedDuration : controller.statusLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpanded(BuildContext context) {
    final connected = controller.isConnected;
    final initial = controller.friendName.isNotEmpty
        ? controller.friendName[0].toUpperCase()
        : '?';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onMaximize,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.blueAccent,
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        controller.friendName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        controller.statusLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: connected ? Colors.greenAccent : Colors.white60,
                          fontSize: 12,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          _IslandAction(
            icon: controller.isMuted ? Icons.mic_off : Icons.mic,
            background: controller.isMuted ? Colors.white24 : Colors.white10,
            onTap: onMute,
          ),
          const SizedBox(width: 6),
          _IslandAction(
            icon: Icons.open_in_full,
            background: Colors.white10,
            onTap: onMaximize,
          ),
          const SizedBox(width: 6),
          _IslandAction(
            icon: Icons.call_end,
            background: Colors.redAccent,
            onTap: onHangup,
          ),
        ],
      ),
    );
  }
}

class _IslandAction extends StatelessWidget {
  const _IslandAction({
    required this.icon,
    required this.background,
    required this.onTap,
  });

  final IconData icon;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1.0, end: 0.3).animate(_ac),
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
