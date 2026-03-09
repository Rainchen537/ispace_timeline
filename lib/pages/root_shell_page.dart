import 'package:flutter/material.dart';

import '../state/app_session_controller.dart';
import 'ispace_page.dart';
import 'placeholder_page.dart';
import 'schedule_page.dart';
import 'user_page.dart';

class RootShellPage extends StatefulWidget {
  const RootShellPage({super.key, required this.controller});

  final AppSessionController controller;

  @override
  State<RootShellPage> createState() => _RootShellPageState();
}

class _RootShellPageState extends State<RootShellPage> {
  int _index = 2;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const PlaceholderPage(
        title: 'Home',
        subtitle: '校园与课程的统一入口',
        icon: Icons.home_rounded,
        gradient: [Color(0xFF003049), Color(0xFF1D3557)],
      ),
      const PlaceholderPage(
        title: 'Life',
        subtitle: '生活服务与校园资讯',
        icon: Icons.explore_rounded,
        gradient: [Color(0xFF006D77), Color(0xFF0A9396)],
      ),
      IspacePage(
        controller: widget.controller,
        onGoToUserTab: () {
          setState(() {
            _index = 4;
          });
        },
      ),
      SchedulePage(
        controller: widget.controller,
      ),
      UserPage(controller: widget.controller),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          setState(() {
            _index = value;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'home',
          ),
          NavigationDestination(
            icon: Icon(Icons.landscape_outlined),
            selectedIcon: Icon(Icons.landscape_rounded),
            label: 'life',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school_rounded),
            label: 'ispace',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: 'schedule',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'user',
          ),
        ],
      ),
    );
  }
}
