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
              stream: _friendService.getPendingRequests(currentUser.uid),
              builder: (context, pendingSnapshot) {
                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _friendService.getFriends(currentUser.uid),
                  builder: (context, friendsSnapshot) {
                    if (pendingSnapshot.connectionState == ConnectionState.waiting &&
                        friendsSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final pendingRequests = pendingSnapshot.data ?? [];
                    final myFriends = friendsSnapshot.data ?? [];

                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // --- SECTION: FRIEND REQUESTS ---
                          if (pendingRequests.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                              child: Text(
                                'Friend Requests (\${pendingRequests.length})',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange),
                              ),
                            ),
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: pendingRequests.length,
                              itemBuilder: (context, index) {
                                final request = pendingRequests[index];
                                final name = request['name'] as String;
                                final uid = request['uid'] as String;
                                final firstLetter = name.isNotEmpty ? name[0].toUpperCase() : '?';

                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.orange,
                                    child: Text(
                                      firstLetter,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: const Text('Ingin berteman dengan Anda'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.check_circle, color: Colors.green),
                                        onPressed: () async {
                                          await _friendService.acceptFriendRequest(currentUser.uid, uid);
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.cancel, color: Colors.red),
                                        onPressed: () async {
                                          await _friendService.rejectFriendRequest(currentUser.uid, uid);
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            const Divider(),
                          ],

                          // --- SECTION: MY FRIENDS ---
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
                                final firstLetter = name.isNotEmpty ? name[0].toUpperCase() : '?';

                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.green,
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
                                      context.push('/chat/${friend["uid"]}');
                                    },
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
