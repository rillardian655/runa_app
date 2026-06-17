import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:runa_app/core/services/auth_service.dart';
import 'package:runa_app/core/services/friend_service.dart';
import 'package:runa_app/core/utils/image_helper.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final FriendService _friendService = FriendService();

  Widget _buildUserAvatar(String photoUrl, String name, Color fallbackColor) {
    if (photoUrl.isNotEmpty) {
      return CircleAvatar(
        backgroundColor: Colors.grey,
        backgroundImage: ImageHelper.getImageProvider(photoUrl),
      );
    }
    final firstLetter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return CircleAvatar(
      backgroundColor: fallbackColor,
      child: Text(
        firstLetter,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final currentUser = authService.currentUser;

    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text('Not Logged In')));
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
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
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Discover'),
              Tab(text: 'My Friends'),
              Tab(text: 'Requests'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // TAB 1: Discover (Global Users)
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: _friendService.getAllUsers(currentUser.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final users = snapshot.data ?? [];
                if (users.isEmpty) return const Center(child: Text('No users found.'));

                return ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index];
                    final name = user['username'] ?? 'Unknown';
                    final bio = user['bio'] ?? 'Available';
                    final photoUrl = user['photoUrl'] ?? '';

                    return ListTile(
                      leading: _buildUserAvatar(photoUrl, name, Colors.blue),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(bio),
                      trailing: IconButton(
                        icon: const Icon(Icons.person_add),
                        onPressed: () {
                          _friendService.addFriendByUid(currentUser.uid, user['uid']);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Request sent!')),
                          );
                        },
                      ),
                      onTap: () => context.push('/profile/${user["uid"]}'),
                    );
                  },
                );
              },
            ),

            // TAB 2: My Friends
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: _friendService.getFriends(currentUser.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final myFriends = snapshot.data ?? [];
                if (myFriends.isEmpty) {
                  return const Center(child: Text('You have no friends yet.'));
                }

                return ListView.builder(
                  itemCount: myFriends.length,
                  itemBuilder: (context, index) {
                    final friend = myFriends[index];
                    final name = friend['name'] as String;
                    final status = friend['status'] as String;
                    // Note: getFriends response should be updated to include photoUrl
                    final photoUrl = friend['photoUrl'] ?? ''; 

                    return ListTile(
                      leading: _buildUserAvatar(photoUrl, name, Colors.green),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(status),
                      trailing: IconButton(
                        icon: const Icon(Icons.chat_bubble_outline),
                        onPressed: () {
                          context.push('/chat/${friend["uid"]}');
                        },
                      ),
                      onTap: () => context.push('/profile/${friend["uid"]}'),
                    );
                  },
                );
              },
            ),

            // TAB 3: Request History
            SingleChildScrollView(
              child: Column(
                children: [
                  // Received Requests
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _friendService.getPendingRequests(currentUser.uid),
                    builder: (context, snapshot) {
                      final requests = snapshot.data ?? [];
                      if (requests.isEmpty) return const SizedBox();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text('Received Requests', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: requests.length,
                            itemBuilder: (context, index) {
                              final req = requests[index];
                              return ListTile(
                                leading: _buildUserAvatar(req['photoUrl'] ?? '', req['name'], Colors.orange),
                                title: Text(req['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: const Text('Wants to be friends'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.check_circle, color: Colors.green),
                                      onPressed: () => _friendService.acceptFriendRequest(currentUser.uid, req['uid']),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.cancel, color: Colors.red),
                                      onPressed: () => _friendService.rejectFriendRequest(currentUser.uid, req['uid']),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                  // Sent Requests
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _friendService.getSentRequests(currentUser.uid),
                    builder: (context, snapshot) {
                      final requests = snapshot.data ?? [];
                      if (requests.isEmpty) return const SizedBox();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text('Sent Requests', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: requests.length,
                            itemBuilder: (context, index) {
                              final req = requests[index];
                              return ListTile(
                                leading: _buildUserAvatar(req['photoUrl'] ?? '', req['name'], Colors.blueGrey),
                                title: Text(req['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: const Text('Request sent (Pending)'),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
