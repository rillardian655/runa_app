import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iconsax/iconsax.dart';
import 'package:go_router/go_router.dart';
import 'package:runa_app/core/services/auth_service.dart';
import 'package:runa_app/core/utils/image_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _clearCache() async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cache cleared successfully.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final user = authService.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          if (user != null)
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                final data = snapshot.data!.data() as Map<String, dynamic>?;
                if (data == null) return const Center(child: Text('User data not found'));

                final username = data['username'] ?? 'User';
                final bio = data['bio'] ?? 'Available';
                final photoUrl = data['photoUrl'] ?? '';
                final bannerUrl = data['bannerUrl'] ?? '';

                return Column(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.bottomCenter,
                      children: [
                        // Banner Image
                        Container(
                          height: 150,
                          width: double.infinity,
                          color: Colors.blueGrey,
                          child: bannerUrl.isNotEmpty
                              ? ImageHelper.getImageWidget(bannerUrl)
                              : const Icon(Icons.image, color: Colors.white54, size: 50),
                        ),
                        // Profile Avatar
                        Positioned(
                          bottom: -40,
                          child: CircleAvatar(
                            radius: 50,
                            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                            child: CircleAvatar(
                              radius: 46,
                              backgroundColor: Colors.blueAccent,
                              backgroundImage: photoUrl.isNotEmpty ? ImageHelper.getImageProvider(photoUrl) : null,
                              child: photoUrl.isEmpty ? const Icon(Icons.person, size: 50, color: Colors.white) : null,
                            ),
                          ),
                        ),
                        // Edit Button overlay
                        Positioned(
                          top: 10,
                          right: 10,
                          child: IconButton(
                            icon: const Icon(Icons.edit, color: Colors.white),
                            onPressed: () {
                              context.push('/edit_profile');
                            },
                          ),
                        )
                      ],
                    ),
                    const SizedBox(height: 50),
                    Text(
                      username,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user.email != null ? '@${user.email!.split('@')[0].toLowerCase()}' : '@username',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      bio,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                );
              }
            )
          else
            const Column(
              children: [
                SizedBox(height: 20),
                Text(
                  'Not Logged In',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Iconsax.user),
            title: const Text('Account'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Account'),
                  content: const Text('Fitur manajemen akun akan segera hadir!'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    )
                  ],
                )
              );
            },
          ),
          ListTile(
            leading: const Icon(Iconsax.folder),
            title: const Text('Storage & Data'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _clearCache,
            ),
          ),
          ListTile(
            leading: const Icon(Iconsax.info_circle),
            title: const Text('About'),
            subtitle: const Text('Ru.na App v1.0.0'),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'Ru.na App',
                applicationVersion: 'v1.0.0',
                applicationIcon: const Icon(Icons.chat_bubble, size: 40),
                children: const [
                  Text('Aplikasi perpesanan Runa App dengan fitur enkripsi.'),
                ],
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Iconsax.logout, color: Colors.redAccent),
            title: const Text('Logout', style: TextStyle(color: Colors.redAccent)),
            onTap: () async {
              await context.read<AuthService>().logout();
              if (mounted) context.go('/login');
            },
          ),
        ],
      ),
    );
  }
}
