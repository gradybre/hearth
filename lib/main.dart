import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app/router.dart';
import 'app/theme/hearth_theme.dart';

void main() {
  runApp(const ProviderScope(child: HearthApp()));
}

class HearthApp extends StatefulWidget {
  const HearthApp({super.key});

  @override
  State<HearthApp> createState() => _HearthAppState();
}

class _HearthAppState extends State<HearthApp> {
  late final GoRouter _router = buildRouter();

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Hearth',
    debugShowCheckedModeBanner: false,
    theme: HearthTheme.light(),
    darkTheme: HearthTheme.dark(),
    // Light ships first, but dark is defined from day one and follows the OS
    // rather than waiting on an in-app setting (spec §6.1).
    themeMode: ThemeMode.system,
    routerConfig: _router,
  );
}
