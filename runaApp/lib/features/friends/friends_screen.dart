import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:runa_app/core/services/auth_service.dart';
import 'package:runa_app/core/services/friend_service.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final FriendService _friendService = FriendService();

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final currentUser = authService.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: () {
              context.push('/search_friends');
            },
          )
        ],
      ),
      body: currentUser == null
          ? const Center(child: Text('Not Logged In'))
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: _friendService.getFriends(currentUser.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final myFriends = snapshot.data ?? [];

                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- SECTION: MY FRIENDS ---
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text(
                          'My Friends (\${myFriends.length})',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                        ),
                      ),
                      if (myFriends.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('Anda belum memiliki teman. Klik ikon tambah di atas untuk mencari teman!'),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: myFriends.length,
                          itemBuilder: (context, index) {
                            final friend = myFriends[index];
                            final name = friend['name'] as String;
                            final status = friend['status'] as String;
                            // Extract first letter safely
                            final firstLetter = name.isNotEmpty ? name[0].toUpperCase() : '?';

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.green, // Simulasi online
                                child: Text(
                                  firstLetter,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(status),
                              trailing: IconButton(
                                icon: const Icon(Icons.chat_bubble_outline),
                                onPressed: () {
                                  // Passing UID to chat screen instead of just name is better, 
                                  // but let's pass name for now to match routing format and handle inside ChatScreen
                                  // Actually we need friendUID to fetch messages from ChatService!
                                  // For now, let's just pass the UID in the path, but the path might be /chat/:id
                                  context.push('/chat/\${friend["uid"]}');
                                },
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
