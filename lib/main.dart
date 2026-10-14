import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pages/ai_model_select_page.dart';
import 'pages/auth_page.dart';
import 'pages/projects_home_page.dart';
import 'theme/app_palette.dart';

void main() {
  runApp(const ProviderScope(child: BuildifyApp()));
}

class BuildifyApp extends ConsumerWidget {
  const BuildifyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = ThemeData.dark(useMaterial3: true);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Buildify AI Server',
      theme: base.copyWith(
        scaffoldBackgroundColor: AppPalette.bg,
        colorScheme: base.colorScheme.copyWith(
          primary: AppPalette.primary,
          secondary: AppPalette.teal,
          surface: AppPalette.surface,
          error: AppPalette.error,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: AppPalette.bg,
          indicatorColor: AppPalette.primary.withValues(alpha: 0.16),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            minimumSize: const Size.fromHeight(44),
          ),
        ),
        cardTheme: CardThemeData(
          color: AppPalette.surface,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AppPalette.border),
          ),
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (_) => const AuthPage(),
        '/projects':
            (context) => ProjectsHomePage(
              onRunAiModel:
                  () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AiModelSelectPage(),
                    ),
                  ),
            ),
      },
    );
  }
}
