import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:runa_app/core/services/auth_service.dart';
import 'package:runa_app/core/services/chat_service.dart';
import 'package:runa_app/core/utils/image_helper.dart';
import 'package:runa_app/core/widgets/image_viewer.dart';

class ChatScreen extends StatefulWidget {
  final String userId; // Ini adalah friendUid (UID teman yang diajak chat)

  const ChatScreen({super.key, required this.userId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ChatService _chatService = ChatService();
  String _friendName = 'Loading...';
  String _friendPhotoUrl = '';
  Map<String, dynamic>? _replyingToMessage;

  @override
  void initState() {
    super.initState();
    _fetchFriendName();
  }

  Future<void> _fetchFriendName() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
      if (mounted) {
        setState(() {
          if (doc.exists) {
            _friendName = doc.data()?['username'] ?? 'User';
            _friendPhotoUrl = doc.data()?['photoUrl'] ?? '';
          } else {
            _friendName = 'Unknown User';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _friendName = 'Unknown User';
        });
      }
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
    setState(() {
      _replyingToMessage = null;
    });
  }

  Widget _buildReplyBanner() {
    if (_replyingToMessage == null) return const SizedBox.shrink();
    
    final replyText = _replyingToMessage!['text'] ?? '';
    final isStatusReply = replyText.startsWith('💬 Status: ');
    final displayText = isStatusReply ? replyText.replaceFirst('💬 Status: ', '') : replyText;
    final isImage = displayText.startsWith('data:image/') || displayText.startsWith('http');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(left: BorderSide(color: Theme.of(context).primaryColor, width: 4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Replying to...', style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                if (isImage)
                  Row(
                    children: [
                      const Icon(Icons.image, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      const Text('Foto', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          height: 30,
                          width: 30,
                          child: ImageHelper.getImageWidget(displayText, fit: BoxFit.cover),
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    displayText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
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
    final accentColor = isStatusReply ? Colors.green : (isMe ? Colors.white54 : Theme.of(context).primaryColor);
    final label = isStatusReply ? '📢 Balasan Status' : 'Reply';
    final displayText = isStatusReply ? replyText.replaceFirst('💬 Status: ', '') : replyText;
    final isImage = displayText.startsWith('data:image/') || displayText.startsWith('http');

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
          Text(
            label,
            style: TextStyle(
              color: accentColor,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          if (isImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 100, maxWidth: 100),
                child: ImageHelper.getImageWidget(displayText, fit: BoxFit.cover),
              ),
            )
          else
            Text(
              displayText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isMe ? Colors.white70 : Colors.grey[700],
                fontStyle: FontStyle.italic,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source, String currentUid) async {
    Navigator.pop(context); // Close bottom sheet
    try {
      final XFile? image = await _picker.pickImage(source: source, imageQuality: 50);
      if (image != null) {
        final bytes = await image.readAsBytes();
        final base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        
        _chatService.sendMessage(
          currentUid, 
          widget.userId, 
          base64Image,
          type: 'image',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengirim gambar: $e')),
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
                  _buildAttachmentIcon(Icons.insert_drive_file, Colors.indigo, 'Document', onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fitur Document akan segera hadir!')));
                  }),
                  _buildAttachmentIcon(Icons.camera_alt, Colors.pink, 'Camera', onTap: () => _pickImage(ImageSource.camera, currentUid)),
                  _buildAttachmentIcon(Icons.photo, Colors.purple, 'Gallery', onTap: () => _pickImage(ImageSource.gallery, currentUid)),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildAttachmentIcon(Icons.headset, Colors.orange, 'Audio', onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fitur Audio akan segera hadir!')));
                  }),
                  _buildAttachmentIcon(Icons.location_on, Colors.green, 'Location', onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fitur Location akan segera hadir!')));
                  }),
                  _buildAttachmentIcon(Icons.person, Colors.blue, 'Contact', onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fitur Contact akan segera hadir!')));
                  }),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAttachmentIcon(IconData icon, Color color, String text, {required VoidCallback onTap}) {
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
          onTap: () {
            context.push('/profile/${widget.userId}');
          },
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.blueAccent,
                radius: 16,
                backgroundImage: _friendPhotoUrl.isNotEmpty ? ImageHelper.getImageProvider(_friendPhotoUrl) : null,
                child: _friendPhotoUrl.isEmpty ? const Icon(Icons.person, color: Colors.white, size: 16) : null,
              ),
              const SizedBox(width: 12),
              Text(_friendName),
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
                'currentUserName': currentUser.displayName ?? currentUser.email?.split('@')[0] ?? 'User',
                'friendUserId': widget.userId,
                'friendName': _friendName,
                'isIncoming': false,
              });
            },
          ),
          IconButton(
            icon: const Icon(Iconsax.more),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _chatService.getMessages(chatId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('Belum ada pesan.'));
                }

                final docs = snapshot.data!.docs;

                return ListView.builder(
                  reverse: true, // Pesan terbaru di bawah
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final isMe = data['senderId'] == currentUser.uid;
                    
                    return FutureBuilder<String>(
                      future: _chatService.decrypt(data['text'], chatId),
                      builder: (context, decSnapshot) {
                        final text = decSnapshot.data ?? '...';
                        
                        return GestureDetector(
                          onLongPress: () {
                            setState(() {
                              _replyingToMessage = {
                                'id': docs[index].id,
                                'text': text,
                              };
                            });
                          },
                          child: Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                              decoration: BoxDecoration(
                                color: isMe ? Theme.of(context).primaryColor : Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(16).copyWith(
                                  bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(16),
                                  bottomLeft: !isMe ? const Radius.circular(0) : const Radius.circular(16),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  if (data['replyToText'] != null)
                                    _buildReplyContext(data['replyToText'], isMe),
                                  if (data['type'] == 'image')
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ImageViewer(imageUrl: text),
                                          ),
                                        );
                                      },
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(maxHeight: 300),
                                          child: Hero(
                                            tag: text,
                                            child: ImageHelper.getImageWidget(text, fit: BoxFit.cover),
                                          ),
                                        ),
                                      ),
                                    )
                                  else
                                    Text(
                                      text,
                                      style: TextStyle(
                                        color: isMe ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color,
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isMe) ...[
                                        Icon(
                                          data['status'] == 'read' ? Icons.done_all : Icons.check,
                                          size: 14,
                                          color: data['status'] == 'read' ? Colors.lightBlueAccent : Colors.white70,
                                        ),
                                      ],
                                    ],
                                  )
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
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildReplyBanner(),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Iconsax.add),
                        onPressed: () => _showAttachmentBottomSheet(context),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: InputDecoration(
                            hintText: 'Type a message...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Theme.of(context).cardColor,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                          onSubmitted: (_) => _sendMessage(currentUser.uid),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: Theme.of(context).primaryColor,
                        child: IconButton(
                          icon: const Icon(Icons.send, color: Colors.white, size: 20),
                          onPressed: () => _sendMessage(currentUser.uid),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
