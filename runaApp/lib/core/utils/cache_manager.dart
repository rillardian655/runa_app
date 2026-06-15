import 'dart:io';
import 'package:path_provider/path_provider.dart';

class CacheManager {
  static Future<double> getTotalCacheSizeMB() async {
    final cacheDir = await getTemporaryDirectory();
    int totalBytes = 0;
    if (cacheDir.existsSync()) {
      cacheDir.listSync(recursive: true).forEach((entity) {
        if (entity is File) {
          totalBytes += entity.lengthSync();
        }
      });
    }
    return totalBytes / (1024 * 1024);
  }

  static Future<void> clearAllCache() async {
    final cacheDir = await getTemporaryDirectory();
    if (cacheDir.existsSync()) {
      cacheDir.listSync(recursive: true).forEach((entity) {
        if (entity is File) {
          entity.deleteSync();
        }
      });
    }
  }
}
