import 'dart:convert';

import 'package:http/http.dart' as http;

enum VoiceRunTarget { phone, laptop }

/// Check the helper's paired target before opening a call in another app.
class VoiceCallInvitation {
  static Uri parse(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        !RegExp(r'^[a-z0-9-]+\.trycloudflare\.com$').hasMatch(uri.host) ||
        uri.path != '/' ||
        uri.hasQuery ||
        !RegExp(r'^invite=[A-Za-z0-9_-]{43}$').hasMatch(uri.fragment)) {
      throw const FormatException(
        'Paste the complete private HTTPS call link.',
      );
    }
    return uri;
  }

  static Future<void> verify(
    Uri uri,
    VoiceRunTarget target, {
    http.Client? client,
  }) async {
    final connection = client ?? http.Client();
    try {
      final request = http.Request(
        'GET',
        uri.replace(path: '/target').removeFragment(),
      )..followRedirects = false;
      request.headers['Authorization'] =
          'Bearer ${uri.fragment.substring('invite='.length)}';
      final response = await http.Response.fromStream(
        await connection.send(request).timeout(const Duration(seconds: 10)),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw const FormatException(
          'Could not verify this call link. Run voice setup again for the selected device.',
        );
      }
      final data = jsonDecode(response.body);
      final expected = target == VoiceRunTarget.phone ? 'android' : 'windows';
      if (data is! Map || data['platform'] != expected) {
        throw FormatException(
          'This call link does not control your ${target == VoiceRunTarget.phone ? 'phone' : 'laptop'}. Paste the link for the selected device.',
        );
      }
    } finally {
      if (client == null) connection.close();
    }
  }
}
