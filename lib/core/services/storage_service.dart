import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Upload a file to Firebase Storage
  /// Returns the public URL on success, null on failure
  Future<String?> uploadFile(
    File file,
    String path, {
    Function(double)? onProgress,
    String? contentType,
  }) async {
    try {
      final fileSize = await file.length();
      // 25 MB limit
      if (fileSize > 25 * 1024 * 1024) {
        throw Exception('File size exceeds 25 MB');
      }

      final ref = _storage.ref().child(path);
      final task = ref.putFile(
        file,
        SettableMetadata(contentType: contentType ?? _inferContentType(path)),
      );

      if (onProgress != null) {
        task.snapshotEvents.listen((event) {
          final progress = event.bytesTransferred / event.totalBytes;
          onProgress(progress);
        });
      }

      await task;
      return await ref.getDownloadURL();
    } catch (e) {
      return null;
    }
  }

  /// Upload bytes directly (for web/cross-platform)
  Future<String?> uploadBytes(
    List<int> bytes,
    String path, {
    String? contentType,
  }) async {
    try {
      final ref = _storage.ref().child(path);
      await ref.putData(
        Uint8List.fromList(bytes),
        SettableMetadata(contentType: contentType ?? _inferContentType(path)),
      );
      return await ref.getDownloadURL();
    } catch (e) {
      return null;
    }
  }

  /// Upload avatar for a user
  Future<String?> uploadAvatar(File file, String uid) async {
    try {
      final ext = file.path.split('.').last.toLowerCase();
      final path = 'avatars/$uid.$ext';
      return await uploadFile(file, path);
    } catch (e) {
      return null;
    }
  }

  /// Delete a file from storage
  Future<void> deleteFile(String path) async {
    try {
      await _storage.ref().child(path).delete();
    } catch (_) {}
  }

  String _inferContentType(String path) {
    final ext = path.split('.').last.toLowerCase();
    const types = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'mp4': 'video/mp4',
      'mp3': 'audio/mpeg',
      'ogg': 'audio/ogg',
      'pdf': 'application/pdf',
    };
    return types[ext] ?? 'application/octet-stream';
  }
}
