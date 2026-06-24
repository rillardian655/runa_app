import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdateService {
  static const String _collectionName = 'app_versions';
  
  /// Check if there's a new version available
  static Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      // Get current app version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      
      // Get latest version from Firebase
      final snapshot = await FirebaseFirestore.instance
          .collection(_collectionName)
          .where('platform', isEqualTo: 'android')
          .orderBy('created_at', descending: true)
          .limit(1)
          .get();
      
      if (snapshot.docs.isEmpty) {
        debugPrint('[AppUpdate] No version info found in database');
        return null;
      }
      
      final response = snapshot.docs.first.data();
      final latestVersion = response['version'] as String;
      final downloadUrl = response['download_url'] as String?;
      final changelog = response['changelog'] as String?;
      final forceUpdate = response['force_update'] as bool? ?? false;
      
      // Compare versions
      if (_isNewerVersion(currentVersion, latestVersion)) {
        return AppUpdateInfo(
          currentVersion: currentVersion,
          latestVersion: latestVersion,
          downloadUrl: downloadUrl,
          changelog: changelog,
          forceUpdate: forceUpdate,
        );
      }
      
      return null;
    } catch (e) {
      debugPrint('[AppUpdate] Error checking for updates: $e');
      return null;
    }
  }
  
  /// Compare version strings (e.g., "1.0.15" vs "1.0.16")
  static bool _isNewerVersion(String current, String latest) {
    final currentParts = current.split('.').map(int.parse).toList();
    final latestParts = latest.split('.').map(int.parse).toList();
    
    // Pad with zeros if needed
    while (currentParts.length < 3) currentParts.add(0);
    while (latestParts.length < 3) latestParts.add(0);
    
    for (int i = 0; i < 3; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    
    return false;
  }
  
  /// Show update dialog
  static Future<void> showUpdateDialog(
    BuildContext context,
    AppUpdateInfo updateInfo,
  ) async {
    return showDialog(
      context: context,
      barrierDismissible: !updateInfo.forceUpdate,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.system_update, color: Colors.blue),
            const SizedBox(width: 8),
            const Text('Update Available'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A new version of Ru.na is available!',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current: v${updateInfo.currentVersion}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    'Latest: v${updateInfo.latestVersion}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
            ),
            if (updateInfo.changelog != null && updateInfo.changelog!.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'What\'s New:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                updateInfo.changelog!,
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ],
        ),
        actions: [
          if (!updateInfo.forceUpdate)
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Later'),
            ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              if (updateInfo.downloadUrl != null) {
                await _launchDownload(updateInfo.downloadUrl!);
              }
            },
            icon: const Icon(Icons.download),
            label: const Text('Update Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
  
  /// Launch download URL
  static Future<void> _launchDownload(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        debugPrint('[AppUpdate] Could not launch URL: $url');
      }
    } catch (e) {
      debugPrint('[AppUpdate] Error launching download: $e');
    }
  }
}

class AppUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String? downloadUrl;
  final String? changelog;
  final bool forceUpdate;
  
  AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    this.downloadUrl,
    this.changelog,
    this.forceUpdate = false,
  });
}
