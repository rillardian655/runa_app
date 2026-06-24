import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
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

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  final FriendService _friendService = FriendService();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).primaryColor,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Theme.of(context).primaryColor,
          tabs: const [
            Tab(text: 'Friends', icon: Icon(Iconsax.people)),
            Tab(text: 'Requests', icon: Icon(Iconsax.user_add)),
            Tab(text: 'Discover', icon: Icon(Iconsax.discover)),
          ],
        ),
      ),
      body: currentUser == null
          ? const Center(child: Text('Not Logged In'))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildFriendsTab(currentUser.uid),
                _buildRequestsTab(currentUser.uid),
                _buildDiscoverTab(currentUser.uid),
              ],
            ),
    );
  }

  Widget _buildFriendsTab(String currentUid) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _friendService.getFriends(currentUid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final myFriends = snapshot.data ?? [];

        if (myFriends.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                const Text(
                  'No friends yet',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Go to Discover tab to find people!',
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: myFriends.length,
          itemBuilder: (context, index) {
            final friend = myFriends[index];
            final name = friend['name'] as String;
            final status = friend['status'] as String;
            final photoUrl = friend['photoUrl'] as String? ?? '';
            final firstLetter =
                name.isNotEmpty ? name[0].toUpperCase() : '?';

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.green,
                backgroundImage:
                    photoUrl.isNotEmpty ? ImageHelper.getImageProvider(photoUrl) : null,
                child: photoUrl.isEmpty
                    ? Text(
                        firstLetter,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      )
                    : null,
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
        );
      },
    );
  }

  Widget _buildRequestsTab(String currentUid) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _friendService.getPendingRequests(currentUid),
      builder: (context, pendingSnapshot) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _friendService.getSentRequests(currentUid),
          builder: (context, sentSnapshot) {
            if (pendingSnapshot.connectionState == ConnectionState.waiting &&
                sentSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final pendingRequests = pendingSnapshot.data ?? [];
            final sentRequests = sentSnapshot.data ?? [];

            if (pendingRequests.isEmpty && sentRequests.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.mail_outline, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    const Text(
                      'No pending requests',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // Incoming requests
                if (pendingRequests.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      'Incoming (${pendingRequests.length})',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange),
                    ),
                  ),
                  ...pendingRequests.map((request) {
                    final name = request['name'] as String;
                    final uid = request['uid'] as String;
                    final photoUrl = request['photoUrl'] as String? ?? '';
                    final firstLetter =
                        name.isNotEmpty ? name[0].toUpperCase() : '?';

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.orange,
                        backgroundImage: photoUrl.isNotEmpty
                            ? ImageHelper.getImageProvider(photoUrl)
                            : null,
                        child: photoUrl.isEmpty
                            ? Text(
                                firstLetter,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              )
                            : null,
                      ),
                      title: Text(name,
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Wants to be your friend'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.check_circle,
                                color: Colors.green),
                            onPressed: () async {
                              await _friendService.acceptFriendRequest(
                                  currentUid, uid);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.cancel, color: Colors.red),
                            onPressed: () async {
                              await _friendService.rejectFriendRequest(
                                  currentUid, uid);
                            },
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(),
                ],

                // Sent requests (history)
                if (sentRequests.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      'Sent (${sentRequests.length})',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue),
                    ),
                  ),
                  ...sentRequests.map((request) {
                    final name = request['name'] as String;
                    final photoUrl = request['photoUrl'] as String? ?? '';
                    final firstLetter =
                        name.isNotEmpty ? name[0].toUpperCase() : '?';

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue,
                        backgroundImage: photoUrl.isNotEmpty
                            ? ImageHelper.getImageProvider(photoUrl)
                            : null,
                        child: photoUrl.isEmpty
                            ? Text(
                                firstLetter,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              )
                            : null,
                      ),
                      title: Text(name,
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Request sent'),
                      trailing: const Chip(
                        label: Text('Pending',
                            style: TextStyle(fontSize: 12)),
                        backgroundColor: Colors.blueGrey,
                      ),
                    );
                  }),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDiscoverTab(String currentUid) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _friendService.getAllUsers(currentUid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final allUsers = snapshot.data ?? [];

        if (allUsers.isEmpty) {
          return const Center(child: Text('No users found.'));
        }

        // Also get friend status for each user
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _friendService.getFriends(currentUid),
          builder: (context, friendsSnapshot) {
            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: _friendService.getPendingRequests(currentUid),
              builder: (context, pendingSnapshot) {
                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _friendService.getSentRequests(currentUid),
                  builder: (context, sentSnapshot) {
                    final friendUids = (friendsSnapshot.data ?? [])
                        .map((f) => f['uid'] as String)
                        .toSet();
                    final pendingUids = (pendingSnapshot.data ?? [])
                        .map((f) => f['uid'] as String)
                        .toSet();
                    final sentUids = (sentSnapshot.data ?? [])
                        .map((f) => f['uid'] as String)
                        .toSet();

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: allUsers.length,
                      itemBuilder: (context, index) {
                        final user = allUsers[index];
                        final username = user['username'] as String;
                        final bio = user['bio'] as String;
                        final photoUrl = user['photoUrl'] as String? ?? '';
                        final uid = user['uid'] as String;
                        final firstLetter = username.isNotEmpty
                            ? username[0].toUpperCase()
                            : '?';

                        final isFriend = friendUids.contains(uid);
                        final isPending = pendingUids.contains(uid);
                        final isSent = sentUids.contains(uid);

                        Widget trailingWidget;
                        if (isFriend) {
                          trailingWidget = const Chip(
                            label: Text('Friends',
                                style: TextStyle(fontSize: 12)),
                            backgroundColor: Colors.green,
                          );
                        } else if (isPending) {
                          trailingWidget = ElevatedButton(
                            onPressed: () async {
                              await _friendService.acceptFriendRequest(
                                  currentUid, uid);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20)),
                            ),
                            child: const Text('Accept',
                                style: TextStyle(color: Colors.white)),
                          );
                        } else if (isSent) {
                          trailingWidget = const Chip(
                            label: Text('Sent',
                                style: TextStyle(fontSize: 12)),
                            backgroundColor: Colors.blueGrey,
                          );
                        } else {
                          trailingWidget = ElevatedButton(
                            onPressed: () async {
                              await _friendService.addFriendByUid(
                                  currentUid, uid);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          'Friend request sent to @$username!')),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20)),
                            ),
                            child: const Text('Add'),
                          );
                        }

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.blueAccent,
                            backgroundImage: photoUrl.isNotEmpty
                                ? ImageHelper.getImageProvider(photoUrl)
                                : null,
                            child: photoUrl.isEmpty
                                ? Text(
                                    firstLetter,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold),
                                  )
                                : null,
                          ),
                          title: Text(username,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                          subtitle: Text(bio),
                          trailing: trailingWidget,
                          onTap: () {
                            context.push('/profile/$uid');
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
