import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:runa_app/features/chat/chat_list_screen.dart';
import 'package:runa_app/features/friends/friends_screen.dart';
import 'package:runa_app/settings/settings_screen.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    ChatListScreen(),
    FriendsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Iconsax.message),
            activeIcon: Icon(Iconsax.message5),
            label: 'Chats',
          ),
          BottomNavigationBarItem(
            icon: Icon(Iconsax.people),
            activeIcon: Icon(Iconsax.people5),
            label: 'Friends',
          ),
          BottomNavigationBarItem(
            icon: Icon(Iconsax.setting),
            activeIcon: Icon(Iconsax.setting5),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
