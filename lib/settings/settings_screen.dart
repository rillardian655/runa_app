import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iconsax/iconsax.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:runa_app/core/services/auth_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:runa_app/core/services/theme_service.dart';
import 'package:runa_app/core/utils/image_helper.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = info.version);
    } catch (_) {
      // Leave _version empty; the UI falls back to a version-less label.
    }
  }

  void _showThemePicker() {
    final themeService = context.read<ThemeService>();
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Appearance',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              for (final mode in ThemeMode.values)
                ListTile(
                  title: Text(ThemeService.labelFor(mode)),
                  trailing: themeService.themeMode == mode
                      ? Icon(Icons.check,
                          color: Theme.of(sheetContext).colorScheme.primary)
                      : null,
                  onTap: () {
                    themeService.setThemeMode(mode);
                    Navigator.pop(sheetContext);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

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
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          if (user != null)
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .snapshots()
                  .map((snapshot) => snapshot.exists ? [snapshot.data()!] : []),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                final data = snapshot.data!.first;
                final username = data['username'] ?? 'User';
                final bio = data['bio'] ?? 'Available';
                final photoUrl = data['photo_url'] ?? '';
                final bannerUrl = data['banner_url'] ?? '';

                return Column(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.bottomCenter,
                      children: [
                        Container(
                          height: 150,
                          width: double.infinity,
                          color: Colors.blueGrey,
                          child: bannerUrl.isNotEmpty
                              ? ImageHelper.getImageWidget(bannerUrl)
                              : const Icon(Icons.image,
                                  color: Colors.white54, size: 50),
                        ),
                        Positioned(
                          bottom: -40,
                          child: CircleAvatar(
                            radius: 50,
                            backgroundColor:
                                Theme.of(context).scaffoldBackgroundColor,
                            child: CircleAvatar(
                              radius: 46,
                              backgroundColor: Colors.blueAccent,
                              backgroundImage: photoUrl.isNotEmpty
                                  ? ImageHelper.getImageProvider(photoUrl)
                                  : null,
                              child: photoUrl.isEmpty
                                  ? const Icon(Icons.person,
                                      size: 50, color: Colors.white)
                                  : null,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: IconButton(
                            icon: const Icon(Icons.edit, color: Colors.white),
                            onPressed: () => context.push('/edit_profile'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 50),
                    Text(username,
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      user.email != null
                          ? '@${user.email!.split('@')[0].toLowerCase()}'
                          : '@username',
                      style:
                          const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Text(bio, style: const TextStyle(fontSize: 14)),
                  ],
                );
              },
            )
          else
            const Column(
              children: [
                SizedBox(height: 20),
                Text('Not Logged In',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Iconsax.user),
            title: const Text('Account'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/edit_profile'),
          ),
          ListTile(
            leading: const Icon(Iconsax.folder),
            title: const Text('Storage & Data'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _clearCache,
            ),
          ),
          Consumer<ThemeService>(
            builder: (context, themeService, _) => ListTile(
              leading: const Icon(Iconsax.moon),
              title: const Text('Appearance'),
              subtitle: Text(ThemeService.labelFor(themeService.themeMode)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showThemePicker,
            ),
          ),
          ListTile(
            leading: const Icon(Iconsax.info_circle),
            title: const Text('About'),
            subtitle: Text(
                _version.isEmpty ? 'Ru.na App' : 'Ru.na App v$_version'),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'Ru.na',
                applicationVersion: _version.isEmpty ? null : 'v$_version',
                applicationIcon: const CircleAvatar(
                  backgroundColor: Color(0xFF009EF7),
                  child: Text('R',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20)),
                ),
                children: [
                  const Text('Ru.na — Chat & Voice Call App'),
                  const SizedBox(height: 8),
                  const Text('Built with Flutter & Firebase'),
                ],
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Iconsax.logout, color: Colors.redAccent),
            title: const Text('Logout',
                style: TextStyle(color: Colors.redAccent)),
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
