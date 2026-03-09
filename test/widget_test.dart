import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ispace_timeline/pages/login_page.dart';
import 'package:ispace_timeline/pages/root_shell_page.dart';
import 'package:ispace_timeline/state/app_session_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  testWidgets('Login page renders account form', (WidgetTester tester) async {
    final controller = AppSessionController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: LoginPage(controller: controller)),
    );

    expect(find.text('User Id'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('Bottom navigation renders 5 tabs', (WidgetTester tester) async {
    final controller = AppSessionController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: RootShellPage(controller: controller)),
    );

    expect(find.text('home'), findsOneWidget);
    expect(find.text('life'), findsOneWidget);
    expect(find.text('ispace'), findsOneWidget);
    expect(find.text('schedule'), findsOneWidget);
    expect(find.text('user'), findsOneWidget);
  });
}
