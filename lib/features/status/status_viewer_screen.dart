import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:runa_app/core/services/chat_service.dart';
import 'package:runa_app/core/services/status_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:runa_app/core/utils/image_helper.dart';

class StatusViewerScreen extends StatefulWidget {
  /// All statuses from one user (list of maps with 'id', 'type', 'content', 'timestamp', 'viewedBy', etc.)
  final List<Map<String, dynamic>> statuses;
  final String viewerUid; // current user viewing
  final String ownerName;
  final String ownerPhotoUrl;
  final bool isOwn; // if viewing own statuses

  const StatusViewerScreen({
    super.key,
    required this.statuses,
    required this.viewerUid,
    required this.ownerName,
    required this.ownerPhotoUrl,
    this.isOwn = false,
  });

  @override
  State<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends State<StatusViewerScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  late AnimationController _progressController;
  static const Duration _storyDuration = Duration(seconds: 5);

  bool _isReplying = false;
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();
  final ChatService _chatService = ChatService();
  bool _isSending = false;
  bool _isPaused = false; // Track pause state for clean screen

  // Video playback (for type == 'video' statuses)
  VideoPlayerController? _videoController;
  bool _isVideoLoading = false;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(vsync: this, duration: _storyDuration);
    _startStory(0);
  }

  Future<void> _disposeVideo() async {
    final c = _videoController;
    _videoController = null;
    if (c != null) {
      try {
        await c.pause();
      } catch (_) {}
      await c.dispose();
    }
  }

  Future<void> _startStory(int index) async {
    if (index >= widget.statuses.length) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    await _disposeVideo();
    if (!mounted) return;
    setState(() {
      _currentIndex = index;
      _isPaused = false;
      _isVideoLoading = false;
    });
    _progressController.reset();

    final status = widget.statuses[index];
    if (status['type'] == 'video') {
      await _playVideoStory(status);
    } else {
      _progressController.duration = _storyDuration;
      _progressController.forward().then((_) {
        if (mounted && !_isReplying) _nextStory();
      });
    }
  }

  Future<void> _playVideoStory(Map<String, dynamic> status) async {
    final url = (status['content'] as String?) ?? '';
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _videoController = controller;
    setState(() => _isVideoLoading = true);
    try {
      await controller.initialize();
      // Bail if we navigated away while loading
      if (!mounted || _videoController != controller) return;
      await controller.setLooping(false);
      final dur = controller.value.duration;
      _progressController.duration =
          dur.inMilliseconds > 0 ? dur : _storyDuration;
      setState(() => _isVideoLoading = false);
      await controller.play();
      _progressController.forward().then((_) {
        if (mounted && !_isReplying) _nextStory();
      });
    } catch (e) {
      // Couldn't load the video — fall back to the default story timer
      if (!mounted || _videoController != controller) return;
      setState(() => _isVideoLoading = false);
      _progressController.duration = _storyDuration;
      _progressController.forward().then((_) {
        if (mounted && !_isReplying) _nextStory();
      });
    }
  }

  void _nextStory() {
    if (_currentIndex + 1 < widget.statuses.length) {
      _startStory(_currentIndex + 1);
    } else {
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _previousStory() {
    if (_currentIndex > 0) {
      _startStory(_currentIndex - 1);
    }
  }

  void _openReplyInput() {
    _progressController.stop();
    setState(() => _isReplying = true);
    _replyFocusNode.requestFocus();
  }

  void _closeReplyInput() {
    _replyFocusNode.unfocus();
    _replyController.clear();
    setState(() => _isReplying = false);
    // Resume the story
    _progressController.forward().then((_) {
      if (mounted && !_isReplying) _nextStory();
    });
  }

  Future<void> _sendReply() async {
    final replyText = _replyController.text.trim();
    if (replyText.isEmpty || _isSending) return;

    setState(() => _isSending = true);

    final currentStatus = widget.statuses[_currentIndex];
    final statusOwnerUid = currentStatus['uid'] as String;

    // Build a status reply preview text
    String statusPreview;
    if (currentStatus['type'] == 'image') {
      statusPreview = currentStatus['content']; // pass the base64 or URL
    } else {
      final content = currentStatus['content'] as String? ?? '';
      statusPreview = content.length > 60 ? '${content.substring(0, 60)}...' : content;
    }

    try {
      // Send as a chat message with status reply context
      await _chatService.sendMessage(
        widget.viewerUid,
        statusOwnerUid,
        replyText,
        replyToText: '💬 Status: $statusPreview',
      );

      if (mounted) {
        _replyController.clear();
        _replyFocusNode.unfocus();
        setState(() {
          _isReplying = false;
          _isSending = false;
        });

        // Show confirmation
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Balasan terkirim ke ${widget.ownerName}'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );

        // Resume story
        _progressController.forward().then((_) {
          if (mounted && !_isReplying) _nextStory();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengirim balasan: $e')),
        );
      }
    }
  }

  String _timeAgo(dynamic timestamp) {
    if (timestamp == null) return '';
    DateTime? dt;
    if (timestamp is DateTime) {
      dt = timestamp;
    } else if (timestamp is String) {
      dt = DateTime.tryParse(timestamp);
    } else {
      dt = timestamp.toDate();
    }
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m yang lalu';
    if (diff.inHours < 24) return '${diff.inHours}j yang lalu';
    return '${diff.inDays}h yang lalu';
  }

  @override
  void dispose() {
    _progressController.dispose();
    _replyController.dispose();
    _replyFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentStatus = widget.statuses[_currentIndex];
    final isImage = currentStatus['type'] == 'image';
    final isVideo = currentStatus['type'] == 'video';
    final bgColor = Color((currentStatus['bg_color'] as int?) ?? 0xFF1A1A2E);
    final viewedBy = List<String>.from(currentStatus['viewed_by'] ?? []);
    final viewCount = viewedBy.length;

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onTapDown: (details) {
          if (_isReplying) return; // Don't navigate while replying
          final screenWidth = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < screenWidth / 3) {
            _previousStory();
          } else if (details.globalPosition.dx > screenWidth * 2 / 3) {
            _nextStory();
          } else {
            // Pause / resume on center tap
            if (_progressController.isAnimating) {
              _progressController.stop();
              setState(() => _isPaused = true);
            } else {
              _progressController.forward().then((_) {
                if (mounted && !_isReplying) _nextStory();
              });
              setState(() => _isPaused = false);
            }
          }
        },
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // --- Background Content ---
                  if (isVideo)
                    Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_videoController != null && _videoController!.value.isInitialized)
                          FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(
                              width: _videoController!.value.size.width,
                              height: _videoController!.value.size.height,
                              child: VideoPlayer(_videoController!),
                            ),
                          )
                        else
                          const Center(child: CircularProgressIndicator(color: Colors.white)),
                        if (_isVideoLoading)
                          const Center(child: CircularProgressIndicator(color: Colors.white)),
                        if (currentStatus['caption'] != null && currentStatus['caption'].toString().isNotEmpty)
                          Positioned(
                            bottom: widget.isOwn ? 60 : 80,
                            left: 16,
                            right: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                currentStatus['caption'],
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white, fontSize: 16),
                              ),
                            ),
                          ),
                      ],
                    )
                  else if (isImage)
                    Stack(
                      fit: StackFit.expand,
                      children: [
                        Image(
                          image: ImageHelper.getImageProvider(currentStatus['content']),
                          fit: BoxFit.contain,
                        ),
                        if (currentStatus['caption'] != null && currentStatus['caption'].toString().isNotEmpty)
                          Positioned(
                            bottom: widget.isOwn ? 60 : 80,
                            left: 16,
                            right: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                currentStatus['caption'],
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white, fontSize: 16),
                              ),
                            ),
                          ),
                      ],
                    )
                  else
                    Container(
                      color: bgColor,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        currentStatus['content'] ?? '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          height: 1.4,
                        ),
                      ),
                    ),

                  // --- Top gradient overlay (hidden when paused) ---
                  if (!_isPaused)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 120,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black54, Colors.transparent],
                          ),
                        ),
                      ),
                    ),

                  // --- Progress Bars (always visible) ---
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 8,
                    right: 8,
                    child: AnimatedBuilder(
                      animation: _progressController,
                      builder: (context, child) {
                        return Row(
                          children: List.generate(widget.statuses.length, (i) {
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: i < _currentIndex
                                        ? 1.0
                                        : i == _currentIndex
                                            ? _progressController.value
                                            : 0.0,
                                    minHeight: 3,
                                    backgroundColor: Colors.white30,
                                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                ),
                              ),
                            );
                          }),
                        );
                      },
                    ),
                  ),

                  // --- Header (user info + close) — hidden when paused for clean screen ---
                  if (!_isPaused)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 20,
                      left: 12,
                      right: 12,
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.blueAccent,
                            backgroundImage: widget.ownerPhotoUrl.isNotEmpty
                                ? ImageHelper.getImageProvider(widget.ownerPhotoUrl)
                                : null,
                            child: widget.ownerPhotoUrl.isEmpty
                                ? Text(
                                    widget.ownerName.isNotEmpty ? widget.ownerName[0].toUpperCase() : '?',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.ownerName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  _timeAgo(currentStatus['created_at']),
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          if (widget.isOwn)
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.white),
                              onPressed: () async {
                                _progressController.stop();
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: Theme.of(context).cardColor,
                                    title: const Text('Hapus Status'),
                                    content: const Text('Yakin ingin menghapus status ini?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus', style: TextStyle(color: Colors.red))),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await StatusService().deleteStatus(currentStatus['id']);
                                  if (mounted) Navigator.pop(context);
                                } else {
                                  _progressController.forward().then((_) {
                                    if (mounted && !_isReplying) _nextStory();
                                  });
                                }
                              },
                            ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),

                  // --- Bottom: view count (own status) — hidden when paused ---
                  if (widget.isOwn && !_isPaused)
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: GestureDetector(
                        onTap: () => _showViewersList(viewedBy),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.remove_red_eye, color: Colors.white70, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                '$viewCount viewed',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              if (viewCount > 0) ...[
                                const SizedBox(width: 8),
                                const Icon(Icons.chevron_right, color: Colors.white70, size: 18),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // --- Reply input bar (only for other people's status, hidden when paused) ---
            if (!widget.isOwn && !_isPaused)
              _buildReplyBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyBar() {
    if (_isReplying) {
      // Expanded input mode
      return Container(
        color: Colors.black87,
        padding: EdgeInsets.only(
          left: 12,
          right: 8,
          top: 8,
          bottom: MediaQuery.of(context).padding.bottom + 8,
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _replyController,
                focusNode: _replyFocusNode,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Balas ke ${widget.ownerName}...',
                  hintStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white12,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  prefixIcon: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                    onPressed: _closeReplyInput,
                  ),
                ),
                onSubmitted: (_) => _sendReply(),
              ),
            ),
            const SizedBox(width: 8),
            _isSending
                ? const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.green,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 18),
                      onPressed: _sendReply,
                    ),
                  ),
          ],
        ),
      );
    }

    // Default: tap to open reply
    return GestureDetector(
      onTap: _openReplyInput,
      child: Container(
        color: Colors.black87,
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).padding.bottom + 12,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white30),
          ),
          child: const Row(
            children: [
              Icon(Icons.emoji_emotions_outlined, color: Colors.white54, size: 20),
              SizedBox(width: 10),
              Text('Balas status...', style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      ),
    );
  }

  void _showViewersList(List<String> viewedBy) {
        if (viewedBy.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No viewers yet')),
          );
          return;
        }
    
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (ctx) => Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.remove_red_eye, size: 24),
                      const SizedBox(width: 12),
                      Text(
                        'Viewers (${viewedBy.length})',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: viewedBy.length,
                    itemBuilder: (context, index) {
                      final viewerUid = viewedBy[index];
                      return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        future: FirebaseFirestore.instance
                            .collection('users')
                            .doc(viewerUid)
                            .get(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const ListTile(
                              leading: CircleAvatar(child: CircularProgressIndicator()),
                              title: Text('Loading...'),
                            );
                          }

                          final userData = snapshot.data?.data();
                          final username = userData?['username'] ?? 'Unknown';
                          final photoUrl = userData?['photo_url'] ?? '';
    
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blueAccent,
                              backgroundImage: photoUrl.isNotEmpty
                                  ? ImageHelper.getImageProvider(photoUrl)
                                  : null,
                              child: photoUrl.isEmpty
                                  ? Text(
                                      username.isNotEmpty ? username[0].toUpperCase() : '?',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    )
                                  : null,
                            ),
                            title: Text(username, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(userData?['bio'] ?? 'Available'),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
