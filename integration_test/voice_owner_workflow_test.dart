import 'dart:convert';
import 'dart:io';
import 'package:buildify_flutter/main.dart' as app;
import 'package:buildify_flutter/assistant/setup_controller.dart';
import 'package:buildify_flutter/assistant/model_operations.dart';
import 'package:buildify_flutter/assistant/voice_tool_runtime.dart';
import 'package:buildify_flutter/backend/embedded_backend.dart';
import 'package:buildify_flutter/providers/ai_server_provider.dart';
import 'package:buildify_flutter/models/ai_server_models.dart';
import 'package:buildify_flutter/screens/assistant_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real voice plan, owner approval, inference and disposable static project',
    (tester) async {
      await tester.runAsync(app.main);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(app.BuildifyApp)),
      );
      final token = Platform.environment['BUILDIFY_STATUS_TOKEN'];
      expect(token, isNotNull);
      final client = HttpClient();
      Future<Map<String, dynamic>> tool(
        String name, [
        Map<String, Object?> args = const {},
      ]) async {
        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:18791/v1/tools/$name'),
        );
        request.headers.set('Authorization', 'Bearer $token');
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(args));
        final response = await request.close();
        expect(response.statusCode, 200);
        return jsonDecode(await utf8.decoder.bind(response).join())
            as Map<String, dynamic>;
      }

      Future<void> waitFor(
        bool Function() predicate, {
        int seconds = 90,
      }) async {
        final deadline = DateTime.now().add(Duration(seconds: seconds));
        while (!predicate() && DateTime.now().isBefore(deadline)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 250)),
          );
          await tester.pump();
        }
        expect(predicate(), true);
      }

      try {
        final response = await tester.runAsync(
          () => tool('request_specific_model_setup', {
            'model_id': 'tinyllama-q4',
          }),
        );
        expect(response!['state'], 'preparing_plan');
        await waitFor(
          () =>
              !container.read(assistantSetupProvider).busy &&
              container.read(assistantSetupProvider).plan != null,
        );
        expect(container.read(aiServerProvider).status, ServerStatus.stopped);
        final pending = await tester.runAsync(() => tool('get_setup_status'));
        expect(pending!['state'], 'needs_approval');
        for (var frame = 0; frame < 6; frame++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(find.byType(AssistantSetupScreen), findsOneWidget);
        final approve = find.text('Approve and run');
        await tester.scrollUntilVisible(
          approve,
          250,
          scrollable:
              find
                  .descendant(
                    of: find.byType(AssistantSetupScreen),
                    matching: find.byType(Scrollable),
                  )
                  .first,
        );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.drag(find.descendant(of: find.byType(AssistantSetupScreen), matching: find.byType(ListView)).first, const Offset(0, -650));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.ensureVisible(approve);
      await tester.pump(const Duration(milliseconds: 400));
      expect(approve.hitTestable(), findsOneWidget);
        await tester.tap(approve);
        await tester.pump();
        await waitFor(
          () =>
              container.read(assistantSetupProvider).record?.state ==
              ModelOperationState.succeeded,
        );
        final verified = await tester.runAsync(() => tool('get_setup_status'));
        expect(verified!['health_verified'], true);
        await tester.runAsync(() async {
          final report = File('build/status-probe/setup-live-test.json');
          await report.parent.create(recursive: true);
          await report.writeAsString(
            jsonEncode({
              'tested_at': DateTime.now().toUtc().toIso8601String(),
              'model_setup': verified,
            }),
          );
          await container.read(aiServerProvider.notifier).stopServer();
        });
        expect(container.read(aiServerProvider).status, ServerStatus.stopped);

        // Only this generated disposable fixture is created/deleted. No user
        // project files, saved scripts or repositories are executed by this test.
        await tester.runAsync(() async {
          final root = await Directory(
            'build/voice-static-fixture',
          ).absolute.create(recursive: true);
          await File(
            '${root.path}/index.html',
          ).writeAsString('<html><body>Buildify voice fixture</body></html>');
          final backend = container.read(embeddedBackendProvider);
          await backend.ready;
          final project = await backend.createProject(
            name: 'Voice disposable smoke fixture',
            sourceType: 'Static',
            hostingMode: HostingMode.ephemeral,
            customLocalPath: root.path,
          );
          try {
            final runtime = container.read(voiceToolRuntimeProvider);
            final start = await runtime.execute('start_project', {
              'project_id': project.id,
            });
            expect(start['health_verified'], true);
            final status = await runtime.invoke('get_project', {
              'project_id': project.id,
            });
            expect(status['app_reports_live'], true);
            await runtime.execute('stop_project', {'project_id': project.id});
            expect(backend.state.activeSession?.projectId, isNot(project.id));
          } finally {
            if (backend.state.projects.any((p) => p.id == project.id))
              await backend.deleteProject(project.id);
          }
        });
        expect(tester.takeException(), null);
      } finally {
        client.close(force: true);
        await tester.runAsync(
          () => container.read(aiServerProvider.notifier).stopServer(),
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
