import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class GithubAuthService {
  GithubAuthService({http.Client? client}) : client = client ?? http.Client();
  final http.Client client;
  static const clientId = String.fromEnvironment('GITHUB_CLIENT_ID');
  static const storage = FlutterSecureStorage();
  static const tokenKey = 'github_oauth_token';

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, String> body,
  ) async {
    final response = await client
        .post(
          Uri.https('github.com', path),
          headers: {'Accept': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('GitHub authorization failed (${response.statusCode}).');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> begin() async {
    if (clientId.isEmpty) {
      throw Exception(
        'Configure GITHUB_CLIENT_ID and enable device flow in your GitHub OAuth app.',
      );
    }
    final data = await _post('/login/device/code', {
      'client_id': clientId,
      'scope': 'repo',
    });
    if (data['error'] != null) {
      throw Exception('GitHub could not start authorization: ${data['error']}');
    }
    return data;
  }

  Future<String?> poll(
    Map<String, dynamic> device,
    bool Function() cancelled,
  ) async {
    var interval = (device['interval'] as int?) ?? 5;
    final deadline = DateTime.now().add(
      Duration(seconds: device['expires_in'] as int),
    );
    while (DateTime.now().isBefore(deadline) && !cancelled()) {
      await Future<void>.delayed(Duration(seconds: interval));
      if (cancelled()) return null;
      final data = await _post('/login/oauth/access_token', {
        'client_id': clientId,
        'device_code': device['device_code'] as String,
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      });
      if (cancelled()) return null;
      if (data['access_token'] is String) {
        final token = data['access_token'] as String;
        if (token.isEmpty) {
          throw Exception('GitHub returned an empty access token.');
        }
        await storage.write(key: tokenKey, value: token);
        return token;
      }
      switch (data['error']) {
        case 'authorization_pending':
          continue;
        case 'slow_down':
          interval += 5;
          continue;
        case 'access_denied':
          throw Exception('GitHub authorization was declined.');
        case 'expired_token':
        case 'token_expired':
          throw Exception('The code expired. Please try again.');
        default:
          throw Exception('GitHub authorization failed: ${data['error']}');
      }
    }
    if (cancelled()) return null;
    throw Exception('The code expired. Please try again.');
  }

  Future<List<Map<String, dynamic>>> repositories(String token) async {
    final repos = <Map<String, dynamic>>[];
    for (var page = 1; ; page++) {
      final response = await client
          .get(
            Uri.https('api.github.com', '/user/repos', {
              'per_page': '100',
              'page': '$page',
              'sort': 'updated',
              'affiliation': 'owner,collaborator,organization_member',
            }),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/vnd.github+json',
            },
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 401) {
        await storage.delete(key: tokenKey);
        throw Exception('GitHub session expired. Connect again.');
      }
      if (response.statusCode != 200) {
        throw Exception(
          'Cannot load repositories (${response.statusCode}). Check GitHub permissions or try again later.',
        );
      }
      final batch =
          (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
      repos.addAll(batch);
      if (batch.length < 100) return repos;
    }
  }

  void close() => client.close();
}
