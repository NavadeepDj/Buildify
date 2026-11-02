import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/hosted_account_service.dart';

final hostedClientProvider = Provider<SupabaseClient?>((ref) => null);
final hostedStartupMessageProvider = Provider<String?>((ref) => null);
final hostedAccountServiceProvider = Provider<AccountService>(
  (ref) => HostedAccountService(ref.watch(hostedClientProvider)),
);
final hostedAccountProvider = StreamProvider<HostedAccount?>(
  (ref) => ref.watch(hostedAccountServiceProvider).accountChanges,
);
