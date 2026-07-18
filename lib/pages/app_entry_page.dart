import 'package:flutter/material.dart';

import '../state/app_session_controller.dart';
import 'login_page.dart';
import 'root_shell_page.dart';

class AppEntryPage extends StatefulWidget {
  const AppEntryPage({super.key});

  @override
  State<AppEntryPage> createState() => _AppEntryPageState();
}

class _AppEntryPageState extends State<AppEntryPage>
    with WidgetsBindingObserver {
  final AppSessionController _controller = AppSessionController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.restoreSessionIfPossible();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.restoreSessionIfPossible();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_controller.isLoggedIn) {
          return RootShellPage(controller: _controller);
        }
        return LoginPage(controller: _controller);
      },
    );
  }
}
