import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';
import 'package:runa_app/core/services/auth_service.dart';
import 'package:runa_app/core/services/chat_service.dart';
import 'package:runa_app/core/services/notification_service.dart';
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
  final ChatService _chatService = ChatService();
  bool _isShowingIncomingCall = false;
  late PageController _pageController;
  Stream<List<Map<String, dynamic>>>? _unreadStream;

  final List<Widget> _pages = const [
    ChatListScreen(),
    StatusScreen(),
    FriendsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startListeningForCalls();
      final uid = context.read<AuthService>().currentUser?.id;
      if (uid != null) {
        _unreadStream = _chatService.getRecentChats(uid);
      }
    });
  }

  void _startListeningForCalls() {
    final authService = context.read<AuthService>();
    final currentUser = authService.currentUser;
    if (currentUser == null) return;

    _incomingCallSubscription?.cancel();
    _incomingCallSubscription = _signalingService
        .listenForIncomingCalls(currentUser.id)
        .listen((calls) {
      if (calls.isNotEmpty && !_isShowingIncomingCall) {
        final callData = calls.first;
        final callId = callData['id'] as String;
        final callerName = (callData['caller_name'] ?? 'Unknown') as String;
        // Post a system call notification so an incoming call is visible even
        // when the app isn't in the foreground (heads-up / lock screen).
        NotificationService.instance.showCallNotification(
          callerName: callerName,
          callId: callId,
        );
        _showIncomingCallDialog(
          callId: callId,
          callerName: callerName,
          callerId: callData['caller_id'] ?? '',
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
            NotificationService.instance.cancelCallNotification(callId);
            context.push('/call', extra: {
              'callId': callId,
              'currentUserId': currentUser.id,
              'currentUserName': currentUser.userMetadata?['username'] ??
                  currentUser.email?.split('@')[0] ??
                  'User',
              'friendUserId': callerId,
              'friendName': callerName,
              'isIncoming': true,
            });
          },
          onReject: () async {
            Navigator.of(dialogContext).pop();
            _isShowingIncomingCall = false;
            NotificationService.instance.cancelCallNotification(callId);
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
    _pageController.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final currentUser = authService.currentUser;

    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        children: _pages,
      ),
      bottomNavigationBar: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _unreadStream ?? const Stream.empty(),
        builder: (context, snapshot) {
          int totalUnread = 0;
          if (snapshot.hasData) {
            for (var chat in snapshot.data!) {
              totalUnread += (chat['unreadCount'] ?? 0) as int;
            }
          }

          return BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: _onTabTapped,
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
