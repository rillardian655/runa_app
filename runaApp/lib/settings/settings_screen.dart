import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iconsax/iconsax.dart';
import 'package:go_router/go_router.dart';
import 'package:runa_app/core/services/auth_service.dart';
import 'package:runa_app/core/utils/cache_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _cacheSizeMB = 0.0;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    final size = await CacheManager.getTotalCacheSizeMB();
    if (mounted) {
      setState(() {
        _cacheSizeMB = size;
      });
    }
  }

  Future<void> _clearCache() async {
    await CacheManager.clearAllCache();
    _loadCacheSize();
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
          const SizedBox(height: 20),
          const CircleAvatar(
            radius: 50,
            backgroundColor: Colors.blueAccent,
            child: Icon(Icons.person, size: 50, color: Colors.white),
          ),
          const SizedBox(height: 16),
          if (user != null)
            Column(
              children: [
                Text(
                  user.displayName ?? user.email?.split('@')[0] ?? 'User',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  user.email != null ? '@${user.email!.split('@')[0].toLowerCase()}' : '@username',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Available',
                  style: TextStyle(fontSize: 14),
                ),
              ],
            )
          else
            const Column(
              children: [
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
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Iconsax.folder),
            title: const Text('Storage & Data'),
            subtitle: Text('${_cacheSizeMB.toStringAsFixed(2)} MB cached data'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _clearCache,
            ),
          ),
          ListTile(
            leading: const Icon(Iconsax.info_circle),
            title: const Text('About'),
            subtitle: const Text('Ru.na App v1.0.0'),
            onTap: () {},
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
