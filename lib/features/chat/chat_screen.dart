import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:runa_app/core/services/auth_service.dart';
import 'package:runa_app/core/services/chat_service.dart';
import 'package:runa_app/core/services/notification_service.dart';
import 'package:runa_app/core/services/storage_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:runa_app/core/services/typing_service.dart';
import 'package:runa_app/core/utils/image_helper.dart';
import 'package:runa_app/core/widgets/image_viewer.dart';
import 'package:runa_app/features/chat/widgets/voice_message_bubble.dart';

class ChatScreen extends StatefulWidget {
  final String userId;

  const ChatScreen({super.key, required this.userId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const List<String> _reactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  final TextEditingController _messageController = TextEditingController();
  final ChatService _chatService = ChatService();
  final StorageService _storageService = StorageService();
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();
  final TypingService _typingService = TypingService();

  String _friendName = 'Loading...';
  String _friendPhotoUrl = '';
  Map<String, dynamic>? _replyingToMessage;
  String? _chatId;
  bool _hasText = false;
  bool _friendTyping = false;

  // Voice-note recording state.
  bool _isRecording = false;
  bool _cancelArmed = false;
  Duration _recordElapsed = Duration.zero;
  DateTime? _recordStart;
  Timer? _recordTimer;

  /// Live stream of the friend's user row, used to drive presence in the header.
  late final Stream<List<Map<String, dynamic>>> _friendStream = FirebaseFirestore.instance
      .collection('users')
      .doc(widget.userId)
      .snapshots()
      .map((snapshot) => snapshot.exists ? [snapshot.data()!] : []);

  @override
  void initState() {
    super.initState();
    _fetchFriendName();
    // Mark this conversation as open so its incoming messages don't trigger a
    // notification while the user is reading it.
    final uid = context.read<AuthService>().currentUser?.uid;
    if (uid != null) {
      _chatId = _chatService.getChatId(uid, widget.userId);
      NotificationService.activeChatId = _chatId;
      _typingService.subscribe(_chatId!, uid);
    }
    _messageController.addListener(_onMessageChanged);
    _typingService.friendTyping.listen((isTyping) {
      if (mounted) setState(() => _friendTyping = isTyping);
    });
  }

  @override
  void dispose() {
    if (NotificationService.activeChatId == _chatId) {
      NotificationService.activeChatId = null;
    }
    _recordTimer?.cancel();
    _recorder.dispose();
    _typingService.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _onMessageChanged() {
    final hasText = _messageController.text.trim().isNotEmpty;
    _typingService.onTextChanged(hasText);
    if (hasText != _hasText) setState(() => _hasText = hasText);
  }

  Future<void> _fetchFriendName() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      if (mounted) {
        setState(() {
          if (doc.exists) {
            final data = doc.data() as Map<String, dynamic>?;
            if (data != null) {
              _friendName = data['username'] as String? ?? 'Unknown User';
              _friendPhotoUrl = data['photo_url'] as String? ?? '';
            } else {
              _friendName = 'Unknown User';
              _friendPhotoUrl = '';
            }
          } else {
            _friendName = 'Unknown User';
            _friendPhotoUrl = '';
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _friendName = 'Unknown User');
    }
  }

  void _sendMessage(String currentUid) {
    if (_messageController.text.trim().isEmpty) return;

    _chatService.sendMessage(
      currentUid,
      widget.userId,
      _messageController.text.trim(),
      replyToId: _replyingToMessage?['id'],
      replyToText: _replyingToMessage?['text'],
    );
    _messageController.clear();
    setState(() => _replyingToMessage = null);
  }

  // ---------------------------------------------------------------------------
  // Message actions (long-press): react / reply / copy / edit / forward / delete
  // ---------------------------------------------------------------------------

  void _showMessageActions(
      String currentUid, Map<String, dynamic> data, String decryptedText) {
    final isMe = data['sender_id'] == currentUid;
    final type = data['type'] as String? ?? 'text';
    final isText = type == 'text';
    final messageId = data['id'] as String;

    showModalBottomSheet(
      context: context,
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: _reactionEmojis.map((emoji) {
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        _chatService.toggleReaction(messageId, currentUid, emoji);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(emoji, style: const TextStyle(fontSize: 28)),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  setState(() {
                    _replyingToMessage = {
                      'id': messageId,
                      'text': decryptedText,
                    };
                  });
                },
              ),
              if (isText)
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: const Text('Copy'),
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    await Clipboard.setData(
                        ClipboardData(text: decryptedText));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard')),
                      );
                    }
                  },
                ),
              if (isMe && isText)
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _showEditDialog(messageId, decryptedText);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.forward),
                title: const Text('Forward'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _showForwardPicker(currentUid, data, decryptedText);
                },
              ),
              if (isMe)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('Delete',
                      style: TextStyle(color: Colors.red)),
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    await _chatService.deleteMessage(messageId);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _showEditDialog(String messageId, String currentText) {
    final controller = TextEditingController(text: currentText);
    final chatId = _chatId;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final newText = controller.text.trim();
              Navigator.pop(ctx);
              if (newText.isNotEmpty &&
                  newText != currentText &&
                  chatId != null) {
                await _chatService.editMessage(messageId, chatId, newText);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showForwardPicker(
      String currentUid, Map<String, dynamic> data, String decryptedText) {
    showModalBottomSheet(
      context: context,
      builder: (sheetCtx) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Forward to',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _chatService.getRecentChats(currentUid),
                    builder: (context, snapshot) {
                      final chats = snapshot.data ?? [];
                      if (chats.isEmpty) {
                        return const Center(child: Text('No recent chats'));
                      }
                      return ListView.builder(
                        itemCount: chats.length,
                        itemBuilder: (context, index) {
                          final chat = chats[index];
                          final photo = chat['photoUrl'] as String? ?? '';
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blueAccent,
                              backgroundImage: photo.isNotEmpty
                                  ? ImageHelper.getImageProvider(photo)
                                  : null,
                              child: photo.isEmpty
                                  ? const Icon(Icons.person,
                                      color: Colors.white)
                                  : null,
                            ),
                            title: Text(chat['name'] ?? 'Unknown'),
                            onTap: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final name = chat['name'];
                              Navigator.pop(sheetCtx);
                              await _forwardTo(currentUid, chat['uid'] as String,
                                  data, decryptedText);
                              messenger.showSnackBar(
                                SnackBar(content: Text('Forwarded to $name')),
                              );
                            },
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
      },
    );
  }

  Future<void> _forwardTo(String currentUid, String targetUid,
      Map<String, dynamic> data, String decryptedText) async {
    final type = data['type'] as String? ?? 'text';
    if (type == 'audio') {
      final url = data['media_url'] as String?;
      if (url != null) {
        await _chatService.sendMediaMessage(currentUid, targetUid, url, 'audio');
      }
    } else {
      // text / image (base64 data URI) / gif (url) all live in the message body.
      await _chatService.sendMessage(currentUid, targetUid, decryptedText,
          type: type);
    }
  }

  Widget _buildReactions(Map<String, dynamic>? reactions, bool isMe) {
    if (reactions == null || reactions.isEmpty) return const SizedBox.shrink();
    final counts = <String, int>{};
    reactions.forEach((_, emoji) {
      final e = emoji as String;
      counts[e] = (counts[e] ?? 0) + 1;
    });
    final chipColor = (isMe ? Colors.white : Theme.of(context).primaryColor)
        .withValues(alpha: 0.18);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        children: counts.entries.map((entry) {
          final label =
              entry.value > 1 ? '${entry.key} ${entry.value}' : entry.key;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: chipColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 11, color: isMe ? Colors.white : null)),
          );
        }).toList(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Voice messages
  // ---------------------------------------------------------------------------

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission denied')),
          );
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      _recordStart = DateTime.now();
      _recordElapsed = Duration.zero;
      _cancelArmed = false;
      if (mounted) setState(() => _isRecording = true);
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _recordElapsed += const Duration(seconds: 1));
        }
      });
    } catch (e) {
      debugPrint('[ChatScreen] record start failed: $e');
    }
  }

  Future<void> _stopAndSendRecording(String currentUid) async {
    if (!_isRecording) return;
    _recordTimer?.cancel();
    final wasCancel = _cancelArmed;
    final elapsedMs = _recordStart == null
        ? 0
        : DateTime.now().difference(_recordStart!).inMilliseconds;

    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isRecording = false;
        _cancelArmed = false;
      });
    }

    if (wasCancel || path == null) {
      _deleteTemp(path);
      return;
    }
    if (elapsedMs < 800) {
      _deleteTemp(path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hold to record a voice message')),
        );
      }
      return;
    }
    await _uploadAndSendVoice(currentUid, path);
  }

  Future<void> _uploadAndSendVoice(String currentUid, String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final fileName =
          'chat_media/voice/${_chatId ?? 'chat'}/${DateTime.now().millisecondsSinceEpoch}.m4a';
      final url = await _storageService.uploadBytes(
        bytes,
        fileName,
        contentType: 'audio/mp4',
      );
      _deleteTemp(path);
      if (url == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to send voice message')),
          );
        }
        return;
      }
      await _chatService.sendMediaMessage(
          currentUid, widget.userId, url, 'audio',
          mediaSize: bytes.length);
    } catch (e) {
      debugPrint('[ChatScreen] voice upload failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send voice message')),
        );
      }
    }
  }

  void _deleteTemp(String? path) {
    if (path == null) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _formatPresence(String? status, String? lastSeenIso) {
    if (status == 'online') return 'Online';
    if (lastSeenIso == null) return 'Offline';
    final dt = DateTime.tryParse(lastSeenIso)?.toLocal();
    if (dt == null) return 'Offline';
    final now = DateTime.now();
    final diff = now.difference(dt);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    if (diff.inSeconds < 60) return 'last seen just now';
    if (diff.inMinutes < 60) return 'last seen ${diff.inMinutes}m ago';
    if (now.year == dt.year && now.month == dt.month && now.day == dt.day) {
      return 'last seen at $hh:$mm';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (yesterday.year == dt.year &&
        yesterday.month == dt.month &&
        yesterday.day == dt.day) {
      return 'last seen yesterday at $hh:$mm';
    }
    return 'last seen ${dt.day}/${dt.month}/${dt.year}';
  }

  Widget _buildHeaderStatus() {
    if (_friendTyping) {
      return Text(
        'typing…',
        style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).primaryColor,
            fontWeight: FontWeight.w500),
      );
    }
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _friendStream,
      builder: (context, snapshot) {
        final row = (snapshot.data?.isNotEmpty ?? false)
            ? snapshot.data!.first
            : null;
        final status = row?['presence_status'] as String?;
        final lastSeen = row?['last_seen'] as String?;
        final isOnline = status == 'online';
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOnline)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 4),
                decoration: const BoxDecoration(
                    color: Colors.green, shape: BoxShape.circle),
              ),
            Flexible(
              child: Text(
                _formatPresence(status, lastSeen),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Reply UI (unchanged behaviour)
  // ---------------------------------------------------------------------------

  Widget _buildReplyBanner() {
    if (_replyingToMessage == null) return const SizedBox.shrink();

    final replyText = _replyingToMessage!['text'] ?? '';
    final isStatusReply = replyText.startsWith('💬 Status: ');
    final displayText =
        isStatusReply ? replyText.replaceFirst('💬 Status: ', '') : replyText;
    final isImage =
        displayText.startsWith('data:image/') || displayText.startsWith('http');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(
            left: BorderSide(color: Theme.of(context).primaryColor, width: 4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Replying to...',
                    style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
                const SizedBox(height: 4),
                if (isImage)
                  Row(children: [
                    const Icon(Icons.image, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    const Text('Photo', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        height: 30,
                        width: 30,
                        child: ImageHelper.getImageWidget(displayText,
                            fit: BoxFit.cover),
                      ),
                    ),
                  ])
                else
                  Text(displayText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => setState(() => _replyingToMessage = null),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyContext(String replyText, bool isMe) {
    final isStatusReply = replyText.startsWith('💬 Status: ');
    final accentColor = isStatusReply
        ? Colors.green
        : (isMe ? Colors.white54 : Theme.of(context).primaryColor);
    final label = isStatusReply ? '📢 Status Reply' : 'Reply';
    final displayText =
        isStatusReply ? replyText.replaceFirst('💬 Status: ', '') : replyText;
    final isImage =
        displayText.startsWith('data:image/') || displayText.startsWith('http');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: accentColor, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: accentColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 10)),
          const SizedBox(height: 4),
          if (isImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxHeight: 100, maxWidth: 100),
                child:
                    ImageHelper.getImageWidget(displayText, fit: BoxFit.cover),
              ),
            )
          else
            Text(displayText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: isMe ? Colors.white70 : Colors.grey[700],
                    fontStyle: FontStyle.italic,
                    fontSize: 12)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Image sending (unchanged behaviour)
  // ---------------------------------------------------------------------------

  Future<void> _showImagePreviewAndSend(
      String currentUid, List<XFile> images) async {
    if (images.isEmpty) return;

    final captionController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text(images.length > 1
            ? 'Send ${images.length} photos?'
            : 'Send photo?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 200,
              width: double.infinity,
              child: FutureBuilder<Uint8List>(
                future: images.first.readAsBytes(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(snap.data!, fit: BoxFit.cover),
                  );
                },
              ),
            ),
            if (images.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('+${images.length - 1} more photos',
                    style: TextStyle(color: Colors.grey[500])),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: captionController,
              decoration: InputDecoration(
                hintText: 'Add a caption...',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              maxLines: 2,
              minLines: 1,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Send')),
        ],
      ),
    );

    if (result == true && mounted) {
      final caption = captionController.text.trim();
      for (final image in images) {
        if (!mounted) break;
        final bytes = Uint8List.fromList(await image.readAsBytes());
        final base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        try {
          await _chatService.sendMessage(
            currentUid,
            widget.userId,
            base64Image,
            type: 'image',
            caption: caption.isNotEmpty ? caption : null,
          );
        } catch (e) {
          debugPrint('Error sending image: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to send image: $e')),
            );
          }
          break;
        }
      }
    }
    captionController.dispose();
  }

  Future<void> _pickImages(ImageSource source, String currentUid) async {
    Navigator.pop(context);
    try {
      if (source == ImageSource.gallery) {
        final List<XFile> images =
            await _picker.pickMultiImage(imageQuality: 50);
        if (images.isNotEmpty) {
          await _showImagePreviewAndSend(currentUid, images);
        }
      } else {
        final XFile? image =
            await _picker.pickImage(source: source, imageQuality: 50);
        if (image != null) {
          await _showImagePreviewAndSend(currentUid, [image]);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to send image: $e')));
      }
    }
  }

  void _showAttachmentBottomSheet(BuildContext context) {
    final currentUid = context.read<AuthService>().currentUser?.uid;
    if (currentUid == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildAttachmentIcon(
                    Icons.insert_drive_file, Colors.indigo, 'Document',
                    onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Document feature coming soon!')));
                }),
                _buildAttachmentIcon(Icons.camera_alt, Colors.pink, 'Camera',
                    onTap: () =>
                        _pickImages(ImageSource.camera, currentUid)),
                _buildAttachmentIcon(Icons.photo, Colors.purple, 'Gallery',
                    onTap: () =>
                        _pickImages(ImageSource.gallery, currentUid)),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildAttachmentIcon(Icons.gif_box, Colors.orange, 'GIF',
                    onTap: () {
                  Navigator.pop(context);
                  _showGifPicker(currentUid);
                }),
                _buildAttachmentIcon(
                    Icons.location_on, Colors.green, 'Location', onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Location feature coming soon!')));
                }),
                _buildAttachmentIcon(Icons.person, Colors.blue, 'Contact',
                    onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Contact feature coming soon!')));
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showGifPicker(String currentUid) {
    final gifController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: const Text('Send GIF'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Paste a GIF URL (e.g., from Giphy or Tenor):'),
            const SizedBox(height: 12),
            TextField(
              controller: gifController,
              decoration: InputDecoration(
                hintText: 'https://media.giphy.com/...',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final url = gifController.text.trim();
              if (url.isNotEmpty &&
                  (url.contains('.gif') ||
                      url.contains('giphy') ||
                      url.contains('tenor'))) {
                _chatService.sendMessage(currentUid, widget.userId, url,
                    type: 'gif');
                Navigator.pop(ctx);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Please enter a valid GIF URL')));
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentIcon(IconData icon, Color color, String text,
      {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: color,
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final currentUser = authService.currentUser;

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: const Center(child: Text('Not Logged In')),
      );
    }

    final chatId = _chatService.getChatId(currentUser.uid, widget.userId);
    _chatService.markMessagesAsRead(chatId, currentUser.uid, widget.userId);

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => context.push('/profile/${widget.userId}'),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.blueAccent,
                radius: 16,
                backgroundImage: _friendPhotoUrl.isNotEmpty
                    ? ImageHelper.getImageProvider(_friendPhotoUrl)
                    : null,
                child: _friendPhotoUrl.isEmpty
                    ? const Icon(Icons.person, color: Colors.white, size: 16)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_friendName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16)),
                    _buildHeaderStatus(),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Iconsax.call),
            onPressed: () {
              context.push('/call', extra: {
                'callId': '',
                'currentUserId': currentUser.uid,
                'currentUserName': currentUser.displayName ??
                    currentUser.email?.split('@')[0] ??
                    'User',
                'friendUserId': widget.userId,
                'friendName': _friendName,
                'isIncoming': false,
              });
            },
          ),
          IconButton(icon: const Icon(Iconsax.more), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _chatService.getMessages(chatId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data ?? [];

                if (messages.isEmpty) {
                  return const Center(child: Text('No messages yet.'));
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    String formatTime(String? isoString) {
                      if (isoString == null) return '';
                      try {
                        final date = DateTime.parse(isoString).toLocal();
                        return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                      } catch (_) {
                        return '';
                      }
                    }

                    String formatDateHeader(String? isoString) {
                      if (isoString == null) return '';
                      try {
                        final date = DateTime.parse(isoString).toLocal();
                        final now = DateTime.now();
                        final diff = now.difference(date);
                        if (diff.inDays == 0 && now.day == date.day) return 'Hari ini';
                        if (diff.inDays == 1 || (diff.inDays == 0 && now.day != date.day)) return 'Kemarin';
                        return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
                      } catch (_) {
                        return '';
                      }
                    }

                    final data = messages[index];
                    final isMe = data['sender_id'] == currentUser.uid;
                    final type = data['type'] as String? ?? 'text';
                    final reactions = (data['reactions'] as Map?)?.cast<String, dynamic>();
                    final isEdited = data['edited_at'] != null;

                    bool showDateHeader = false;
                    if (index == messages.length - 1) {
                      showDateHeader = true;
                    } else {
                      final prevData = messages[index + 1];
                      if (data['created_at'] != null && prevData['created_at'] != null) {
                        final currDate = DateTime.parse(data['created_at']).toLocal();
                        final prevDate = DateTime.parse(prevData['created_at']).toLocal();
                        if (currDate.day != prevDate.day || currDate.month != prevDate.month || currDate.year != prevDate.year) {
                          showDateHeader = true;
                        }
                      }
                    }

                    return FutureBuilder<String>(
                      future: _chatService.decrypt(data['text'] ?? '', chatId),
                      builder: (context, decSnapshot) {
                        final text = decSnapshot.data ?? '...';

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (showDateHeader)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: Text(
                                    formatDateHeader(data['created_at']),
                                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                                  ),
                                ),
                              ),
                            GestureDetector(
                              onLongPress: () =>
                                  _showMessageActions(currentUser.uid, data, text),
                              child: Align(
                                alignment: isMe
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.75),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? Theme.of(context).primaryColor
                                    : Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(16).copyWith(
                                  bottomRight: isMe
                                      ? const Radius.circular(0)
                                      : const Radius.circular(16),
                                  bottomLeft: !isMe
                                      ? const Radius.circular(0)
                                      : const Radius.circular(16),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: isMe
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  if (data['reply_to_text'] != null)
                                    _buildReplyContext(
                                        data['reply_to_text'], isMe),
                                  if (type == 'audio')
                                    VoiceMessageBubble(
                                      url: data['media_url'] as String? ?? '',
                                      isMe: isMe,
                                    )
                                  else if (type == 'image' || type == 'gif')
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        GestureDetector(
                                          onTap: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                                builder: (_) =>
                                                    ImageViewer(imageUrl: text)),
                                          ),
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                  maxHeight: 300),
                                              child: Hero(
                                                tag: text,
                                                child: ImageHelper.getImageWidget(
                                                    text,
                                                    fit: BoxFit.cover),
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (data['caption'] != null &&
                                            data['caption']
                                                .toString()
                                                .isNotEmpty)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 8),
                                            child: Text(
                                              data['caption'],
                                              style: TextStyle(
                                                color: isMe
                                                    ? Colors.white
                                                    : Theme.of(context)
                                                        .textTheme
                                                        .bodyLarge
                                                        ?.color,
                                              ),
                                            ),
                                          ),
                                      ],
                                    )
                                  else
                                    Text(
                                      text,
                                      style: TextStyle(
                                        color: isMe
                                            ? Colors.white
                                            : Theme.of(context)
                                                .textTheme
                                                .bodyLarge
                                                ?.color,
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isEdited) ...[
                                        Text(
                                          'edited',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontStyle: FontStyle.italic,
                                            color: isMe ? Colors.white70 : Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                      Text(
                                        formatTime(data['created_at'] as String?),
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: isMe ? Colors.white70 : Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      if (isMe)
                                        Icon(
                                          data['status'] == 'read'
                                              ? Icons.done_all
                                              : Icons.check,
                                          size: 14,
                                          color: data['status'] == 'read'
                                              ? Colors.lightBlueAccent
                                              : Colors.white70,
                                        ),
                                    ],
                                  ),
                                  _buildReactions(reactions, isMe),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }, // Closes FutureBuilder builder
                ); // Closes FutureBuilder return
              }, // Closes ListView.builder itemBuilder
            ); // Closes ListView.builder return
          }, // Closes StreamBuilder builder
        ), // Closes StreamBuilder
      ), // Closes Expanded
      SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildReplyBanner(),
                  _buildInputRow(currentUser.uid),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputRow(String currentUid) {
    final showSend = _hasText && !_isRecording;
    return Row(
      children: [
        if (!_isRecording)
          IconButton(
            icon: const Icon(Iconsax.add),
            onPressed: () => _showAttachmentBottomSheet(context),
          ),
        Expanded(
          child: _isRecording
              ? _buildRecordingBar()
              : TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).cardColor,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                  onSubmitted: (_) => _sendMessage(currentUid),
                ),
        ),
        const SizedBox(width: 8),
        showSend
            ? CircleAvatar(
                backgroundColor: Theme.of(context).primaryColor,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white, size: 20),
                  onPressed: () => _sendMessage(currentUid),
                ),
              )
            : GestureDetector(
                onLongPressStart: (_) => _startRecording(),
                onLongPressMoveUpdate: (details) {
                  final shouldCancel = details.offsetFromOrigin.dx < -80;
                  if (shouldCancel != _cancelArmed) {
                    setState(() => _cancelArmed = shouldCancel);
                  }
                },
                onLongPressEnd: (_) => _stopAndSendRecording(currentUid),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Hold to record, release to send'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                child: CircleAvatar(
                  backgroundColor: _isRecording
                      ? Colors.red
                      : Theme.of(context).primaryColor,
                  child: Icon(
                    _isRecording ? Icons.stop : Icons.mic,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
      ],
    );
  }

  Widget _buildRecordingBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
          const SizedBox(width: 8),
          Text(_fmtDuration(_recordElapsed)),
          const Spacer(),
          Text(
            _cancelArmed ? 'Release to cancel' : '‹ Slide to cancel',
            style: TextStyle(
              color: _cancelArmed ? Colors.red : Colors.grey,
              fontWeight:
                  _cancelArmed ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
