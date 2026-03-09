import 'package:flutter/material.dart';

import 'pages/app_entry_page.dart';

void main() {
  runApp(const BnbuApp());
}

class BnbuApp extends StatelessWidget {
  const BnbuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BNBU',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF235789)),
        useMaterial3: true,
      ),
      home: const AppEntryPage(),
    );
  }
}
