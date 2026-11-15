import 'package:buildify_flutter/services/voice_call_invitation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final link = 'https://phone-test.trycloudflare.com/#invite=${'a' * 43}';
  test('reject unsafe invitations before sending credentials', () {
    for (final value in [
      link.replaceFirst('https:', 'http:'),
      link.replaceFirst('phone-test.trycloudflare.com', 'example.com'),
      link.replaceFirst('/#', '/?token=x#'),
      link.replaceFirst('https://', 'https://user@'),
      '$link-invalid',
    ]) {
      expect(() => VoiceCallInvitation.parse(value), throwsFormatException);
    }
  });
  test(
    'check target using invitation header without following redirects',
    () async {
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://phone-test.trycloudflare.com/target',
        );
        expect(request.headers['Authorization'], 'Bearer ${'a' * 43}');
        expect(request.followRedirects, isFalse);
        return http.Response('{"platform":"android"}', 200);
      });
      await VoiceCallInvitation.verify(
        VoiceCallInvitation.parse(link),
        VoiceRunTarget.phone,
        client: client,
      );
    },
  );
  test(
    'reject a laptop link in phone mode and a phone link in laptop mode',
    () async {
      for (final target in VoiceRunTarget.values) {
        final wrong = target == VoiceRunTarget.phone ? 'windows' : 'android';
        await expectLater(
          VoiceCallInvitation.verify(
            VoiceCallInvitation.parse(link),
            target,
            client: MockClient(
              (_) async => http.Response('{"platform":"$wrong"}', 200),
            ),
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'refuse expired invitation or old helper without target verification',
    () async {
      for (final status in [302, 403, 404, 502]) {
        await expectLater(
          VoiceCallInvitation.verify(
            VoiceCallInvitation.parse(link),
            VoiceRunTarget.phone,
            client: MockClient((_) async => http.Response('', status)),
          ),
          throwsFormatException,
        );
      }
    },
  );
}
