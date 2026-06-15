import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';
import 'package:runa_app/core/services/auth_service.dart';
import 'package:runa_app/core/services/chat_service.dart';
import 'package:runa_app/core/services/signaling_service.dart';
import 'package:runa_app/features/call/incoming_call_overlay.dart';
import 'package:runa_app/features/chat/chat_list_screen.dart';
import 'package:runa_app/features/friends/friends_screen.dart';
import 'package:runa_app/features/status/status_screen.dart';
import 'package:runa_app/settings/settings_screen.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;
  StreamSubscription? _incomingCallSubscription;
  final SignalingService _signalingService = SignalingService();
  bool _isShowingIncomingCall = false;

  final List<Widget> _pages = const [
    ChatListScreen(),
    StatusScreen(),
    FriendsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startListeningForCalls();
    });
  }

  void _startListeningForCalls() {
    final authService = context.read<AuthService>();
    final currentUser = authService.currentUser;
    if (currentUser == null) return;

    _incomingCallSubscription?.cancel();
    _incomingCallSubscription = _signalingService
        .listenForIncomingCalls(currentUser.uid)
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty && !_isShowingIncomingCall) {
        final callDoc = snapshot.docs.first;
        final data = callDoc.data() as Map<String, dynamic>;
        _showIncomingCallDialog(
          callId: callDoc.id,
          callerName: data['callerName'] ?? 'Unknown',
          callerId: data['callerId'] ?? '',
        );
      }
    });
  }

  void _showIncomingCallDialog({
    required String callId,
    required String callerName,
    required String callerId,
  }) {
    if (_isShowingIncomingCall) return;
    _isShowingIncomingCall = true;

    final currentUser = context.read<AuthService>().currentUser;
    if (currentUser == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return IncomingCallOverlay(
          callerName: callerName,
          callId: callId,
          onAccept: () {
            Navigator.of(dialogContext).pop();
            _isShowingIncomingCall = false;
            context.push('/call', extra: {
              'callId': callId,
              'currentUserId': currentUser.uid,
              'currentUserName': currentUser.displayName ?? currentUser.email?.split('@')[0] ?? 'User',
              'friendUserId': callerId,
              'friendName': callerName,
              'isIncoming': true,
            });
          },
          onReject: () async {
            Navigator.of(dialogContext).pop();
            _isShowingIncomingCall = false;
            await _signalingService.rejectCall(callId);
          },
        );
      },
    ).then((_) {
      _isShowingIncomingCall = false;
    });
  }

  @override
  void dispose() {
    _incomingCallSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final currentUser = authService.currentUser;

    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: StreamBuilder<List<Map<String, dynamic>>>(
        stream: currentUser != null
            ? ChatService().getRecentChats(currentUser.uid)
            : const Stream.empty(),
        builder: (context, snapshot) {
          int totalUnread = 0;
          if (snapshot.hasData) {
            for (var chat in snapshot.data!) {
              totalUnread += (chat['unreadCount'] ?? 0) as int;
            }
          }

          return BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            type: BottomNavigationBarType.fixed,
            items: [
              BottomNavigationBarItem(
                icon: Badge(
                  isLabelVisible: totalUnread > 0,
                  label: Text(totalUnread.toString()),
                  child: const Icon(Iconsax.message),
                ),
                activeIcon: Badge(
                  isLabelVisible: totalUnread > 0,
                  label: Text(totalUnread.toString()),
                  child: const Icon(Iconsax.message5),
                ),
                label: 'Chats',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Iconsax.status),
                activeIcon: Icon(Iconsax.status5),
                label: 'Status',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Iconsax.people),
                activeIcon: Icon(Iconsax.people5),
                label: 'Friends',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Iconsax.setting),
                activeIcon: Icon(Iconsax.setting5),
                label: 'Settings',
              ),
            ],
          );
        },
      ),
    );
  }
}
