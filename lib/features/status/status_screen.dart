import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:runa_app/core/services/auth_service.dart';
import 'package:runa_app/core/services/status_service.dart';
import 'package:runa_app/core/utils/image_helper.dart';
import 'package:runa_app/features/status/status_viewer_screen.dart';

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  final StatusService _statusService = StatusService();

  @override
  void initState() {
    super.initState();
    // Clean up expired statuses on screen load
    _statusService.cleanupExpiredStatuses().catchError((e) {
      debugPrint('Error cleaning up statuses: $e');
    });
  }

  void _openViewer(BuildContext context, List<Map<String, dynamic>> statuses,
      String ownerName, String ownerPhotoUrl, String currentUid, bool isOwn) {
    // Mark all as viewed
    for (final s in statuses) {
      final viewedBy = (s['viewed_by'] as List?) ?? const [];
      if (!viewedBy.contains(currentUid)) {
        _statusService.markAsViewed(s['id'], currentUid).catchError((e) {
          debugPrint('Error marking status as viewed: $e');
        });
      }
    }
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => StatusViewerScreen(
        statuses: statuses,
        viewerUid: currentUid,
        ownerName: ownerName,
        ownerPhotoUrl: ownerPhotoUrl,
        isOwn: isOwn,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final currentUser = authService.currentUser;
    if (currentUser == null) return const Scaffold(body: Center(child: Text('Not Logged In')));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Status'),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _statusService.getPublicStatuses(currentUser.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Error loading statuses: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            );
          }

          final groups = snapshot.data ?? [];
          final ownGroup = groups.where((g) => g['uid'] == currentUser.id).firstOrNull;
          final otherGroups = groups.where((g) => g['uid'] != currentUser.id).toList();

          return ListView(
            children: [
              // ── MY STATUS ──────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('Status Saya',
                    style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5)),
              ),
              _buildMyStatusTile(context, currentUser.id, ownGroup),

              // ── OTHER USERS' STATUS ─────────────────────
              if (otherGroups.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('Update Terkini',
                      style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5)),
                ),
                ...otherGroups.map((group) => _buildOtherStatusTile(context, group, currentUser.id)),
              ] else
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.people_outline, size: 56, color: Colors.grey[600]),
                        const SizedBox(height: 12),
                        Text('Belum ada status dari pengguna lain.',
                            style: TextStyle(color: Colors.grey[500])),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/status/add'),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildMyStatusTile(BuildContext context, String uid, Map<String, dynamic>? ownGroup) {
    final hasStatus = ownGroup != null && (ownGroup['statuses'] as List).isNotEmpty;
    final statuses = (hasStatus && ownGroup != null) ? ownGroup['statuses'] as List<Map<String, dynamic>> : <Map<String, dynamic>>[];

    return FutureBuilder<Map<String, dynamic>?>(
      future: context.read<AuthService>().getUserData(uid),
      builder: (context, snap) {
        final username = snap.data?['username'] ?? 'Saya';
        final photoUrl = snap.data?['photoUrl'] ?? '';

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: _buildAvatarRing(
            photoUrl: photoUrl,
            label: username,
            hasStatus: hasStatus,
            allViewed: false,
            onAddTap: () => context.push('/status/add'),
            showAdd: true,
          ),
          title: Text(username, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            hasStatus ? 'Tap untuk lihat status kamu' : 'Tap untuk tambah status',
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
          onTap: hasStatus
              ? () => _openViewer(context, statuses, username, photoUrl, uid, true)
              : () => context.push('/status/add'),
        );
      },
    );
  }

  Widget _buildOtherStatusTile(BuildContext context, Map<String, dynamic> group, String currentUid) {
    final statuses = group['statuses'] as List<Map<String, dynamic>>;
    final username = group['username'] as String;
    final photoUrl = group['photoUrl'] as String;
    final allViewed = _statusService.allViewed(statuses, currentUid);

    final latest = group['latestTimestamp'];
    final timeAgo = _formatTimeAgo(latest);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: _buildAvatarRing(
        photoUrl: photoUrl,
        label: username,
        hasStatus: true,
        allViewed: allViewed,
        showAdd: false,
      ),
      title: Text(username, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(timeAgo, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
      onTap: () => _openViewer(context, statuses, username, photoUrl, currentUid, false),
    );
  }

  Widget _buildAvatarRing({
    required String photoUrl,
    required String label,
    required bool hasStatus,
    required bool allViewed,
    bool showAdd = false,
    VoidCallback? onAddTap,
  }) {
    final ringColor = hasStatus
        ? (allViewed ? Colors.grey : Colors.green)
        : Colors.transparent;

    return GestureDetector(
      onTap: showAdd && !hasStatus ? onAddTap : null,
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: ringColor, width: 2.5),
            ),
            child: CircleAvatar(
              radius: 26,
              backgroundColor: Colors.blueAccent,
              backgroundImage: photoUrl.isNotEmpty ? ImageHelper.getImageProvider(photoUrl) : null,
              child: photoUrl.isEmpty
                  ? Text(label.isNotEmpty ? label[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                  : null,
            ),
          ),
          if (showAdd)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 1.5),
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 13),
              ),
            ),
        ],
      ),
    );
  }

  String _formatTimeAgo(dynamic timestamp) {
    if (timestamp == null) return '';
    DateTime? dt;
    if (timestamp is DateTime) {
      dt = timestamp;
    } else if (timestamp is String) {
      dt = DateTime.tryParse(timestamp);
    } else {
      dt = timestamp.toDate();
    }
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    return '${diff.inDays} hari lalu';
  }
}
