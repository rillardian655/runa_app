import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:runa_app/core/services/auth_service.dart';
import 'package:runa_app/core/services/friend_service.dart';
import 'package:runa_app/core/services/group_service.dart';
import 'package:runa_app/core/utils/image_helper.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController _groupNameController = TextEditingController();
  final FriendService _friendService = FriendService();
  final GroupService _groupService = GroupService();
  final Set<String> _selectedMembers = {};
  bool _isLoading = false;

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    if (_groupNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group name')),
      );
      return;
    }

    if (_selectedMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one member')),
      );
      return;
    }

    final auth = context.read<AuthService>();
    final currentUser = auth.currentUser;
    if (currentUser == null) return;

    setState(() => _isLoading = true);

    try {
      final groupId = await _groupService.createGroup(
        name: _groupNameController.text.trim(),
        creatorId: currentUser.id,
        memberIds: _selectedMembers.toList(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group created successfully!')),
        );
        Navigator.pop(context, groupId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create group: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Group'),
        actions: [
          if (!_isLoading)
            TextButton(
              onPressed: _createGroup,
              child: const Text('Create', style: TextStyle(fontWeight: FontWeight.bold)),
            )
          else
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      body: Column(
        children: [
          // Group name input
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _groupNameController,
              decoration: InputDecoration(
                labelText: 'Group Name',
                prefixIcon: const Icon(Icons.group),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const Divider(),
          // Selected members count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.people, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${_selectedMembers.length} member${_selectedMembers.length != 1 ? 's' : ''} selected',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const Divider(),
          // Friends list
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _friendService.getFriends(currentUser.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final friends = snapshot.data ?? [];

                if (friends.isEmpty) {
                  return const Center(
                    child: Text('No friends yet. Add some friends first!'),
                  );
                }

                return ListView.builder(
                  itemCount: friends.length,
                  itemBuilder: (context, index) {
                    final friend = friends[index];
                    final uid = friend['uid'] as String;
                    final name = friend['name'] as String;
                    final photoUrl = friend['photoUrl'] as String? ?? '';
                    final isSelected = _selectedMembers.contains(uid);
                    final firstLetter = name.isNotEmpty ? name[0].toUpperCase() : '?';

                    return CheckboxListTile(
                      value: isSelected,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedMembers.add(uid);
                          } else {
                            _selectedMembers.remove(uid);
                          }
                        });
                      },
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(friend['status'] ?? 'Available'),
                      secondary: CircleAvatar(
                        backgroundColor: Colors.blueAccent,
                        backgroundImage: photoUrl.isNotEmpty ? ImageHelper.getImageProvider(photoUrl) : null,
                        child: photoUrl.isEmpty
                            ? Text(
                                firstLetter,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              )
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
