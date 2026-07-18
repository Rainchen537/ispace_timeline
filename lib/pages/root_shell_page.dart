import 'package:flutter/material.dart';

import '../state/app_session_controller.dart';
import 'ispace_page.dart';
import 'mail_page.dart';
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
  late final List<Widget?> _pages;

  @override
  void initState() {
    super.initState();
    _pages = List<Widget?>.filled(5, null);
    _loadPage(_index);
  }

  void _loadPage(int index) {
    if (_pages[index] != null) {
      return;
    }
    _pages[index] = switch (index) {
      0 => const PlaceholderPage(
        title: 'Home',
        subtitle: '校园与课程的统一入口',
        icon: Icons.home_rounded,
        gradient: [Color(0xFF003049), Color(0xFF1D3557)],
      ),
      1 => MailPage(controller: widget.controller),
      2 => IspacePage(
        controller: widget.controller,
        onGoToUserTab: () => _selectTab(4),
      ),
      3 => SchedulePage(controller: widget.controller),
      4 => UserPage(controller: widget.controller),
      _ => const SizedBox.shrink(),
    };
  }

  void _selectTab(int index) {
    setState(() {
      _loadPage(index);
      _index = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: _pages
            .map((page) => page ?? const SizedBox.shrink())
            .toList(growable: false),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'home',
          ),
          NavigationDestination(
            icon: Icon(Icons.mail_outline_rounded),
            selectedIcon: Icon(Icons.mail_rounded),
            label: 'mail',
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
