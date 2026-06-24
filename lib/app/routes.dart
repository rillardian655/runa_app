import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:runa_app/features/auth/login_screen.dart';
import 'package:runa_app/features/auth/register_screen.dart';
import 'package:runa_app/features/layout/main_layout.dart';
import 'package:runa_app/features/chat/chat_screen.dart';
import 'package:runa_app/features/chat/group_chat_screen.dart';
import 'package:runa_app/features/chat/create_group_screen.dart';
import 'package:runa_app/features/friends/user_profile_screen.dart';
import 'package:runa_app/settings/settings_screen.dart';
import 'package:runa_app/settings/edit_profile_screen.dart';
import 'package:runa_app/features/call/call_screen.dart';
import 'package:runa_app/features/friends/search_friends_screen.dart';
import 'package:runa_app/features/status/add_status_screen.dart';

final GoRouter appRouter = GoRouter(
  initialLocation:
      FirebaseAuth.instance.currentUser == null ? '/login' : '/',
  redirect: (context, state) {
    final isLoggedIn =
        FirebaseAuth.instance.currentUser != null;
    final isGoingToLoginOrRegister = state.matchedLocation == '/login' ||
        state.matchedLocation == '/register';

    if (!isLoggedIn && !isGoingToLoginOrRegister) {
      return '/login';
    }
    if (isLoggedIn && isGoingToLoginOrRegister) {
      return '/';
    }
    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/',
      builder: (context, state) => const MainLayout(),
    ),
    GoRoute(
      path: '/edit_profile',
      builder: (context, state) => const EditProfileScreen(),
    ),
    GoRoute(
      path: '/profile/:userId',
      builder: (context, state) {
        final userId = state.pathParameters['userId']!;
        return UserProfileScreen(userId: userId);
      },
    ),
    GoRoute(
      path: '/chat/:userId',
      builder: (context, state) {
        final userId = state.pathParameters['userId']!;
        return ChatScreen(userId: userId);
      },
    ),
    GoRoute(
      path: '/call',
      builder: (context, state) {
        final params = state.extra as Map<String, dynamic>;
        return CallScreen(
          callId: params['callId'] ?? '',
          currentUserId: params['currentUserId'] ?? '',
          currentUserName: params['currentUserName'] ?? '',
          friendUserId: params['friendUserId'] ?? '',
          friendName: params['friendName'] ?? 'Unknown',
          isIncoming: params['isIncoming'] ?? false,
        );
      },
    ),
    GoRoute(
      path: '/search_friends',
      builder: (context, state) => const SearchFriendsScreen(),
    ),
    GoRoute(
      path: '/status/add',
      builder: (context, state) => const AddStatusScreen(),
    ),
    GoRoute(
      path: '/group/:groupId',
      builder: (context, state) {
        final groupId = state.pathParameters['groupId']!;
        return GroupChatScreen(groupId: groupId);
      },
    ),
    GoRoute(
      path: '/create_group',
      builder: (context, state) => const CreateGroupScreen(),
    ),
  ],
);
