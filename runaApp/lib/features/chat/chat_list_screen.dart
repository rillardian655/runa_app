import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:runa_app/core/services/auth_service.dart';
import 'package:runa_app/core/services/chat_service.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final ChatService _chatService = ChatService();

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

                return ListView.builder(
                  itemCount: recentChats.length,
                  itemBuilder: (context, index) {
                    final chat = recentChats[index];
                    final name = chat['name'] as String;
                    final firstLetter = name.isNotEmpty ? name[0].toUpperCase() : '?';

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blueAccent,
                        child: Text(
                          firstLetter,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(chat['lastMessage'], maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: const Text('Recent', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      onTap: () {
                        context.push('/chat/\${chat["uid"]}');
                      },
                    );
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Navigasi ke tab teman atau munculkan list teman
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pilih teman dari daftar Friends untuk mulai chat!')),
          );
        },
        child: const Icon(Icons.chat),
      ),
    );
  }
}
