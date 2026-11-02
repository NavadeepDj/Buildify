import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pages/ai_model_select_page.dart';
import 'pages/hosted_account_page.dart';
import 'pages/projects_home_page.dart';
import 'pages/verification_page.dart';
import 'theme/app_palette.dart';
import 'providers/hosted_account_provider.dart';
import 'services/hosted_auth_config.dart';
import 'services/secure_auth_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SupabaseClient? client;
  String? startupMessage;
  try {
    final config = HostedAuthConfig.fromDefines();
    if (config != null) {
      final supabase = await Supabase.initialize(
        url: config.url,
        publishableKey: config.publishableKey,
        debug: false,
        authOptions: FlutterAuthClientOptions(
          localStorage: SecureAuthStorage(
            projectHost: Uri.parse(config.url).host,
          ),
          pkceAsyncStorage: SecurePkceStorage(
            projectHost: Uri.parse(config.url).host,
          ),
          // Initial hosted flow uses email codes; callback support is separate.
          detectSessionInUri: false,
        ),
      );
      client = supabase.client;
    }
  } on FormatException {
    startupMessage =
        'Account configuration is invalid in this build. Local hosting is still available.';
  } catch (_) {
    startupMessage =
        'Account sign-in could not start. Restart the app to retry, or continue locally.';
  }
  runApp(
    ProviderScope(
      overrides: [
        hostedClientProvider.overrideWithValue(client),
        hostedStartupMessageProvider.overrideWithValue(startupMessage),
      ],
      child: const BuildifyApp(),
    ),
  );
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
      onGenerateRoute: (settings) {
        final uri = Uri.tryParse(settings.name ?? '') ?? Uri();
        if (uri.path == '/verify') {
          final token = uri.queryParameters['token'];
          return MaterialPageRoute<void>(
            builder: (_) => VerificationPage(initialToken: token),
            settings: settings,
          );
        }
        if (uri.path == '/projects') {
          return MaterialPageRoute<void>(
            builder:
                (ctx) => ProjectsHomePage(
                  onRunAiModel:
                      () => Navigator.of(ctx).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AiModelSelectPage(),
                        ),
                      ),
                ),
            settings: settings,
          );
        }
        return MaterialPageRoute<void>(
          builder:
              (_) => HostedAccountGate(
                signedInBuilder:
                    (ctx) => ProjectsHomePage(
                      onRunAiModel:
                          () => Navigator.of(ctx).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AiModelSelectPage(),
                            ),
                          ),
                    ),
              ),
          settings: settings,
        );
      },
    );
  }
}
