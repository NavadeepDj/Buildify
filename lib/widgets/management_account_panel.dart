import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/management_account_provider.dart';
import '../services/management_account_service.dart';

class ManagementAccountPanel extends ConsumerWidget {
  const ManagementAccountPanel({
    super.key,
    required this.fallbackName,
    required this.onSignInAgain,
  });
  final String fallbackName;
  final VoidCallback? onSignInAgain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startup = ref.watch(managementStartupMessageProvider);
    if (ref.watch(managementApiConfigProvider) == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(fallbackName), if (startup != null) Text(startup)],
      );
    }
    return ref
        .watch(managementAccountProvider)
        .when(
          skipLoadingOnRefresh: false,
          data:
              (account) =>
                  account == null
                      ? const SizedBox.shrink()
                      : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            account.displayName,
                            key: const Key('management-display-name'),
                          ),
                          TextButton(
                            onPressed:
                                () => ref.invalidate(managementAccountProvider),
                            child: const Text('Refresh profile'),
                          ),
                        ],
                      ),
          loading:
              () => const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Loading your cloud profile…'),
                ],
              ),
          error:
              (error, _) => _ProfileFailure(
                failure:
                    error is ManagementFailure
                        ? error
                        : const ManagementFailure(
                          ManagementFailureKind.unavailable,
                        ),
                retry: () => ref.invalidate(managementAccountProvider),
                signIn: onSignInAgain,
              ),
        );
  }
}

class _ProfileFailure extends StatefulWidget {
  const _ProfileFailure({
    required this.failure,
    required this.retry,
    required this.signIn,
  });
  final ManagementFailure failure;
  final VoidCallback retry;
  final VoidCallback? signIn;
  @override
  State<_ProfileFailure> createState() => _ProfileFailureState();
}

class _ProfileFailureState extends State<_ProfileFailure> {
  Timer? _timer;
  int _remaining = 0;
  void _start() {
    _timer?.cancel();
    _remaining = widget.failure.retryAfterSeconds ?? 0;
    if (_remaining > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() => _remaining--);
        if (_remaining <= 0) timer.cancel();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant _ProfileFailure oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.failure, widget.failure)) _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(widget.failure.message, key: const Key('management-error')),
      if (widget.failure.kind == ManagementFailureKind.signInRequired)
        TextButton(onPressed: widget.signIn, child: const Text('Sign in again'))
      else
        TextButton(
          onPressed: _remaining > 0 ? null : widget.retry,
          child: Text(
            _remaining > 0 ? 'Retry in ${_remaining}s' : 'Retry profile',
          ),
        ),
    ],
  );
}
