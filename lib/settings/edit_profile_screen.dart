import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:runa_app/core/services/auth_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:runa_app/core/utils/image_helper.dart';
import 'package:runa_app/core/services/storage_service.dart';
import 'package:go_router/go_router.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();

  bool _isLoading = false;

  XFile? _profileImage;
  XFile? _bannerImage;

  String _currentPhotoUrl = '';
  String _currentBannerUrl = '';
  Map<String, dynamic>? _userData;

  @override
  void initState() {
    super.initState();
    _loadCurrentData();
  }

  Future<void> _loadCurrentData() async {
    final user = context.read<AuthService>().currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _userData = data;
          _usernameController.text = data['username'] ?? '';
          _bioController.text = data['bio'] ?? '';
          _currentPhotoUrl = data['photo_url'] ?? '';
          _currentBannerUrl = data['banner_url'] ?? '';
        });
      }
    }
  }

  bool _canChangeUsername() {
    if (_userData == null) return true;
    final lastChanged = _userData!['username_last_changed'] as String?;
    if (lastChanged == null) return true;
    final lastChangedDate = DateTime.parse(lastChanged);
    final daysSinceChange = DateTime.now().difference(lastChangedDate).inDays;
    return daysSinceChange >= 14;
  }

  int _daysUntilNextChange() {
    if (_userData == null) return 0;
    final lastChanged = _userData!['username_last_changed'] as String?;
    if (lastChanged == null) return 0;
    final lastChangedDate = DateTime.parse(lastChanged);
    final daysSinceChange = DateTime.now().difference(lastChangedDate).inDays;
    return 14 - daysSinceChange;
  }

  Future<void> _pickImage(bool isBanner) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 30,
      maxWidth: isBanner ? 800 : 400,
    );

    if (pickedFile != null) {
      setState(() {
        if (isBanner) {
          _bannerImage = pickedFile;
        } else {
          _profileImage = pickedFile;
        }
      });
    }
  }

  Future<String?> _uploadImageAsBase64(XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      final base64String = base64Encode(bytes);
      String mimeType = 'image/jpeg';
      if (file.name.toLowerCase().endsWith('.png')) mimeType = 'image/png';
      return 'data:$mimeType;base64,$base64String';
    } catch (e) {
      debugPrint('Error converting image: $e');
      return null;
    }
  }

  Future<void> _saveChanges() async {
    final user = context.read<AuthService>().currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final currentUsername = _userData?['username'] ?? '';
      final newUsername = _usernameController.text.trim();
      final usernameChanged = currentUsername != newUsername;

      if (usernameChanged && !_canChangeUsername()) {
        final daysLeft = _daysUntilNextChange();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'You can change your username again in $daysLeft days')));
          setState(() => _isLoading = false);
        }
        return;
      }

      String photoUrl = _currentPhotoUrl;
      String bannerUrl = _currentBannerUrl;

      if (_profileImage != null) {
        if (kIsWeb) {
          final url = await _uploadImageAsBase64(_profileImage!);
          if (url != null) photoUrl = url;
        } else {
          final url = await StorageService().uploadAvatar(File(_profileImage!.path), user.uid);
          if (url != null) photoUrl = url;
        }
      }

      if (_bannerImage != null) {
        if (kIsWeb) {
          final url = await _uploadImageAsBase64(_bannerImage!);
          if (url != null) bannerUrl = url;
        } else {
          final url = await StorageService().uploadFile(File(_bannerImage!.path), 'banners/${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg');
          if (url != null) bannerUrl = url;
        }
      }

      final updateData = <String, dynamic>{
        'uid': user.uid,
        'username': newUsername,
        'bio': _bioController.text.trim(),
        'photo_url': photoUrl,
        'banner_url': bannerUrl,
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (usernameChanged) {
        updateData['username_last_changed'] =
            DateTime.now().toIso8601String();
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(updateData, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile updated successfully!')));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to update: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canChange = _canChangeUsername();
    final daysLeft = _daysUntilNextChange();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          _isLoading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.check), onPressed: _saveChanges),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Banner Edit
          GestureDetector(
            onTap: () => _pickImage(true),
            child: Container(
              height: 150,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(12),
                image: _bannerImage != null
                    ? DecorationImage(
                        image: kIsWeb
                            ? NetworkImage(_bannerImage!.path) as ImageProvider
                            : FileImage(File(_bannerImage!.path)),
                        fit: BoxFit.cover)
                    : (_currentBannerUrl.isNotEmpty
                        ? DecorationImage(
                            image: ImageHelper.getImageProvider(
                                _currentBannerUrl),
                            fit: BoxFit.cover)
                        : null),
              ),
              child: _bannerImage == null && _currentBannerUrl.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.camera_alt,
                              color: Colors.white54, size: 40),
                          Text('Tap to change banner',
                              style: TextStyle(color: Colors.white54)),
                        ],
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 24),

          // Profile Photo Edit
          Center(
            child: GestureDetector(
              onTap: () => _pickImage(false),
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.blueAccent,
                    backgroundImage: _profileImage != null
                        ? (kIsWeb
                            ? NetworkImage(_profileImage!.path) as ImageProvider
                            : FileImage(File(_profileImage!.path)))
                        : (_currentPhotoUrl.isNotEmpty
                            ? ImageHelper.getImageProvider(_currentPhotoUrl)
                            : null),
                    child: _profileImage == null && _currentPhotoUrl.isEmpty
                        ? const Icon(Icons.person,
                            size: 50, color: Colors.white)
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                          color: Colors.blue, shape: BoxShape.circle),
                      child:
                          const Icon(Icons.edit, size: 20, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          TextField(
            controller: _usernameController,
            enabled: canChange,
            decoration: InputDecoration(
              labelText: 'Username',
              prefixIcon: const Icon(Icons.person),
              helperText: canChange
                  ? null
                  : 'You can change your username in $daysLeft days',
              helperStyle: const TextStyle(color: Colors.orange),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _bioController,
            decoration: const InputDecoration(
              labelText: 'Bio',
              prefixIcon: Icon(Icons.info_outline),
            ),
          ),
        ],
      ),
    );
  }
}
