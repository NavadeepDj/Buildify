import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/hosted_account_provider.dart';
import '../providers/management_account_provider.dart';
import '../services/hosted_account_service.dart';
import '../widgets/management_account_panel.dart';

/// Cloud account UI. Legacy SQLite accounts remain separate during migration.
class HostedAccountPage extends ConsumerStatefulWidget {
  const HostedAccountPage({super.key});

  @override
  ConsumerState<HostedAccountPage> createState() => _HostedAccountPageState();
}

class _HostedAccountPageState extends ConsumerState<HostedAccountPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _signup = false;
  bool _verify = false;
  bool _busy = false;
  bool _hidePassword = true;
  String? _message;
  bool _isError = false;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    _cooldown = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _cooldown <= 1) {
        timer.cancel();
        if (mounted) setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  Future<void> _perform(Future<void> Function(AccountService) action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action(ref.read(hostedAccountServiceProvider));
    } on AccountFailure catch (error) {
      if (mounted) {
        setState(() {
          _message = error.message;
          _isError = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'Unable to complete this request. Please try again.';
          _isError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _complete() {
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    }
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    await _perform((service) async {
      if (_verify) {
        await service.verifyEmail(email: _email.text, code: _code.text);
        _complete();
        return;
      }
      final result =
          _signup
              ? await service.signUp(
                name: _name.text,
                email: _email.text,
                password: _password.text,
              )
              : await service.signIn(
                email: _email.text,
                password: _password.text,
              );
      if (!mounted) return;
      _password.clear();
      if (result.needsVerification) {
        setState(() {
          _verify = true;
          _message =
              _signup
                  ? 'Check your inbox for a confirmation email. If this account already exists, return to sign in.'
                  : 'Confirm your email before signing in. Use your existing email or request a new code.';
          _isError = false;
          if (_signup) _startCooldown();
        });
      } else {
        _complete();
      }
    });
  }

  Future<void> _resend() => _perform((service) async {
    await service.resendVerification(_email.text);
    if (mounted) {
      setState(() {
        _message =
            'A new verification email was requested. Check your inbox and spam folder.';
        _isError = false;
        _startCooldown();
      });
    }
  });

  void _resetForm() {
    setState(() {
      _verify = false;
      _signup = false;
      _message = null;
      _code.clear();
      _password.clear();
    });
    _form.currentState?.reset();
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(hostedAccountServiceProvider);
    final account = ref.watch(hostedAccountProvider).valueOrNull;
    final startupMessage = ref.watch(hostedStartupMessageProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Buildify account')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    account != null
                        ? 'Your account'
                        : _verify
                        ? 'Verify your email'
                        : _signup
                        ? 'Create your account'
                        : 'Welcome back',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  if (account != null) ...[
                    ManagementAccountPanel(
                      fallbackName: account.name,
                      onSignInAgain:
                          _busy
                              ? null
                              : () => _perform((service) async {
                                await service.signOut();
                                _complete();
                              }),
                    ),
                    Text(account.email),
                    const SizedBox(height: 16),
                    const Text(
                      'Signing out ends this account session. It does not delete or stop local projects.',
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed:
                          _busy
                              ? null
                              : () => _perform((service) async {
                                await service.signOut();
                                _complete();
                              }),
                      child: const Text('Sign out'),
                    ),
                  ] else ...[
                    if (!service.isConfigured) ...[
                      Text(
                        startupMessage ??
                            'Account sign-in is not configured in this build. Local hosting is still available.',
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_verify) ...[
                      Text(
                        'Enter the code from the confirmation email for ${_email.text.trim()}. You can also confirm using the email link, then return to sign in.',
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('account-code'),
                        controller: _code,
                        enabled: !_busy,
                        decoration: const InputDecoration(
                          labelText: 'Email verification code',
                        ),
                        keyboardType: TextInputType.number,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        validator:
                            (value) =>
                                RegExp(
                                      r'^\d{6,10}$',
                                    ).hasMatch(value?.trim() ?? '')
                                    ? null
                                    : 'Enter the code from your email.',
                      ),
                    ] else ...[
                      const Text(
                        'Sign in to your shared Buildify account. Previous device-local accounts require a new cloud signup.',
                      ),
                      const SizedBox(height: 16),
                      if (_signup) ...[
                        TextFormField(
                          key: const Key('account-name'),
                          controller: _name,
                          enabled: !_busy,
                          decoration: const InputDecoration(
                            labelText: 'Display name',
                          ),
                          validator:
                              (value) =>
                                  value == null || value.trim().isEmpty
                                      ? 'Enter your name.'
                                      : null,
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        key: const Key('account-email'),
                        controller: _email,
                        enabled: !_busy,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Email address',
                        ),
                        validator:
                            (value) =>
                                RegExp(
                                      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                    ).hasMatch(value?.trim() ?? '')
                                    ? null
                                    : 'Enter a valid email address.',
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('account-password'),
                        controller: _password,
                        enabled: !_busy,
                        obscureText: _hidePassword,
                        autofillHints: [
                          _signup
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        decoration: InputDecoration(
                          labelText: 'Password',
                          suffixIcon: IconButton(
                            tooltip:
                                _hidePassword
                                    ? 'Show password'
                                    : 'Hide password',
                            onPressed:
                                () => setState(
                                  () => _hidePassword = !_hidePassword,
                                ),
                            icon: Icon(
                              _hidePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                          ),
                        ),
                        validator:
                            (value) =>
                                value == null || value.isEmpty
                                    ? 'Enter your password.'
                                    : _signup && value.length < 8
                                    ? 'Use at least 8 characters.'
                                    : null,
                        onFieldSubmitted: (_) {
                          if (!_busy && service.isConfigured) _submit();
                        },
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed:
                          _busy || !service.isConfigured ? null : _submit,
                      child: Text(
                        _busy
                            ? 'Please wait…'
                            : _verify
                            ? 'Verify email'
                            : _signup
                            ? 'Create account'
                            : 'Sign in',
                      ),
                    ),
                    if (_verify) ...[
                      TextButton(
                        onPressed: _busy || _cooldown > 0 ? null : _resend,
                        child: Text(
                          _cooldown > 0
                              ? 'Resend in ${_cooldown}s'
                              : 'Resend verification email',
                        ),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _resetForm,
                        child: const Text('Back to sign in'),
                      ),
                    ] else
                      TextButton(
                        onPressed:
                            _busy
                                ? null
                                : () {
                                  setState(() {
                                    _signup = !_signup;
                                    _message = null;
                                    _password.clear();
                                  });
                                  _form.currentState?.reset();
                                },
                        child: Text(
                          _signup
                              ? 'Already have an account? Sign in'
                              : 'New to Buildify? Create an account',
                        ),
                      ),
                  ],
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _message!,
                          style: TextStyle(
                            color:
                                _isError
                                    ? Theme.of(context).colorScheme.error
                                    : null,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed:
                        _busy
                            ? null
                            : () =>
                                Navigator.of(context).pushNamed('/projects'),
                    child: const Text('Continue with local hosting'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HostedAccountGate extends ConsumerWidget {
  const HostedAccountGate({super.key, required this.signedInBuilder});
  final WidgetBuilder signedInBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Start the cloud read after sign-in without blocking the local dashboard.
    ref.watch(managementAccountProvider);
    return ref
        .watch(hostedAccountProvider)
        .when(
          data:
              (account) =>
                  account == null
                      ? const HostedAccountPage()
                      : signedInBuilder(context),
          loading:
              () => const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              ),
          error: (_, _) => const HostedAccountPage(),
        );
  }
}
