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
import 'package:runa_app/features/auth/splash_screen.dart';
import 'package:runa_app/features/status/add_status_screen.dart';
import 'package:runa_app/core/services/auth_service.dart';

// Create a global key for the router so we can pass auth service easily if needed,
// but the best way is to pass authService as a parameter to the router factory.
// For now, we will create a function that takes AuthService to build the router,
// or we can just access it if we make it a provider. Wait, auth service is provided in main.
// So we can change appRouter to a function or keep it global but use a global instance.

// Let's refactor appRouter to a function that takes AuthService.
GoRouter createAppRouter(AuthService authService) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: authService,
    redirect: (context, state) {
      final isInitialized = authService.isInitialized;
      final isLoggedIn = authService.currentUser != null;

      final isSplash = state.matchedLocation == '/splash';
      final isGoingToLoginOrRegister = state.matchedLocation == '/login' || state.matchedLocation == '/register';

      if (!isInitialized) {
        if (!isSplash) return '/splash';
        return null;
      }

      if (!isLoggedIn && !isGoingToLoginOrRegister) {
        return '/login';
      }
      if (isLoggedIn && (isGoingToLoginOrRegister || isSplash)) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
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
}
