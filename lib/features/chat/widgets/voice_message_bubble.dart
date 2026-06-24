import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

/// Inline player for a voice message. Loads the clip lazily, shows a
/// play/pause control, a scrubber, and an elapsed/total duration label.
class VoiceMessageBubble extends StatefulWidget {
  final String url;
  final bool isMe;

  const VoiceMessageBubble({super.key, required this.url, required this.isMe});

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  final AudioPlayer _player = AudioPlayer();
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _isPlaying = s == PlayerState.playing);
    });
    _player.onPlayerComplete.listen((_) async {
      await _player.seek(Duration.zero);
      if (mounted) {
        setState(() {
          _position = Duration.zero;
          _isPlaying = false;
        });
      }
    });
    try {
      await _player.setSourceUrl(widget.url);
      final d = await _player.getDuration();
      if (d != null && mounted) setState(() => _duration = d);
    } catch (_) {
      // Leave duration at zero; the label falls back to a generic marker.
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_isPlaying) {
        await _player.pause();
      } else {
        await _player.resume();
      }
    } catch (_) {
      try {
        await _player.play(UrlSource(widget.url));
      } catch (_) {
        // Ignore playback errors (e.g. transient network failure).
      }
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isMe ? Colors.white : Theme.of(context).primaryColor;
    final trackColor = widget.isMe ? Colors.white : Colors.grey;
    final total = _duration.inMilliseconds;
    final pos = _position.inMilliseconds.clamp(0, total == 0 ? 1 : total);
    final progress = total == 0 ? 0.0 : (pos / total).clamp(0.0, 1.0);

    return SizedBox(
      width: 220,
      child: Row(
        children: [
          GestureDetector(
            onTap: _toggle,
            child: Icon(
              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
              color: color,
              size: 38,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 22,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: color,
                      inactiveTrackColor: trackColor.withValues(alpha: 0.35),
                      thumbColor: color,
                    ),
                    child: Slider(
                      value: progress,
                      onChanged: total == 0
                          ? null
                          : (v) async {
                              final target =
                                  Duration(milliseconds: (v * total).round());
                              await _player.seek(target);
                              if (mounted) setState(() => _position = target);
                            },
                    ),
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.mic, size: 12, color: color),
                    const SizedBox(width: 4),
                    Text(
                      total == 0
                          ? 'Voice message'
                          : _fmt(pos > 0 ? _position : _duration),
                      style: TextStyle(fontSize: 11, color: color),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
