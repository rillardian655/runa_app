import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:runa_app/features/auth/login_screen.dart';
import 'package:runa_app/features/auth/register_screen.dart';
import 'package:runa_app/features/layout/main_layout.dart';
import 'package:runa_app/features/chat/chat_screen.dart';
import 'package:runa_app/features/call/call_screen.dart';
import 'package:runa_app/features/friends/search_friends_screen.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/login',
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
      path: '/chat/:userId',
      builder: (context, state) {
        final userId = state.pathParameters['userId']!;
        return ChatScreen(userId: userId);
      },
    ),
    GoRoute(
      path: '/call/:callId',
      builder: (context, state) {
        final callId = state.pathParameters['callId']!;
        return CallScreen(callId: callId);
      },
    ),
    GoRoute(
      path: '/search_friends',
      builder: (context, state) => const SearchFriendsScreen(),
    ),
  ],
);
