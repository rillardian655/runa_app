import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:runa_app/core/services/auth_service.dart';
import 'package:runa_app/core/services/friend_service.dart';
import 'package:runa_app/core/utils/image_helper.dart';

class SearchFriendsScreen extends StatefulWidget {
  const SearchFriendsScreen({super.key});

  @override
  State<SearchFriendsScreen> createState() => _SearchFriendsScreenState();
}

class _SearchFriendsScreenState extends State<SearchFriendsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FriendService _friendService = FriendService();
  
  List<Map<String, dynamic>> _searchResults = [];
  bool _isLoading = false;

  Timer? _debounce;

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query.trim());
    });
  }

  void _performSearch(String query) async {
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isLoading = false;
        });
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final results = await _friendService.searchUsers(query);
      
      final authService = context.read<AuthService>();
      final currentUid = authService.currentUser?.uid;
      
      final filteredResults = results.where((user) => user['uid'] != currentUid).toList();

      if (mounted) {
        if (results.isNotEmpty && filteredResults.isEmpty) {
          // This means the only match was the user themselves
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Anda mencari diri sendiri!')),
          );
        }
        
        setState(() {
          _searchResults = filteredResults;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error during search: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _searchResults = []; // Clear results on error
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengambil data pengguna. Pastikan koneksi internet & Firebase Rules benar. Error: $e')),
        );
      }
    }
  }

  Future<void> _addFriend(String targetUid, String username) async {
    final authService = context.read<AuthService>();
    final currentUser = authService.currentUser;
    
    if (currentUser == null) return;

    try {
      await _friendService.addFriendByUid(currentUser.uid, targetUid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Permintaan pertemanan terkirim ke @$username!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menambahkan: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Cari username...',
            border: InputBorder.none,
          ),
          onChanged: _onSearchChanged,
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _searchResults.isEmpty
              ? const Center(child: Text('Tidak ada pengguna ditemukan.'))
              : ListView.builder(
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final user = _searchResults[index];
                    final username = user['username'] as String;
                    final bio = user['bio'] as String;
                    final photoUrl = user['photo_url'] as String? ?? '';
                    final firstLetter = username.isNotEmpty ? username[0].toUpperCase() : '?';

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blueAccent,
                        backgroundImage: photoUrl.isNotEmpty
                            ? ImageHelper.getImageProvider(photoUrl)
                            : null,
                        child: photoUrl.isEmpty
                            ? Text(
                                firstLetter,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              )
                            : null,
                      ),
                      title: Text(username, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(bio),
                      trailing: ElevatedButton(
                        onPressed: () => _addFriend(user['uid'], username),
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text('Add'),
                      ),
                    );
                  },
                ),
    );
  }
}
