import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:runa_app/core/services/auth_service.dart';
import 'package:runa_app/core/services/chat_service.dart';
import 'package:runa_app/core/services/status_service.dart';
import 'package:runa_app/core/utils/image_helper.dart';
import 'package:runa_app/features/status/status_viewer_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final ChatService _chatService = ChatService();
  final StatusService _statusService = StatusService();

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final currentUser = authService.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Cari teman...',
                  border: InputBorder.none,
                ),
                style: const TextStyle(fontSize: 18),
              )
            : const Text('Chats'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                }
              });
            },
          )
        ],
      ),
      body: currentUser == null
          ? const Center(child: Text('Not Logged In'))
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: _chatService.getRecentChats(currentUser.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final recentChats = snapshot.data ?? [];

                if (recentChats.isEmpty) {
                  return const Center(child: Text('Belum ada pesan. Mulai chat dengan teman!'));
                }

                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _statusService.getPublicStatuses(currentUser.uid),
                  builder: (context, statusSnapshot) {
                    final statusGroups = statusSnapshot.data ?? [];

                    return ListView.builder(
                      itemCount: recentChats.length,
                      itemBuilder: (context, index) {
                        final chat = recentChats[index];
                        final name = chat['name'] as String;
                        final firstLetter = name.isNotEmpty ? name[0].toUpperCase() : '?';
                        final photoUrl = chat['photoUrl'] as String? ?? '';
                        final chatUid = chat['uid'] as String;

                        // Check status for this user
                        final group = statusGroups.where((g) => g['uid'] == chatUid).firstOrNull;
                        final hasStatus = group != null && (group['statuses'] as List).isNotEmpty;
                        bool allViewed = true;
                        if (hasStatus) {
                          allViewed = _statusService.allViewed(group['statuses'] as List<Map<String, dynamic>>, currentUser.uid);
                        }
                        final ringColor = hasStatus ? (allViewed ? Colors.grey : Colors.green) : Colors.transparent;

                        return ListTile(
                          leading: GestureDetector(
                            onTap: hasStatus ? () {
                              final statuses = group['statuses'] as List<Map<String, dynamic>>;
                              // Mark as viewed
                              for (final s in statuses) {
                                if (!(s['viewedBy'] as List).contains(currentUser.uid)) {
                                  _statusService.markAsViewed(s['id'], currentUser.uid);
                                }
                              }
                              // Open status viewer
                              Navigator.of(context).push(MaterialPageRoute(
                                fullscreenDialog: true,
                                builder: (_) => StatusViewerScreen(
                                  statuses: statuses,
                                  viewerUid: currentUser.uid,
                                  ownerName: name,
                                  ownerPhotoUrl: photoUrl,
                                  isOwn: false,
                                ),
                              ));
                            } : null,
                            child: Container(
                              padding: const EdgeInsets.all(2.5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: ringColor, width: 2.5),
                              ),
                              child: CircleAvatar(
                                backgroundColor: Colors.blueAccent,
                                backgroundImage: photoUrl.isNotEmpty ? ImageHelper.getImageProvider(photoUrl) : null,
                                child: photoUrl.isEmpty ? Text(
                                  firstLetter,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ) : null,
                              ),
                            ),
                          ),
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            chat['lastMessage'], 
                            maxLines: 1, 
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: (chat['unreadCount'] ?? 0) > 0 ? FontWeight.bold : FontWeight.normal,
                              color: (chat['unreadCount'] ?? 0) > 0 ? Theme.of(context).textTheme.bodyLarge?.color : Colors.grey,
                            ),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('Recent', style: TextStyle(color: Colors.grey, fontSize: 12)),
                              if ((chat['unreadCount'] ?? 0) > 0)
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    chat['unreadCount'].toString(),
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                            ],
                          ),
                          onTap: () {
                            context.push('/chat/${chat["uid"]}');
                          },
                        );
                      },
                    );
                  }
                );
              },
            ),
      floatingActionButton: Builder(
        builder: (context) {
          return FloatingActionButton(
            onPressed: () {
              final RenderBox button = context.findRenderObject() as RenderBox;
              final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
              final RelativeRect position = RelativeRect.fromRect(
                Rect.fromPoints(
                  button.localToGlobal(const Offset(0, -100), ancestor: overlay),
                  button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
                ),
                Offset.zero & overlay.size,
              );

              showMenu<String>(
                context: context,
                position: position,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                items: [
                  const PopupMenuItem<String>(
                    value: 'new_contact',
                    child: Row(
                      children: [
                        Icon(Icons.person_add_alt_1),
                        SizedBox(width: 12),
                        Text('Kontak Baru'),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'new_group',
                    child: Row(
                      children: [
                        Icon(Icons.group_add),
                        SizedBox(width: 12),
                        Text('Buat Grup'),
                      ],
                    ),
                  ),
                ],
              ).then((value) {
                if (value == 'new_contact') {
                  context.push('/search_friends');
                } else if (value == 'new_group') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Fitur Buat Grup akan segera hadir!')),
                  );
                }
              });
            },
            child: const Icon(Icons.chat),
          );
        }
      ),
    );
  }
}
