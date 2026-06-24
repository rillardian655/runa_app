import os

# 1. Fix StatusScreen typo
f1 = 'lib/features/status/status_screen.dart'
with open(f1, 'r') as f: content = f.read()
content = content.replace("snap.data?['photoUrl']", "snap.data?['photo_url']")
with open(f1, 'w') as f: f.write(content)

# 2. Fix StatusService video upload
f2 = 'lib/core/services/status_service.dart'
with open(f2, 'r') as f: content = f.read()

old_video = """    final fileName = '${uid}_${now.millisecondsSinceEpoch}.mp4';
    final bytes = await videoFile.readAsBytes();

    final ref = _storage.ref().child('status_media').child(fileName);
    await ref.putData(bytes, SettableMetadata(contentType: 'video/mp4'));
    final videoUrl = await ref.getDownloadURL();"""

new_video = """    final fileName = '${uid}_${now.millisecondsSinceEpoch}.mp4';
    final ref = _storage.ref().child('status_media').child(fileName);
    
    if (kIsWeb) {
      final bytes = await videoFile.readAsBytes();
      await ref.putData(bytes, SettableMetadata(contentType: 'video/mp4'));
    } else {
      await ref.putFile(File(videoFile.path), SettableMetadata(contentType: 'video/mp4'));
    }
    final videoUrl = await ref.getDownloadURL();"""

content = content.replace(old_video, new_video)
with open(f2, 'w') as f: f.write(content)

# 3. Fix EditProfileScreen image upload
f3 = 'lib/settings/edit_profile_screen.dart'
with open(f3, 'r') as f: content = f.read()

old_import = "import 'package:runa_app/core/utils/image_helper.dart';"
new_import = "import 'package:runa_app/core/utils/image_helper.dart';\nimport 'package:runa_app/core/services/storage_service.dart';"
if 'storage_service.dart' not in content:
    content = content.replace(old_import, new_import)

old_profile_upload = """      if (_profileImage != null) {
        final url = await _uploadImageAsBase64(_profileImage!);
        if (url != null) photoUrl = url;
      }

      if (_bannerImage != null) {
        final url = await _uploadImageAsBase64(_bannerImage!);
        if (url != null) bannerUrl = url;
      }"""

new_profile_upload = """      if (_profileImage != null) {
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
      }"""

content = content.replace(old_profile_upload, new_profile_upload)
with open(f3, 'w') as f: f.write(content)

print("All fixes applied!")
