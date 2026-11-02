import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:buildify_flutter/services/github_auth_service.dart';

void main() {
  test(
    'loads all pages with authentication, including private repositories',
    () async {
      final pages = <int>[];
      final service = GithubAuthService(
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer test-token');
          expect(
            request.url.queryParameters['affiliation'],
            'owner,collaborator,organization_member',
          );
          final page = int.parse(request.url.queryParameters['page']!);
          pages.add(page);
          return http.Response(
            jsonEncode(
              page == 1
                  ? List.generate(
                    100,
                    (i) => {'full_name': 'owner/repo$i', 'private': true},
                  )
                  : [
                    {'full_name': 'owner/last', 'private': false},
                  ],
            ),
            200,
          );
        }),
      );
      addTearDown(service.close);
      final repos = await service.repositories('test-token');
      expect(repos.length, 101);
      expect(pages, [1, 2]);
      expect(repos.first['private'], true);
      expect(repos.last['full_name'], 'owner/last');
    },
  );

  test(
    'surfaces permission and rate limit failures instead of showing an empty list',
    () async {
      final service = GithubAuthService(
        client: MockClient((_) async => http.Response('{}', 403)),
      );
      addTearDown(service.close);
      await expectLater(service.repositories('token'), throwsException);
    },
  );

  test('cancelled authorization does not make a token request', () async {
    final service = GithubAuthService(
      client: MockClient((_) async {
        fail('Cancelled authorization must not contact GitHub');
      }),
    );
    addTearDown(service.close);
    expect(await service.poll({'expires_in': 900}, () => true), isNull);
  });
}
