import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:runa_app/core/services/auth_service.dart';
import 'package:runa_app/core/services/chat_service.dart';
import 'package:runa_app/core/services/group_service.dart';
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
  final GroupService _groupService = GroupService();
  late final Stream<List<Map<String, dynamic>>> _chatStream;
  late final Stream<List<Map<String, dynamic>>> _groupStream;
  late final Stream<List<Map<String, dynamic>>> _statusStream;

  @override
  void initState() {
    super.initState();
    final uid = context.read<AuthService>().currentUser?.uid ?? '';
    _chatStream = _chatService.getRecentChats(uid);
    _groupStream = _groupService.getUserGroups(uid);
    _statusStream = _statusService.getPublicStatuses(uid);
  }

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
                  hintText: 'Search friends...',
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
              stream: _chatStream,
              builder: (context, chatSnapshot) {
                if (chatSnapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text('Error: ${chatSnapshot.error}', textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(onPressed: () => setState(() {}), child: const Text('Retry')),
                      ],
                    ),
                  );
                }
                if (chatSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (chatSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final recentChats = chatSnapshot.data ?? [];

                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _groupStream,
                  builder: (context, groupSnapshot) {
                    final groups = groupSnapshot.data ?? [];

                    return StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _statusStream,
                      builder: (context, statusSnapshot) {
                        final statusGroups = statusSnapshot.data ?? [];

                        if (recentChats.isEmpty && groups.isEmpty) {
                          return const Center(
                            child: Text('No messages yet. Start chatting with friends!'),
                          );
                        }

                        // Combine groups and chats into a single list
                        final items = <Map<String, dynamic>>[];

                        // Add groups first
                        for (final group in groups) {
                          items.add({
                            'type': 'group',
                            'groupId': group['groupId'],
                            'name': group['name'],
                            'photoUrl': group['groupIcon'] ?? '',
                            'lastMessage': group['lastMessage'] ?? '',
                            'memberCount': (group['memberIds'] as List?)?.length ?? 0,
                          });
                        }

                        // Add individual chats
                        for (final chat in recentChats) {
                          items.add({
                            'type': 'chat',
                            ...chat,
                          });
                        }

                        return ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];

                            if (item['type'] == 'group') {
                              return _buildGroupTile(item);
                            } else {
                              return _buildChatTile(item, currentUser.uid, statusGroups);
                            }
                          },
                        );
                      },
                    );
                  },
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
                        Text('New Contact'),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'new_group',
                    child: Row(
                      children: [
                        Icon(Icons.group_add),
                        SizedBox(width: 12),
                        Text('Create Group'),
                      ],
                    ),
                  ),
                ],
              ).then((value) {
                if (value == 'new_contact') {
                  context.push('/search_friends');
                } else if (value == 'new_group') {
                  context.push('/create_group');
                }
              });
            },
            child: const Icon(Icons.chat),
          );
        }
      ),
    );
  }

  Widget _buildGroupTile(Map<String, dynamic> group) {
    final name = group['name'] as String;
    final photoUrl = group['photoUrl'] as String? ?? '';
    final groupId = group['groupId'] as String;
    final memberCount = group['memberCount'] as int;
    final firstLetter = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.deepPurple,
        backgroundImage: photoUrl.isNotEmpty ? ImageHelper.getImageProvider(photoUrl) : null,
        child: photoUrl.isEmpty
            ? Icon(Icons.group, color: Colors.white, size: 20)
            : null,
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(
        '$memberCount members',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.grey),
      ),
      onTap: () {
        context.push('/group/$groupId');
      },
    );
  }

  Widget _buildChatTile(
    Map<String, dynamic> chat,
    String currentUid,
    List<Map<String, dynamic>> statusGroups,
  ) {
    final name = chat['name'] as String;
    final firstLetter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final photoUrl = chat['photoUrl'] as String? ?? '';
    final chatUid = chat['uid'] as String;

    // Check status for this user
    final group = statusGroups.where((g) => g['uid'] == chatUid).firstOrNull;
    final hasStatus = group != null && (group['statuses'] as List).isNotEmpty;
    bool allViewed = true;
    if (hasStatus) {
      allViewed = _statusService.allViewed(group['statuses'] as List<Map<String, dynamic>>, currentUid);
    }
    final ringColor = hasStatus ? (allViewed ? Colors.grey : Colors.green) : Colors.transparent;

    return ListTile(
      leading: GestureDetector(
        onTap: hasStatus ? () {
          final statuses = group['statuses'] as List<Map<String, dynamic>>;
          // Mark as viewed
          for (final s in statuses) {
            if (!(s['viewed_by'] as List? ?? []).contains(currentUid)) {
              _statusService.markAsViewed(s['id'], currentUid);
            }
          }
          // Open status viewer
          Navigator.of(context).push(MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => StatusViewerScreen(
              statuses: statuses,
              viewerUid: currentUid,
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
  }
}
