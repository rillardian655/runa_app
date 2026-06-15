import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:runa_app/core/services/auth_service.dart';
import 'package:runa_app/core/services/status_service.dart';

class AddStatusScreen extends StatefulWidget {
  const AddStatusScreen({super.key});

  @override
  State<AddStatusScreen> createState() => _AddStatusScreenState();
}

class _AddStatusScreenState extends State<AddStatusScreen> {
  final TextEditingController _textController = TextEditingController();
  final StatusService _statusService = StatusService();
  bool _isLoading = false;
  int _selectedBgColorIndex = 0;
  XFile? _selectedImage;

  final List<Color> _bgColors = [
    const Color(0xFF1A1A2E),
    const Color(0xFF16213E),
    const Color(0xFF0F3460),
    const Color(0xFF533483),
    const Color(0xFF2D6A4F),
    const Color(0xFFD62828),
    const Color(0xFFF77F00),
    const Color(0xFF023E8A),
  ];

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 60);
    if (image != null) {
      setState(() => _selectedImage = image);
    }
  }

  Future<void> _postStatus() async {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    if (user == null) return;

    // Capture context-dependent objects before async gap
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // Fetch username and photoUrl from Firestore
    final userDoc = await auth.getUserData(user.uid);
    final username = userDoc?['username'] ?? user.email?.split('@')[0] ?? 'User';
    final photoUrl = userDoc?['photoUrl'] ?? '';

    setState(() => _isLoading = true);

    try {
      if (_selectedImage != null) {
        await _statusService.postImageStatus(
          uid: user.uid,
          username: username,
          photoUrl: photoUrl,
          imageFile: _selectedImage!,
        );
      } else {
        if (_textController.text.trim().isEmpty) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Tulis status dulu ya!')),
          );
          setState(() => _isLoading = false);
          return;
        }
        await _statusService.postTextStatus(
          uid: user.uid,
          username: username,
          photoUrl: photoUrl,
          content: _textController.text.trim(),
          bgColorValue: _bgColors[_selectedBgColorIndex].toARGB32(),
        );
      }
      if (mounted) navigator.pop();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Gagal posting status: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final previewBg = _bgColors[_selectedBgColorIndex];

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Buat Status'),
        actions: [
          if (!_isLoading)
            TextButton(
              onPressed: _postStatus,
              child: const Text('Kirim', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
          // --- Preview Area ---
          Expanded(
            child: _selectedImage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FutureBuilder<Uint8List>(
                          future: _selectedImage!.readAsBytes(),
                          builder: (context, snap) {
                            if (!snap.hasData) return const CircularProgressIndicator();
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.memory(snap.data!, height: 300, fit: BoxFit.cover),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: () => setState(() => _selectedImage = null),
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          label: const Text('Hapus Gambar', style: TextStyle(color: Colors.redAccent)),
                        ),
                      ],
                    ),
                  )
                : Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: previewBg,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(24),
                    child: TextField(
                      controller: _textController,
                      maxLines: null,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Tulis status kamu...',
                        hintStyle: TextStyle(color: Colors.white38, fontSize: 24),
                        border: InputBorder.none,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
          ),

          // --- Bottom Controls ---
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            color: const Color(0xFF1E1E1E),
            child: Column(
              children: [
                // Color picker row (only for text)
                if (_selectedImage == null) ...[
                  SizedBox(
                    height: 40,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _bgColors.length,
                      itemBuilder: (context, i) {
                        final selected = i == _selectedBgColorIndex;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedBgColorIndex = i),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: _bgColors[i],
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected ? Colors.white : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                            child: selected
                                ? const Icon(Icons.check, color: Colors.white, size: 16)
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // Add image button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Tambah Foto'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Helper widget
class ClipRounded extends StatelessWidget {
  final Widget child;
  const ClipRounded({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(borderRadius: BorderRadius.circular(12), child: child);
  }
}
