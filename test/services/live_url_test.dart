import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:buildify_flutter/backend/embedded_backend.dart';
import 'package:buildify_flutter/services/database_helper.dart';
import 'package:buildify_flutter/services/subdomain.dart';

void main() {
  test('DNS labels reject nested, reserved, uppercase and oversized names', () {
    for (final invalid in ['www', 'api', 'a.b', '-abc', 'abc-', 'ABC', '', 'a' * 64]) {
      expect(validateSubdomain(invalid), isNotNull, reason: invalid);
    }
    expect(validateSubdomain('a'), isNull);
    expect(validateSubdomain('a' * 63), isNull);
    for (var i = 0; i < 100; i++) {
      final slug = projectSubdomain('  My Project! ${'Long name ' * 20}');
      expect(validateSubdomain(slug), isNull);
      expect(slug, startsWith('my-project-'));
    }
  });

  test('assignment persists, collisions are rejected, release stops routing', () async {
    final directory = await Directory.systemTemp.createTemp('buildify-live-test-');
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(directory.path);
    final legacy = await openDatabase('${directory.path}/buildify.db', version: 2,
      onCreate: (db, version) async {
        await db.execute('''CREATE TABLE projects (
          id TEXT PRIMARY KEY, name TEXT, type TEXT, hosting_mode TEXT,
          source_uri TEXT, local_path TEXT, port INTEGER, subdomain TEXT,
          env_vars TEXT, branch TEXT, build_command TEXT, publish_dir TEXT,
          base_dir TEXT, desired_state TEXT, created_at INTEGER, last_active_at INTEGER)''');
        await db.insert('projects', {'id': 'legacy-one', 'subdomain': 'duplicate-placeholder'});
        await db.insert('projects', {'id': 'legacy-two', 'subdomain': 'duplicate-placeholder'});
      });
    await legacy.close();
    final migrated = await DatabaseHelper.instance.database;
    expect((await migrated.query('projects')).every((r) => r['subdomain'] == null && r['live_url_status'] == 'Stopped'), true);
    await migrated.delete('projects');
    final portProbe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final testPort = portProbe.port;
    await portProbe.close();
    final backend = EmbeddedBackendService(autoHydrate: false, projectPortStart: testPort);
    final client = HttpClient();
    try {
      final first = await backend.createProject(name: 'My Site', sourceType: 'Static', customLocalPath: directory.path);
      final second = await backend.createProject(name: 'My Site', sourceType: 'Static', customLocalPath: directory.path);
      expect(first.subdomain, isNot(second.subdomain));
      expect(first.liveUrl, 'https://${first.subdomain}.$baseDomain');
      await backend.liveUrls.assign(first.id);
      expect(backend.state.projects.first.subdomain, first.subdomain);
      expect((await DatabaseHelper.instance.getProject(first.id))!['live_url'], first.liveUrl);
      await expectLater(backend.liveUrls.assign(second.id, custom: first.subdomain), throwsFormatException);
      await backend.liveUrls.assign(first.id, custom: 'custom-project');
      expect((await DatabaseHelper.instance.getProject(first.id))!['subdomain'], 'custom-project');
      final db = await DatabaseHelper.instance.database;
      await expectLater(db.update('projects', {'subdomain': 'custom-project'}, where: 'id = ?', whereArgs: [second.id]), throwsA(isA<DatabaseException>()));
      await backend.liveUrls.start();
      Future<int> status(String host) async {
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:8787/'));
        req.headers.set('host', host);
        final response = await req.close();
        await response.drain<void>();
        return response.statusCode;
      }
      expect(await status('custom-project.$baseDomain'), 503);
      expect(await status('unknown.$baseDomain'), 404);
      expect(await status('nested.custom-project.$baseDomain'), 404);
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:8788/api/projects/${first.id}'));
      final response = await request.close();
      expect(response.statusCode, 401);
      expect(jsonDecode(await utf8.decoder.bind(response).join()), contains('error'));
      final token = Platform.environment['LIVE_URL_API_TOKEN'];
      if (token != null && token.isNotEmpty) {
        Future<(int, dynamic)> api(String method, String path, [Object? body]) async {
          final req = await client.openUrl(method, Uri.parse('http://127.0.0.1:8788$path'));
          req.headers.set('authorization', 'Bearer $token');
          if (body != null) { req.headers.contentType = ContentType.json; req.write(jsonEncode(body)); }
          final res = await req.close();
          return (res.statusCode, jsonDecode(await utf8.decoder.bind(res).join()));
        }
        final path = '/api/projects/${first.id}/live-url';
        expect((await api('GET', '/api/projects/${first.id}')).$2['subdomain'], 'custom-project');
        expect((await api('PATCH', path, {'subdomain': 'www'})).$1, 400);
        expect((await api('PATCH', path, {'subdomain': 'api-edited-project'})).$1, 200);
        expect((await api('POST', path)).$2['subdomain'], 'api-edited-project');
        expect((await api('GET', '/api/projects/check-subdomain?name=api-edited-project')).$2['available'], false);
        expect((await api('DELETE', path)).$1, 200);
        expect((await api('POST', path)).$2['liveUrl'], isNotEmpty);
        await backend.liveUrls.assign(first.id, custom: 'custom-project');
      }
      await File('${directory.path}/index.html').writeAsString('running-project-response');
      final session = await backend.startSession(projectId: first.id);
      // Cancel external activation polling; this test exercises the local data plane.
      await backend.liveUrls.setStatus(first.id, 'Stopped');
      final proxiedRequest = await client.getUrl(Uri.parse('http://127.0.0.1:8787/'));
      proxiedRequest.headers.set('host', 'custom-project.$baseDomain');
      final proxiedResponse = await proxiedRequest.close();
      expect(proxiedResponse.statusCode, 200);
      expect(await utf8.decoder.bind(proxiedResponse).join(), 'running-project-response');
      final websocketOrigin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      websocketOrigin.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request,
          protocolSelector: (protocols) => protocols.contains('echo') ? 'echo' : null);
        socket.listen(socket.add);
      });
      try {
        await db.update('projects', {'port': websocketOrigin.port}, where: 'id = ?', whereArgs: [first.id]);
        final socket = await WebSocket.connect('ws://127.0.0.1:8787/echo',
          headers: {'Host': 'custom-project.$baseDomain'}, protocols: ['echo']);
        expect(socket.protocol, 'echo');
        socket.add('websocket-through-router');
        expect(await socket.first.timeout(const Duration(seconds: 5)), 'websocket-through-router');
        await socket.close();
      } finally {
        await websocketOrigin.close(force: true);
        await db.update('projects', {'port': first.port}, where: 'id = ?', whereArgs: [first.id]);
      }
      await backend.stopSession(sessionId: session.id);
      expect(await status('custom-project.$baseDomain'), 503);
      await backend.liveUrls.assign(first.id, release: true);
      expect(await status('custom-project.$baseDomain'), 404);
      expect(await backend.liveUrls.available('custom-project'), isTrue);
      final aiOrigin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      aiOrigin.listen((request) async {
        request.response.write(request.uri.path == '/health'
            ? 'healthy' : request.headers.value('authorization') ?? 'missing-key');
        await request.response.close();
      });
      try {
        final aiUrl = await backend.liveUrls.registerAiRoute('My AI Server', aiOrigin.port);
        expect(aiUrl, 'https://my-ai-server.$baseDomain');
        expect(await backend.liveUrls.registerAiRoute('My AI Server', aiOrigin.port), aiUrl);
        expect(await backend.liveUrls.available('my-ai-server'), false);
        final healthRequest = await client.getUrl(Uri.parse('http://127.0.0.1:8787/__buildify_health'));
        healthRequest.headers.set('host', 'my-ai-server.$baseDomain');
        final healthResponse = await healthRequest.close();
        expect(healthResponse.statusCode, 200);
        expect(await utf8.decoder.bind(healthResponse).join(), 'ai-model');
        final inferenceRequest = await client.postUrl(Uri.parse('http://127.0.0.1:8787/v1/chat/completions'));
        inferenceRequest.headers.set('host', 'my-ai-server.$baseDomain');
        inferenceRequest.headers.set('authorization', 'Bearer test-ai-key');
        final inferenceResponse = await inferenceRequest.close();
        expect(await utf8.decoder.bind(inferenceResponse).join(), 'Bearer test-ai-key');
        backend.liveUrls.unregisterAiRoute();
        expect(await status('my-ai-server.$baseDomain'), 404);
        expect(await backend.liveUrls.available('my-ai-server'), true);
      } finally {
        await aiOrigin.close(force: true);
      }
      if (token != null && token.isNotEmpty) {
        int statusCode = 200;
        for (var n = 0; n < 65; n++) {
          final req = await client.getUrl(Uri.parse('http://127.0.0.1:8788/api/projects/${first.id}'));
          req.headers.set('authorization', 'Bearer $token');
          final res = await req.close();
          statusCode = res.statusCode;
          await res.drain<void>();
          if (statusCode == 429) break;
        }
        expect(statusCode, 429);
      }
    } finally {
      client.close(force: true);
      backend.dispose();
      await (await DatabaseHelper.instance.database).delete('projects');
      await (await DatabaseHelper.instance.database).close();
      await directory.delete(recursive: true);
    }
  });
}
