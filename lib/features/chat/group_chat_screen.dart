import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:runa_app/core/services/auth_service.dart';
import 'package:runa_app/core/services/chat_service.dart';
import 'package:runa_app/core/services/group_service.dart';
import 'package:runa_app/core/services/group_typing_service.dart';
import 'package:runa_app/core/services/storage_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:runa_app/core/utils/image_helper.dart';
import 'package:runa_app/core/widgets/image_viewer.dart';
import 'package:runa_app/features/chat/widgets/voice_message_bubble.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId;

  const GroupChatScreen({super.key, required this.groupId});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  static const List<String> _reactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  final TextEditingController _messageController = TextEditingController();
  final GroupService _groupService = GroupService();
  final ChatService _chatService = ChatService();
  final StorageService _storageService = StorageService();
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();
  final GroupTypingService _typingService = GroupTypingService();

  String _groupName = 'Loading...';
  String _groupIcon = '';
  List<String> _memberIds = [];
  String _myName = 'Someone';
  bool _hasText = false;
  List<String> _typers = [];

  // Cache uid -> display name so frequent rebuilds (e.g. typing updates) don't
  // re-query the users table for every message on screen.
  final Map<String, String> _nameCache = {};

  // Voice-note recording state.
  bool _isRecording = false;
  bool _cancelArmed = false;
  Duration _recordElapsed = Duration.zero;
  DateTime? _recordStart;
  Timer? _recordTimer;

  @override
  void initState() {
    super.initState();
    _fetchGroupDetails();
    final uid = context.read<AuthService>().currentUser?.uid;
    if (uid != null) {
      _typingService.subscribe(widget.groupId, uid);
      _fetchMyName(uid);
    }
    _messageController.addListener(_onMessageChanged);
    _typingService.typers.listen((names) {
      if (mounted) setState(() => _typers = names);
    });
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _recorder.dispose();
    _typingService.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _fetchGroupDetails() async {
    final details = await _groupService.getGroupDetails(widget.groupId);
    final memberIds = await _groupService.getGroupMemberIds(widget.groupId);
    if (mounted) {
      setState(() {
        _groupName = details?['name'] ?? 'Unnamed Group';
        _groupIcon = details?['group_icon'] ?? '';
        _memberIds = memberIds;
      });
    }
  }

  Future<void> _fetchMyName(String uid) async {
    final name = await _getSenderName(uid);
    if (mounted) setState(() => _myName = name);
  }

  void _onMessageChanged() {
    final hasText = _messageController.text.trim().isNotEmpty;
    _typingService.onTextChanged(hasText, _myName);
    if (hasText != _hasText) setState(() => _hasText = hasText);
  }

  void _sendMessage(String currentUid) {
    if (_messageController.text.trim().isEmpty) return;

    _groupService.sendGroupMessage(
      groupId: widget.groupId,
      senderId: currentUid,
      text: _messageController.text.trim(),
    );
    _messageController.clear();
  }

  Future<String> _getSenderName(String senderId) async {
    final cached = _nameCache[senderId];
    if (cached != null) return cached;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(senderId)
        .get();
    final name = (doc.exists ? doc.data()?['username'] as String? : null) ?? 'Unknown';
    _nameCache[senderId] = name;
    return name;
  }

  // ---------------------------------------------------------------------------
  // Message actions (long-press): react / copy / edit / forward / delete
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
                        _groupService.toggleReaction(
                            messageId, currentUid, emoji);
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
                    await _groupService.deleteGroupMessage(messageId);
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
              if (newText.isNotEmpty && newText != currentText) {
                await _groupService.editGroupMessage(
                    messageId, widget.groupId, newText);
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
                              await _forwardTo(currentUid,
                                  chat['uid'] as String, data, decryptedText);
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
      // text / image (base64 data URI) all live in the decrypted message body.
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
      debugPrint('[GroupChatScreen] record start failed: $e');
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
          'chat_media/voice/group/${widget.groupId}/${DateTime.now().millisecondsSinceEpoch}.m4a';
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
      await _groupService.sendGroupMediaMessage(
        groupId: widget.groupId,
        senderId: currentUid,
        mediaUrl: url,
        type: 'audio',
      );
    } catch (e) {
      debugPrint('[GroupChatScreen] voice upload failed: $e');
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

  Widget _buildHeaderSubtitle() {
    if (_typers.isNotEmpty) {
      final text = _typers.length == 1
          ? '${_typers.first} is typing…'
          : _typers.length == 2
              ? '${_typers[0]} and ${_typers[1]} are typing…'
              : 'Several people are typing…';
      return Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).primaryColor,
            fontWeight: FontWeight.w500),
      );
    }
    return Text(
      '${_memberIds.length} members',
      style: const TextStyle(fontSize: 12, color: Colors.grey),
    );
  }

  // ---------------------------------------------------------------------------
  // Image sending
  // ---------------------------------------------------------------------------

  Future<void> _pickImage(ImageSource source, String currentUid) async {
    Navigator.pop(context); // Close bottom sheet
    try {
      final XFile? image =
          await _picker.pickImage(source: source, imageQuality: 50);
      if (image != null) {
        final bytes = await image.readAsBytes();
        final base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';

        await _groupService.sendGroupMessage(
          groupId: widget.groupId,
          senderId: currentUid,
          text: base64Image,
          type: 'image',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send image: $e')),
        );
      }
    }
  }

  void _showAttachmentBottomSheet(BuildContext context) {
    final currentUid = context.read<AuthService>().currentUser?.uid;
    if (currentUid == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
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
                  _buildAttachmentIcon(Icons.camera_alt, Colors.pink, 'Camera',
                      onTap: () => _pickImage(ImageSource.camera, currentUid)),
                  _buildAttachmentIcon(Icons.photo, Colors.purple, 'Gallery',
                      onTap: () => _pickImage(ImageSource.gallery, currentUid)),
                ],
              ),
            ],
          ),
        );
      },
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

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.blueAccent,
              radius: 16,
              backgroundImage: _groupIcon.isNotEmpty
                  ? ImageHelper.getImageProvider(_groupIcon)
                  : null,
              child: _groupIcon.isEmpty
                  ? const Icon(Icons.group, color: Colors.white, size: 16)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_groupName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16)),
                  _buildHeaderSubtitle(),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Iconsax.more), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _groupService.getGroupMessages(widget.groupId),
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
                    final data = messages[index];
                    final isMe = data['sender_id'] == currentUser.uid;
                    final senderId = data['sender_id'] as String;
                    final type = data['type'] as String? ?? 'text';
                    final isAudio = type == 'audio';
                    final reactions =
                        (data['reactions'] as Map?)?.cast<String, dynamic>();
                    final isEdited = data['edited_at'] != null;

                    return FutureBuilder<String>(
                      future: isAudio
                          ? Future.value('')
                          : _groupService.decryptGroupMessage(
                              data['text'] ?? '', widget.groupId),
                      builder: (context, decSnapshot) {
                        final text = decSnapshot.data ?? '...';

                        return FutureBuilder<String>(
                          initialData: _nameCache[senderId],
                          future: _getSenderName(senderId),
                          builder: (context, nameSnapshot) {
                            final senderName = nameSnapshot.data ?? 'Unknown';

                            return GestureDetector(
                              onLongPress: () => _showMessageActions(
                                  currentUser.uid, data, text),
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
                                          MediaQuery.of(context).size.width *
                                              0.75),
                                  decoration: BoxDecoration(
                                    color: isMe
                                        ? Theme.of(context).primaryColor
                                        : Theme.of(context).cardColor,
                                    borderRadius:
                                        BorderRadius.circular(16).copyWith(
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
                                      if (!isMe)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 4),
                                          child: Text(
                                            senderName,
                                            style: TextStyle(
                                              color:
                                                  Theme.of(context).primaryColor,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      if (isAudio)
                                        VoiceMessageBubble(
                                          url:
                                              data['media_url'] as String? ?? '',
                                          isMe: isMe,
                                        )
                                      else if (type == 'image')
                                        GestureDetector(
                                          onTap: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  ImageViewer(imageUrl: text),
                                            ),
                                          ),
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                  maxHeight: 300),
                                              child: Hero(
                                                tag: text,
                                                child:
                                                    ImageHelper.getImageWidget(
                                                        text,
                                                        fit: BoxFit.cover),
                                              ),
                                            ),
                                          ),
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
                                      if (isEdited)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 2),
                                          child: Text(
                                            'edited',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontStyle: FontStyle.italic,
                                              color: isMe
                                                  ? Colors.white70
                                                  : Colors.grey,
                                            ),
                                          ),
                                        ),
                                      _buildReactions(reactions, isMe),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: _buildInputRow(currentUser.uid),
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
              fontWeight: _cancelArmed ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
