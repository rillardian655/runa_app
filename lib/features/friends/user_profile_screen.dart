import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:runa_app/core/utils/image_helper.dart';
import 'package:runa_app/core/services/auth_service.dart';
import 'package:runa_app/core/services/friend_service.dart';
import 'package:iconsax/iconsax.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;

  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final FriendService _friendService = FriendService();

  Future<void> _addFriend(String username) async {
    final currentUid = context.read<AuthService>().currentUser?.uid;
    if (currentUid == null) return;
    try {
      await _friendService.addFriendByUid(currentUid, widget.userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Permintaan pertemanan terkirim ke @$username!')),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menambahkan: $e')),
        );
      }
    }
  }

  Future<void> _unfriend() async {
    final currentUid = context.read<AuthService>().currentUser?.uid;
    if (currentUid == null) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unfriend?'),
        content: const Text('Anda yakin ingin menghapus pertemanan ini?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Unfriend', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _friendService.unfriend(currentUid, widget.userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pertemanan dihapus')),
        );
        setState(() {}); // refresh
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal unfriend: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthService>().currentUser;
    final isMe = currentUser?.uid == widget.userId;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('User not found'));
          }

          final data = snapshot.data!.data()!;
          final username = data['username'] ?? 'Unknown User';
          final bio = data['bio'] ?? 'Available';
          final photoUrl = data['photo_url'] ?? '';
          final bannerUrl = data['banner_url'] ?? '';
          final email = data['email'] ?? '';
          final presence = data['presence_status'] ?? 'offline';

          return ListView(
            children: [
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  Container(
                    height: 200,
                    width: double.infinity,
                    color: Colors.blueGrey,
                    child: bannerUrl.isNotEmpty
                        ? ImageHelper.getImageWidget(bannerUrl)
                        : const Icon(Icons.image,
                            color: Colors.white54, size: 80),
                  ),
                  Positioned(
                    bottom: -50,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          radius: 60,
                          backgroundColor:
                              Theme.of(context).scaffoldBackgroundColor,
                          child: CircleAvatar(
                            radius: 56,
                            backgroundColor: Colors.blueAccent,
                            backgroundImage: photoUrl.isNotEmpty
                                ? ImageHelper.getImageProvider(photoUrl)
                                : null,
                            child: photoUrl.isEmpty
                                ? const Icon(Icons.person,
                                    size: 60, color: Colors.white)
                                : null,
                          ),
                        ),
                        if (presence == 'online')
                          Positioned(
                            bottom: 5,
                            right: 15,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                                border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 4),
                              ),
                            ),
                          )
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 60),
              Column(
                children: [
                  Text(username,
                      style: const TextStyle(
                          fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    '@${email.split('@')[0].toLowerCase()}',
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  
                  if (!isMe && currentUser != null)
                    FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('friends')
                          .doc('${currentUser.uid}_${widget.userId}')
                          .get(),
                      builder: (context, friendSnap) {
                        final isFriend = friendSnap.hasData && friendSnap.data!.exists && friendSnap.data!['status'] == 'accepted';
                        final isRequested = friendSnap.hasData && friendSnap.data!.exists && friendSnap.data!['status'] == 'pending';
                        
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => context.push('/chat/${widget.userId}'),
                                  icon: const Icon(Iconsax.message),
                                  label: const Text('Chat'),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    context.push('/call', extra: {
                                      'callId': '',
                                      'currentUserId': currentUser.uid,
                                      'currentUserName': currentUser.displayName ?? currentUser.email?.split('@')[0] ?? 'User',
                                      'friendUserId': widget.userId,
                                      'friendName': username,
                                      'isIncoming': false,
                                    });
                                  },
                                  icon: const Icon(Iconsax.call),
                                  label: const Text('Call'),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              if (isFriend)
                                IconButton(
                                  onPressed: _unfriend,
                                  icon: const Icon(Icons.person_remove),
                                  color: Colors.red,
                                  tooltip: 'Unfriend',
                                )
                              else if (isRequested)
                                IconButton(
                                  onPressed: null,
                                  icon: const Icon(Icons.pending),
                                  tooltip: 'Requested',
                                )
                              else
                                IconButton(
                                  onPressed: () => _addFriend(username),
                                  icon: const Icon(Icons.person_add),
                                  color: Colors.blueAccent,
                                  tooltip: 'Add Friend',
                                )
                            ],
                          ),
                        );
                      }
                    ),
                  if (isMe)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: ElevatedButton.icon(
                        onPressed: () => context.push('/edit_profile').then((_) => setState(() {})),
                        icon: const Icon(Icons.edit),
                        label: const Text('Edit Profile'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  
                  const SizedBox(height: 24),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('About Me',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 8),
                        Text(bio, style: const TextStyle(fontSize: 15)),
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                            const SizedBox(width: 8),
                            Text(
                              data['created_at'] != null 
                                ? 'Joined ${DateTime.parse(data['created_at'].toDate().toString()).year}'
                                : 'Joined recently',
                              style: const TextStyle(color: Colors.grey),
                            )
                          ],
                        )
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
