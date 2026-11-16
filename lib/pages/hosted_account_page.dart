import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/hosted_account_provider.dart';
import '../providers/management_account_provider.dart';
import '../services/hosted_account_service.dart';
import '../widgets/buildify_logo.dart';
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
  final _confirmPassword = TextEditingController();
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _signup = false;
  bool _verify = false;
  bool _busy = false;
  bool _hidePassword = true;
  bool _hideConfirmation = true;
  String? _message;
  bool _isError = false;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
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
      _confirmPassword.clear();
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
      _resetPasswords();
    });
    _form.currentState?.reset();
  }

  void _toggleSignup() {
    setState(() {
      _signup = !_signup;
      _message = null;
      _resetPasswords();
    });
    _form.currentState?.reset();
  }

  void _resetPasswords() {
    _password.clear();
    _confirmPassword.clear();
    _hidePassword = true;
    _hideConfirmation = true;
  }

  String? _validateEmail(String? value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value?.trim() ?? '')
          ? null
          : 'Enter a valid email address.';

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Enter your password.';
    return _signup && value.length < 8 ? 'Use at least 8 characters.' : null;
  }

  Widget _buildAuthForm(bool configured, String? startupMessage) {
    final creatingAccount = _signup && !_verify;
    const muted = Color(0xFFC4C7C8);
    const caption = TextStyle(
      fontFamily: 'Space Mono',
      color: muted,
      fontSize: 10,
      height: 1.4,
    );
    const label = TextStyle(
      fontFamily: 'Space Mono',
      color: muted,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1,
    );
    final micro = label.copyWith(fontSize: 8, letterSpacing: 0.8);
    final radius = BorderRadius.circular(creatingAccount ? 4 : 8);
    const fieldText = TextStyle(
      fontFamily: 'Space Mono',
      color: Color(0xFFE5E2E0),
      fontSize: 14,
      height: 20 / 14,
    );

    InputDecoration field(String hint, {Widget? prefix, Widget? suffix}) {
      return InputDecoration(
        hintText: hint,
        hintStyle: fieldText.copyWith(color: const Color(0xFF747676)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        filled: true,
        fillColor: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return creatingAccount
                ? const Color(0xFF2A2A29)
                : const Color(0xFF1C1C1A);
          }
          return creatingAccount
              ? const Color(0xFF20201E)
              : const Color(0xFF0E0E0D);
        }),
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide.none,
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
        ),
        prefixIcon: prefix,
        prefixIconConstraints: const BoxConstraints(minWidth: 36),
        suffixIcon: suffix,
        suffixIconConstraints: const BoxConstraints(minHeight: 44),
      );
    }

    Widget labeledField(
      String title,
      String annotation,
      Widget input, {
      TextStyle? annotationStyle,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: label)),
              const SizedBox(width: 8),
              Text(annotation, style: annotationStyle ?? caption),
            ],
          ),
          const SizedBox(height: 6),
          Semantics(label: title, child: input),
        ],
      );
    }

    Widget passwordVisibility(
      bool hidden,
      String fieldName,
      VoidCallback toggle,
    ) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Center(
          widthFactor: 1,
          child: TextButton(
            onPressed: _busy ? null : toggle,
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFF2A2A29),
              minimumSize: const Size(0, 24),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: Text(
              hidden ? '[ SHOW ]' : '[ HIDE ]',
              semanticsLabel: hidden ? 'Show $fieldName' : 'Hide $fieldName',
              style: micro,
            ),
          ),
        ),
      );
    }

    final credentials = Form(
      key: _form,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: creatingAccount ? 64 : 56,
                    height: creatingAccount ? 64 : 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color:
                          creatingAccount
                              ? const Color(0xFF20201E)
                              : const Color(0xFF2A2A29),
                      borderRadius: BorderRadius.circular(
                        creatingAccount ? 12 : 8,
                      ),
                    ),
                    child: BuildifyLogo(size: creatingAccount ? 48 : 40),
                  ),
                  Positioned(
                    top: creatingAccount ? 4 : -4,
                    right: creatingAccount ? 4 : -4,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox.square(
                        dimension: creatingAccount ? 8 : 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _verify
                  ? 'Verify your email'
                  : creatingAccount
                  ? 'init_account // register'
                  : 'welcome back, engineer.',
              textAlign: TextAlign.center,
              style: label.copyWith(
                color: Colors.white,
                fontSize: 18,
                height: 24 / 18,
                letterSpacing: -0.45,
              ),
            ),
            SizedBox(height: creatingAccount ? 24 : 48),
            const Divider(color: Color(0xFF353533), height: 1),
            const SizedBox(height: 24),
            if (!configured) ...[
              Text(
                startupMessage ??
                    'Account sign-in is not configured in this build. Local hosting is still available.',
                style: caption,
              ),
              const SizedBox(height: 16),
            ],
            if (_verify) ...[
              Text(
                'Enter the code from the confirmation email for ${_email.text.trim()}. You can also confirm using the email link, then return to sign in.',
                style: caption,
              ),
              const SizedBox(height: 16),
              labeledField(
                'EMAIL VERIFICATION CODE',
                '6–10 digits',
                TextFormField(
                  key: const Key('account-code'),
                  controller: _code,
                  enabled: !_busy,
                  style: fieldText,
                  decoration: field(
                    'Enter your code',
                    prefix: const Icon(
                      Icons.mail_outline,
                      size: 16,
                      color: muted,
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  validator:
                      (value) =>
                          RegExp(r'^\d{6,10}$').hasMatch(value?.trim() ?? '')
                              ? null
                              : 'Enter the code from your email.',
                  onFieldSubmitted: (_) {
                    if (!_busy && configured) _submit();
                  },
                ),
              ),
            ] else ...[
              if (creatingAccount) ...[
                labeledField(
                  'DISPLAY NAME',
                  'required',
                  TextFormField(
                    key: const Key('account-name'),
                    controller: _name,
                    enabled: !_busy,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.name],
                    style: fieldText,
                    decoration: field('your name'),
                    validator:
                        (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Enter your name.'
                                : null,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              labeledField(
                creatingAccount ? 'EMAIL' : 'EMAIL ADDRESS',
                creatingAccount ? 'verification required' : 'REQ_FIELD',
                annotationStyle: creatingAccount ? null : micro,
                TextFormField(
                  key: const Key('account-email'),
                  controller: _email,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  style: fieldText,
                  decoration: field(
                    creatingAccount
                        ? 'engineer@company.com'
                        : 'user@buildify.internal',
                    prefix:
                        creatingAccount
                            ? null
                            : const Icon(
                              Icons.terminal,
                              size: 16,
                              color: muted,
                            ),
                  ),
                  validator: _validateEmail,
                ),
              ),
              const SizedBox(height: 16),
              labeledField(
                creatingAccount ? 'PASSWORD' : 'PASSPHRASE',
                creatingAccount ? 'minimum 8 characters' : '',
                TextFormField(
                  key: const Key('account-password'),
                  controller: _password,
                  enabled: !_busy,
                  obscureText: _hidePassword,
                  autofillHints: [
                    creatingAccount
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  style: fieldText,
                  decoration: field(
                    '\u2022' * 16,
                    prefix:
                        creatingAccount
                            ? null
                            : const Icon(
                              Icons.key_outlined,
                              size: 16,
                              color: muted,
                            ),
                    suffix: passwordVisibility(
                      _hidePassword,
                      'password',
                      () => setState(() => _hidePassword = !_hidePassword),
                    ),
                  ),
                  textInputAction:
                      creatingAccount
                          ? TextInputAction.next
                          : TextInputAction.done,
                  validator: _validatePassword,
                  onFieldSubmitted:
                      creatingAccount
                          ? null
                          : (_) {
                            if (!_busy && configured) _submit();
                          },
                ),
              ),
              if (creatingAccount) ...[
                const SizedBox(height: 16),
                labeledField(
                  'CONFIRM PASSWORD',
                  '',
                  TextFormField(
                    key: const Key('account-confirm-password'),
                    controller: _confirmPassword,
                    enabled: !_busy,
                    obscureText: _hideConfirmation,
                    textInputAction: TextInputAction.done,
                    style: fieldText,
                    decoration: field(
                      '\u2022' * 16,
                      suffix: passwordVisibility(
                        _hideConfirmation,
                        'password confirmation',
                        () => setState(
                          () => _hideConfirmation = !_hideConfirmation,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty)
                        return 'Confirm your password.';
                      return value == _password.text
                          ? null
                          : 'Passwords do not match.';
                    },
                    onFieldSubmitted: (_) {
                      if (!_busy && configured) _submit();
                    },
                  ),
                ),
              ],
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy || !configured ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF2F3131),
                shape: RoundedRectangleBorder(borderRadius: radius),
              ),
              child: Text(
                _busy
                    ? (creatingAccount
                        ? '[ INITIALIZING ACCOUNT... ]'
                        : 'Please wait…')
                    : (_verify
                        ? 'Verify email'
                        : creatingAccount
                        ? '[ INITIALIZE ACCOUNT -> ]'
                        : '[ AUTHENTICATE_SESSION -> ]'),
                style: const TextStyle(
                  fontFamily: 'Space Mono',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
            if (_verify)
              TextButton(
                onPressed: _busy || _cooldown > 0 ? null : _resend,
                child: Text(
                  _cooldown > 0
                      ? 'Resend in ${_cooldown}s'
                      : 'Resend verification email',
                  style: caption,
                ),
              ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _message!,
                    style: caption.copyWith(
                      color:
                          _isError
                              ? Theme.of(context).colorScheme.error
                              : muted,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    const padding = EdgeInsets.symmetric(horizontal: 16, vertical: 24);
    return Scaffold(
      backgroundColor: const Color(0xFF131312),
      body: SafeArea(
        child: LayoutBuilder(
          builder:
              (context, viewport) => SingleChildScrollView(
                padding: padding,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: viewport.deflate(padding).maxHeight,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (creatingAccount)
                            credentials
                          else
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1B1B19),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black38,
                                    blurRadius: 42,
                                    offset: Offset(0, 22),
                                  ),
                                ],
                              ),
                              child: credentials,
                            ),
                          const SizedBox(height: 12),
                          if (_verify)
                            TextButton(
                              onPressed: _busy ? null : _resetForm,
                              child: Text(
                                'Back to sign in',
                                style: label.copyWith(color: Colors.white),
                              ),
                            )
                          else
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              children: [
                                Text(
                                  creatingAccount
                                      ? 'Already have credentials?'
                                      : 'New to Buildify?',
                                  style: caption,
                                ),
                                TextButton(
                                  onPressed: _busy ? null : _toggleSignup,
                                  child: Text(
                                    creatingAccount
                                        ? '[ Sign in ]'
                                        : '[ CREATE AN ACCOUNT ]',
                                    style: label.copyWith(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          OutlinedButton(
                            onPressed:
                                _busy
                                    ? null
                                    : () => Navigator.of(
                                      context,
                                    ).pushNamed('/projects'),
                            child: const Text(
                              'Continue with local hosting',
                              style: caption,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(hostedAccountServiceProvider);
    final account = ref.watch(hostedAccountProvider).valueOrNull;
    final startupMessage = ref.watch(hostedStartupMessageProvider);
    if (account == null) {
      return _buildAuthForm(service.isConfigured, startupMessage);
    }
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
                    'Your account',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
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
