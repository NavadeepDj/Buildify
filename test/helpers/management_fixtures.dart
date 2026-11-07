import 'package:buildify_flutter/services/hosted_auth_config.dart';
import 'package:buildify_flutter/services/management_api_config.dart';
import 'package:buildify_flutter/services/management_account_service.dart';

const userA = '11111111-1111-4111-8111-111111111111';
const userB = '22222222-2222-4222-8222-222222222222';
const requestId = '33333333-3333-4333-8333-333333333333';
const credentials = ManagementSession(
  userId: userA,
  accessToken: 'synthetic-first',
);
final config =
    ManagementApiConfig.parse(
      'https://test-project.supabase.co/functions/v1/management',
      HostedAuthConfig.parse(
        environment: 'development',
        url: 'https://test-project.supabase.co',
        publishableKey: 'sb_publishable_fixture',
      ),
    )!;

class FakeSessions implements ManagementSessionSource {
  ManagementSession? current = credentials;
  ManagementSession? refreshed;
  final reads = <bool>[];
  @override
  Future<ManagementSession?> read({bool refresh = false}) async {
    reads.add(refresh);
    if (refresh && refreshed != null) current = refreshed;
    return current;
  }

  @override
  bool isCurrentUser(String id) => current?.userId == id;
}
