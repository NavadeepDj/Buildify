import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pages/ai_model_select_page.dart';
import 'pages/hosted_account_page.dart';
import 'pages/projects_home_page.dart';
import 'pages/verification_page.dart';
import 'screens/ai_server_shell.dart';
import 'theme/app_palette.dart';
import 'providers/hosted_account_provider.dart';
import 'providers/management_account_provider.dart';
import 'services/hosted_auth_config.dart';
import 'services/management_api_config.dart';
import 'services/secure_auth_storage.dart';
import 'services/windows_app_storage.dart';
import 'assistant/status_probe_provider.dart';
import 'screens/assistant_setup_screen.dart';
import 'assistant/voice_tool_runtime.dart';
import 'screens/voice_actions_screen.dart';
import 'pages/host_project_wizard.dart';
import 'pages/project_detail_page.dart';
import 'pages/env_management_page.dart';

final _appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureWindowsAppStorage();
  SupabaseClient? client;
  HostedAuthConfig? authConfig;
  String? startupMessage;
  try {
    final config = HostedAuthConfig.fromDefines();
    authConfig = config;
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
  ManagementApiConfig? managementConfig;
  String? managementMessage;
  try {
    managementConfig = ManagementApiConfig.fromDefines(authConfig);
  } on FormatException {
    managementMessage =
        'Cloud profile settings are invalid in this build. Local hosting is still available.';
  }
  runApp(
    ProviderScope(
      overrides: [
        hostedClientProvider.overrideWithValue(client),
        hostedStartupMessageProvider.overrideWithValue(startupMessage),
        managementApiConfigProvider.overrideWithValue(managementConfig),
        managementStartupMessageProvider.overrideWithValue(managementMessage),
      ],
      child: const BuildifyApp(),
    ),
  );
}

class BuildifyApp extends ConsumerWidget {
  const BuildifyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voiceBridge = ref.watch(statusProbeProvider);
    final pendingVoiceRequests = ref.watch(pendingVoiceRequestsProvider);
    ref.listen(voiceSetupRequestsProvider, (previous, next) {
      if (previous == next) return;
      _appNavigatorKey.currentState?.pushNamed('/voice-setup');
    });
    ref.listen(voiceNavigationProvider, (previous, next) {
      if (next == null || previous == next) return;
      Widget page;
      switch (next.page) {
        case 'wizard':
          page = const HostProjectSourcePage();
        case 'project':
          page = ProjectDetailPage(projectId: next.projectId!);
        case 'environment':
          page = EnvManagementPage(projectId: next.projectId!);
        default:
          page = const VoiceActionsScreen();
      }
      _appNavigatorKey.currentState?.push(
        MaterialPageRoute<void>(builder: (_) => page),
      );
    });
    final base = ThemeData.dark(useMaterial3: true);
    return MaterialApp(
      navigatorKey: _appNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Buildify AI Server',
      builder:
          (context, child) => Stack(
            children: [
              child ?? const SizedBox.shrink(),
              if (voiceBridge.asData?.value != null)
                Positioned(
                  right: 16,
                  bottom: 76,
                  child: FloatingActionButton.extended(
                    heroTag: null,
                    onPressed:
                        () => _appNavigatorKey.currentState?.push(
                          MaterialPageRoute<void>(
                            builder: (_) => const VoiceActionsScreen(),
                          ),
                        ),
                    icon: Badge(
                      label: Text('$pendingVoiceRequests'),
                      child: const Icon(Icons.record_voice_over_outlined),
                    ),
                    label: const Text('Voice requests'),
                  ),
                ),
            ],
          ),
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
        if (uri.path == '/voice-setup') {
          return MaterialPageRoute<void>(
            builder: (_) => const AssistantSetupScreen(),
            settings: settings,
          );
        }
        if (uri.path == '/verify') {
          final token = uri.queryParameters['token'];
          return MaterialPageRoute<void>(
            builder: (_) => VerificationPage(initialToken: token),
            settings: settings,
          );
        }
        if (uri.path == '/ai-server' || uri.path == '/ai-assistant') {
          return MaterialPageRoute<void>(
            builder: (_) => const AiServerShell(),
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
                  onOpenAiServer:
                      () => Navigator.of(ctx).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AiServerShell(),
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
                      onOpenAiServer:
                          () => Navigator.of(ctx).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AiServerShell(),
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
