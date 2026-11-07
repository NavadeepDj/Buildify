import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/management_account_service.dart';
import '../services/management_api_config.dart';
import 'hosted_account_provider.dart';

final managementApiConfigProvider = Provider<ManagementApiConfig?>(
  (ref) => null,
);
final managementStartupMessageProvider = Provider<String?>((ref) => null);
final managementAccountServiceProvider = Provider<ManagementAccountService?>((
  ref,
) {
  final config = ref.watch(managementApiConfigProvider);
  final client = ref.watch(hostedClientProvider);
  if (config == null || client == null) return null;
  return ManagementAccountService(
    config: config,
    sessions: SupabaseManagementSessionSource(client),
  );
});

final managementAccountProvider = FutureProvider.autoDispose<
  ManagementAccount?
>((ref) async {
  // Every auth event invalidates this request. Riverpod discards completions from
  // the previous identity; a signout never retains another user's cloud profile.
  final account = ref.watch(hostedAccountProvider).asData?.value;
  if (account == null) return null;
  return ref.watch(managementAccountServiceProvider)?.fetchAccount();
});
