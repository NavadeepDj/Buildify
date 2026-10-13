import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../backend/embedded_backend.dart';
import 'database_helper.dart';
import 'subdomain.dart';
import 'project_gateway.dart';

/// Public proxy and private management API use separate loopback listeners.
class LiveUrlService {
  LiveUrlService(this.backend);
  final EmbeddedBackendService backend;
  final gateway = ProjectGateway();
  BackendProject? _aiRoute;

  Future<String> registerAiRoute(String name, int port) async {
    final slug = projectNameSubdomain(name);
    if (validateSubdomain(slug) != null ||
        !await available(slug, except: 'ai-model')) {
      throw const FormatException(
        'This subdomain is reserved or already in use.',
      );
    }
    await start();
    final url = 'https://$slug.$baseDomain';
    _aiRoute = BackendProject(
      id: 'ai-model',
      name: name,
      repoProvider: 'Local',
      url: '',
      lastDeployedAt: null,
      isLive: true,
      port: port,
      subdomain: slug,
      liveUrl: url,
    );
    return url;
  }

  void unregisterAiRoute() => _aiRoute = null;
  final _errors = <String, String>{};
  String? errorFor(String id) => _errors[id];
  int get routerPort =>
      int.parse(Platform.environment['ROUTER_PORT'] ?? '8787');
  HttpServer? _router, _api;
  Future<void>? _starting;
  Future<void> _queue = Future.value();
  bool _disposed = false;
  final _attempts = <String, int>{};
  final _limits = <String, List<DateTime>>{};
  final _client =
      HttpClient()
        ..autoUncompress = false
        ..connectionTimeout = const Duration(seconds: 10);
  final _healthClient =
      HttpClient()..connectionTimeout = const Duration(seconds: 10);
  BackendProject project(String id) => backend.state.projects.firstWhere(
    (p) => p.id == id,
    orElse: () => throw const HttpException('Project not found'),
  );

  Future<void> start() =>
      _starting ??= _start().catchError((Object e) {
        _starting = null;
        throw e;
      });
  Future<void> _start() async {
    _router = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      int.parse(Platform.environment['ROUTER_PORT'] ?? '8787'),
    );
    try {
      _api = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        int.parse(Platform.environment['LIVE_URL_API_PORT'] ?? '8788'),
      );
    } catch (_) {
      await _router!.close(force: true);
      rethrow;
    }
    _router!.listen(_proxy);
    _api!.listen(_handleApi);
  }

  Future<void> assign(String id, {String? custom, bool release = false}) {
    final result = _queue.then((_) async {
      var p = project(id);
      if (release) {
        _attempts[id] = (_attempts[id] ?? 0) + 1;
        await _save(p, '', '', 'Stopped');
        return;
      }
      if (custom == null && p.subdomain.isNotEmpty) {
        if (p.isLive) unawaited(startProjectTunnel(id));
        return;
      }
      for (var n = 0; n < 20; n++) {
        final preferred = projectNameSubdomain(p.name);
        final slug =
            custom ??
            (n == 0 && validateSubdomain(preferred) == null
                ? preferred
                : projectSubdomain(p.name));
        final error = validateSubdomain(slug);
        if (error != null) throw FormatException(error);
        if (!await available(slug, except: id)) {
          if (custom != null) {
            throw const FormatException('Subdomain already in use.');
          }
          continue;
        }
        try {
          _attempts[id] = (_attempts[id] ?? 0) + 1;
          await _save(
            p,
            slug,
            'https://$slug.$baseDomain',
            p.isLive ? 'Provisioning' : 'Stopped',
          );
        } catch (e) {
          if (!e.toString().contains('UNIQUE')) rethrow;
          if (custom != null) {
            throw const FormatException('Subdomain already in use.');
          }
          continue;
        }
        if (p.isLive) unawaited(startProjectTunnel(id));
        return;
      }
      throw const HttpException('Could not allocate subdomain. Retry.');
    });
    _queue = result.catchError((Object _) {});
    return result;
  }

  Future<bool> available(String slug, {String? except}) async {
    if (validateSubdomain(slug) != null ||
        (_aiRoute?.subdomain == slug && except != 'ai-model')) {
      return false;
    }
    final rows = await DatabaseHelper.instance.getProjects();
    return !rows.any((r) => r['subdomain'] == slug && r['id'] != except) &&
        !backend.state.projects.any(
          (p) => p.subdomain == slug && p.id != except,
        );
  }

  Future<void> _save(
    BackendProject p,
    String slug,
    String url,
    String status,
  ) async {
    // The DB unique index is the authority for every identity.
    {
      await DatabaseHelper.instance.updateProject(p.id, {
        'subdomain': slug.isEmpty ? null : slug,
        'live_url': url,
        'live_url_status': status,
      });
    }
    backend.updateLiveUrl(p.id, slug, url, status);
  }

  Future<void> setStatus(String id, String status) async {
    if (_disposed) return;
    project(id);
    if (status == 'Stopped') _attempts[id] = (_attempts[id] ?? 0) + 1;
    await DatabaseHelper.instance.updateProject(id, {
      'live_url_status': status,
    });
    if (_disposed) return;
    final latest = project(id);
    backend.updateLiveUrl(id, latest.subdomain, latest.liveUrl, status);
  }

  Future<void> activate(String id) async {
    final epoch = (_attempts[id] ?? 0) + 1;
    _attempts[id] = epoch;
    try {
      var p = project(id);
      if (!p.isLive || p.liveUrl.isEmpty) {
        await setStatus(id, 'Stopped');
        return;
      }
      final url = p.liveUrl;
      await setStatus(id, 'Provisioning');
      for (var n = 0; n < 20; n++) {
        if (_attempts[id] != epoch) return;
        p = project(id);
        if (!p.isLive || p.liveUrl != url) return;
        try {
          final request = await _healthClient.getUrl(
            Uri.parse('$url/__buildify_health'),
          );
          request.followRedirects = false;
          request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
          final response = await request.close().timeout(
            const Duration(seconds: 10),
          );
          final body = await utf8.decoder
              .bind(response)
              .join()
              .timeout(const Duration(seconds: 10));
          if (_attempts[id] != epoch || !project(id).isLive) return;
          if (response.statusCode == 200 && body == id) {
            await setStatus(id, 'Live');
            return;
          }
        } catch (_) {}
        await Future<void>.delayed(const Duration(seconds: 3));
      }
      if (_attempts[id] == epoch && project(id).isLive) {
        _errors[id] =
            'The public URL did not reach this project. Check wildcard DNS and gateway ingress to port $routerPort, then retry.';
        stderr.writeln('Live URL health check failed for project $id');
        await setStatus(id, 'Failed');
      }
    } catch (e) {
      stderr.writeln('Live URL activation failed for $id: $e');
    }
  }

  Future<void> startProjectTunnel(String id) async {
    try {
      _errors.remove(id);
      if (!project(id).isLive)
        throw const HttpException('Start the project server first.');
      await start();
      await setStatus(id, 'Provisioning');
      await gateway.start(routerPort);
      if (_disposed ||
          !backend.state.projects.any((p) => p.id == id && p.isLive))
        return;
      await activate(id);
    } catch (e) {
      if (!_disposed &&
          backend.state.projects.any((p) => p.id == id && p.isLive)) {
        _errors[id] =
            e is HttpException
                ? e.message
                : 'Could not start the gateway tunnel. Check configuration and retry.';
        stderr.writeln(
          'Project gateway startup failed for $id: ${_errors[id]}',
        );
        await setStatus(id, 'Failed');
      }
    }
  }

  Map<String, Object> _json(BackendProject p) => {
    'id': p.id,
    'subdomain': p.subdomain,
    'liveUrl': p.liveUrl,
    'liveUrlStatus': p.liveUrlStatus,
  };
  Future<void> _handleApi(HttpRequest r) async {
    r.response.headers.contentType = ContentType.json;
    try {
      // Never expose management through wildcard routing. Require an explicit token.
      final token = Platform.environment['LIVE_URL_API_TOKEN'];
      if (token == null ||
          token.isEmpty ||
          r.headers.value('authorization') != 'Bearer $token') {
        r.response.statusCode = 401;
        r.response.write(jsonEncode({'error': 'Management token required'}));
        return;
      }
      final now = DateTime.now();
      final hits = _limits.putIfAbsent('management', () => []);
      hits.removeWhere((t) => now.difference(t).inSeconds >= 60);
      if (hits.length >= 60) {
        r.response.statusCode = 429;
        r.response.headers.set('Retry-After', '60');
        r.response.write(jsonEncode({'error': 'Too many requests'}));
        return;
      }
      hits.add(now);
      final parts = r.uri.pathSegments;
      if (r.method == 'GET' && r.uri.path == '/api/projects/check-subdomain') {
        final name = r.uri.queryParameters['name'] ?? '';
        r.response.write(
          jsonEncode({
            'available': await available(name),
            'error': validateSubdomain(name),
          }),
        );
        return;
      }
      if (parts.length < 3 || parts[0] != 'api' || parts[1] != 'projects') {
        throw const HttpException('Route not found');
      }
      final id = parts[2];
      project(id);
      if (parts.length == 3 && r.method == 'GET') {
        r.response.write(jsonEncode(_json(project(id))));
        return;
      }
      if (parts.length != 4 || parts[3] != 'live-url') {
        throw const HttpException('Route not found');
      }
      switch (r.method) {
        case 'POST':
          await assign(id);
        case 'DELETE':
          await assign(id, release: true);
        case 'PATCH':
          final bytes = <int>[];
          await for (final chunk in r) {
            bytes.addAll(chunk);
            if (bytes.length > 4096) {
              throw const FormatException('Request body too large');
            }
          }
          final data = jsonDecode(utf8.decode(bytes));
          if (data is! Map || data['subdomain'] is! String) {
            throw const FormatException('subdomain must be a string');
          }
          await assign(id, custom: data['subdomain'] as String);
        default:
          r.response.statusCode = 405;
          r.response.write(jsonEncode({'error': 'Method not allowed'}));
          return;
      }
      r.response.write(jsonEncode(_json(project(id))));
    } catch (e) {
      stderr.writeln('Live URL API ${r.method} ${r.uri.path}: $e');
      r.response.statusCode =
          e is FormatException
              ? 400
              : e is HttpException
              ? 404
              : 500;
      r.response.write(
        jsonEncode({
          'error':
              e is FormatException
                  ? e.message
                  : e is HttpException
                  ? e.message
                  : 'Live URL operation failed',
        }),
      );
    } finally {
      await r.response.close();
    }
  }

  Future<void> _page(HttpRequest r, int status, String message) async {
    r.response.statusCode = status;
    r.response.headers.contentType = ContentType.html;
    r.response.headers.set('Cache-Control', 'no-store');
    r.response.write(
      '<!doctype html><title>Buildiify</title><h1>$message</h1><p>Please check the project or try again later.</p>',
    );
    await r.response.close();
  }

  Future<void> _proxy(HttpRequest r) async {
    try {
      final host =
          (r.headers.value('host') ?? '').toLowerCase().split(':').first;
      final suffix = '.$baseDomain';
      final slug =
          host.endsWith(suffix)
              ? host.substring(0, host.length - suffix.length)
              : '';
      if (validateSubdomain(slug) != null) {
        await _page(r, 404, 'Project not found');
        return;
      }
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'projects',
        where: 'subdomain = ?',
        whereArgs: [slug],
        limit: 1,
      );
      final p =
          _aiRoute?.subdomain == slug
              ? _aiRoute
              : rows.isEmpty
              ? null
              : backend.state.projects
                  .where((p) => p.id == rows.first['id'] && p.subdomain == slug)
                  .firstOrNull;
      if (p == null) {
        await _page(r, 404, 'Project not found');
        return;
      }
      if (!p.isLive) {
        await _page(r, 503, 'Project is not running');
        return;
      }
      final port = p.id == 'ai-model' ? p.port : rows.first['port'] as int;
      final target = Uri.parse('http://127.0.0.1:$port${r.uri}');
      if (WebSocketTransformer.isUpgradeRequest(r)) {
        final protocols =
            r.headers
                .value('sec-websocket-protocol')
                ?.split(',')
                .map((s) => s.trim())
                .toList();
        final headers = <String, dynamic>{};
        r.headers.forEach((key, values) {
          if (!_hopHeaders(r.headers).contains(key.toLowerCase()) &&
              !key.startsWith('sec-websocket-') &&
              key != 'host') {
            headers[key] = values;
          }
        });
        headers['Host'] = host;
        final upstream = await WebSocket.connect(
          target.replace(scheme: 'ws').toString(),
          protocols: protocols,
          headers: headers,
        );
        final downstream = await WebSocketTransformer.upgrade(
          r,
          protocolSelector: (_) => upstream.protocol,
        );
        upstream.listen(
          downstream.add,
          onDone: downstream.close,
          onError: (_) => downstream.close(),
        );
        downstream.listen(
          upstream.add,
          onDone: upstream.close,
          onError: (_) => upstream.close(),
        );
        return;
      }
      final health = r.uri.path == '/__buildify_health';
      final req = await _client.openUrl(
        health ? 'GET' : r.method,
        health
            ? Uri.parse(
              'http://127.0.0.1:$port/${p.id == 'ai-model' ? 'health' : ''}',
            )
            : target,
      );
      req.followRedirects = false;
      if (!health) {
        r.headers.forEach((key, values) {
          if (!_hopHeaders(r.headers).contains(key.toLowerCase())) {
            req.headers.set(key, values);
          }
        });
        req.headers.set('host', host);
        await req.addStream(r);
      }
      final response = await req.close();
      if (health) {
        await response.drain<void>();
        r.response.statusCode = response.statusCode < 500 ? 200 : 503;
        r.response.headers.set('Cache-Control', 'no-store');
        r.response.write(
          response.statusCode < 500 ? p.id : 'Project unavailable',
        );
      } else {
        r.response.statusCode = response.statusCode;
        response.headers.forEach((key, values) {
          if (!_hopHeaders(response.headers).contains(key.toLowerCase())) {
            r.response.headers.set(key, values);
          }
        });
        await r.response.addStream(response);
      }
      await r.response.close();
    } catch (e) {
      stderr.writeln('Project proxy failed: $e');
      try {
        await _page(r, 502, 'Project is unavailable');
      } catch (_) {
        r.response.close();
      }
    }
  }

  Set<String> _hopHeaders(HttpHeaders h) => {
    'connection',
    'keep-alive',
    'proxy-authenticate',
    'proxy-authorization',
    'te',
    'trailer',
    'transfer-encoding',
    'upgrade',
    ...?h.value('connection')?.split(',').map((s) => s.trim().toLowerCase()),
  };
  void dispose() {
    _disposed = true;
    for (final id in _attempts.keys.toList()) {
      _attempts[id] = _attempts[id]! + 1;
    }
    _router?.close(force: true);
    _api?.close(force: true);
    _client.close(force: true);
    _healthClient.close(force: true);
  }
}
