import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_model.dart';
import '../models/verification_models.dart';
import '../providers/ai_server_provider.dart';
import '../providers/auth_provider.dart';

class VerificationPage extends ConsumerStatefulWidget {
  const VerificationPage({
    super.key,
    this.challenge,
    this.initialToken,
    this.user,
  });

  final ChallengePublicInfo? challenge;
  final String? initialToken;
  final User? user;

  @override
  ConsumerState<VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends ConsumerState<VerificationPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _meshController;
  final _otpController = TextEditingController();
  final _manualTokenController = TextEditingController();

  ChallengePublicInfo? _challenge;
  bool _isLoading = false;
  bool _isSuccess = false;
  String? _errorMessage;
  String? _infoMessage;
  int _cooldownRemaining = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _challenge = widget.challenge;
    _meshController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat(reverse: true);

    if (_challenge != null) {
      _startCooldown(_challenge!.cooldownSeconds);
    }

    if (widget.initialToken != null && widget.initialToken!.isNotEmpty) {
      _manualTokenController.text = widget.initialToken!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _verifyEmailToken(widget.initialToken!);
      });
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _meshController.dispose();
    _otpController.dispose();
    _manualTokenController.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() => _cooldownRemaining = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_cooldownRemaining <= 1) {
        timer.cancel();
        setState(() => _cooldownRemaining = 0);
      } else {
        setState(() => _cooldownRemaining--);
      }
    });
  }

  Future<void> _verifyEmailToken(String token) async {
    if (token.trim().isEmpty) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    final authService = ref.read(authServiceProvider);
    final result = await authService.verifyEmailToken(token);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.isSuccess) {
      setState(() {
        _isSuccess = true;
        _infoMessage = result.message;
      });
      _onVerificationComplete(result.user as User?);
    } else {
      setState(() => _errorMessage = result.message);
    }
  }

  Future<void> _verifyPhoneOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() => _errorMessage = 'Please enter a 6-digit verification code.');
      return;
    }
    if (_challenge == null) {
      setState(() => _errorMessage = 'Challenge session missing. Please request a new code.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    final authService = ref.read(authServiceProvider);
    final result = await authService.verifyPhoneOtp(
      challengeId: _challenge!.challengeId,
      rawOtp: otp,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.isSuccess) {
      setState(() {
        _isSuccess = true;
        _infoMessage = result.message;
      });
      _onVerificationComplete(result.user as User?);
    } else {
      setState(() => _errorMessage = result.message);
    }
  }

  Future<void> _resend() async {
    if (_challenge == null || _cooldownRemaining > 0 || _isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    final authService = ref.read(authServiceProvider);
    final result = await authService.resendVerification(
      challengeId: _challenge!.challengeId,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.challenge != null) {
      setState(() {
        _challenge = result.challenge;
        _infoMessage = result.message;
      });
      _startCooldown(result.challenge!.cooldownSeconds);
    } else {
      setState(() => _errorMessage = result.message);
    }
  }

  void _onVerificationComplete(User? user) {
    if (user != null) {
      ref.read(currentUserProvider.notifier).state = user;
      ref.read(embeddedBackendProvider).devLogin(userName: user.name);
    }
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/projects', (route) => false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEmail = _challenge?.channel == VerificationChannel.email ||
        widget.initialToken != null;

    return Scaffold(
      backgroundColor: const Color(0xFF131312),
      body: Stack(
        children: [
          _VerificationMesh(animation: _meshController),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: const Color(0x6620201E),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0x1AFFFFFF)),
                        ),
                        child: _isSuccess
                            ? _buildSuccessView()
                            : (isEmail ? _buildEmailView() : _buildPhoneView()),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF2DD4BF).withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF2DD4BF), width: 1.5),
          ),
          child: const Icon(
            Icons.check_circle_outline,
            color: Color(0xFF2DD4BF),
            size: 32,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'verification complete',
          style: TextStyle(
            color: Color(0xFFE5E2E0),
            fontFamily: 'monospace',
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _infoMessage ?? 'your account is verified. Redirecting to workspace...',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0x99C4C7C8),
            fontFamily: 'monospace',
            fontSize: 13,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(
              '/projects',
              (route) => false,
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFFFFFF),
              foregroundColor: const Color(0xFF131312),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('proceed to dashboard'),
          ),
        ),
      ],
    );
  }

  Widget _buildEmailView() {
    final masked = _challenge?.maskedTarget ?? 'your email address';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0x332DD4BF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.mark_email_unread_outlined,
                color: Color(0xFF2DD4BF),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'verify your email',
                style: TextStyle(
                  color: Color(0xFFE5E2E0),
                  fontFamily: 'monospace',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'We sent a secure verification link to $masked. Please check your inbox and click the link to activate your Buildify workspace.',
          style: const TextStyle(
            color: Color(0x99C4C7C8),
            fontFamily: 'monospace',
            fontSize: 13,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Note: Links expire after 30 minutes. The email must be verified on the server before access is granted.',
          style: TextStyle(
            color: Color(0x80C4C7C8),
            fontFamily: 'monospace',
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 20),
        if (_errorMessage != null) _buildAlertBox(_errorMessage!, isError: true),
        if (_infoMessage != null) _buildAlertBox(_infoMessage!, isError: false),
        const SizedBox(height: 12),
        const Divider(color: Color(0x1AFFFFFF)),
        const SizedBox(height: 12),
        const Text(
          'or paste verification token manually:',
          style: TextStyle(
            color: Color(0xFFE5E2E0),
            fontFamily: 'monospace',
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _manualTokenController,
          style: const TextStyle(
            color: Color(0xFFE5E2E0),
            fontFamily: 'monospace',
            fontSize: 13,
          ),
          decoration: _inputDecoration(
            hint: 'paste token here',
            icon: Icons.vpn_key_outlined,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: FilledButton(
            onPressed: _isLoading
                ? null
                : () => _verifyEmailToken(_manualTokenController.text),
            style: _primaryButtonStyle(),
            child: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF131312),
                    ),
                  )
                : const Text('verify token'),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: _cooldownRemaining > 0 || _isLoading ? null : _resend,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(
                _cooldownRemaining > 0
                    ? 'resend in ${_cooldownRemaining}s'
                    : 'resend email',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pushReplacementNamed('/'),
              child: const Text(
                'back to login',
                style: TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPhoneView() {
    final masked = _challenge?.maskedTarget ?? 'your phone number';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0x332DD4BF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.sms_outlined,
                color: Color(0xFF2DD4BF),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'enter otp code',
                style: TextStyle(
                  color: Color(0xFFE5E2E0),
                  fontFamily: 'monospace',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Enter the 6-digit verification code sent via SMS to $masked.',
          style: const TextStyle(
            color: Color(0x99C4C7C8),
            fontFamily: 'monospace',
            fontSize: 13,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Code expires in 5 minutes. Codes are single-use.',
          style: TextStyle(
            color: Color(0x80C4C7C8),
            fontFamily: 'monospace',
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 20),
        if (_errorMessage != null) _buildAlertBox(_errorMessage!, isError: true),
        if (_infoMessage != null) _buildAlertBox(_infoMessage!, isError: false),
        const SizedBox(height: 12),
        TextFormField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFE5E2E0),
            fontFamily: 'monospace',
            fontSize: 24,
            letterSpacing: 10,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: '000000',
            hintStyle: const TextStyle(
              color: Color(0x33C4C7C8),
              letterSpacing: 10,
            ),
            filled: true,
            fillColor: const Color(0x662A2A29),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF2DD4BF)),
            ),
          ),
          onFieldSubmitted: (_) => _verifyPhoneOtp(),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: _isLoading ? null : _verifyPhoneOtp,
            style: _primaryButtonStyle(),
            child: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF131312),
                    ),
                  )
                : const Text('verify code'),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: _cooldownRemaining > 0 || _isLoading ? null : _resend,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(
                _cooldownRemaining > 0
                    ? 'resend in ${_cooldownRemaining}s'
                    : 'resend code',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pushReplacementNamed('/'),
              child: const Text(
                'back to login',
                style: TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAlertBox(String message, {required bool isError}) {
    final color = isError ? const Color(0xFFFFB4AB) : const Color(0xFF86EFAC);
    final bgColor = isError ? const Color(0x26FFB4AB) : const Color(0x2686EFAC);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: color,
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.4,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({required String hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: const Color(0x99C4C7C8), size: 20),
      filled: true,
      fillColor: const Color(0x662A2A29),
      hintStyle: const TextStyle(color: Color(0x99C4C7C8), fontSize: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF2DD4BF)),
      ),
    );
  }

  ButtonStyle _primaryButtonStyle() {
    return FilledButton.styleFrom(
      backgroundColor: const Color(0xFFFFFFFF),
      foregroundColor: const Color(0xFF131312),
      disabledBackgroundColor: const Color(0x80FFFFFF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

class _VerificationMesh extends StatelessWidget {
  const _VerificationMesh({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) =>
          Transform.scale(scale: 1 + animation.value * 0.08, child: child),
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: const Color(0xFF131312)),
            Align(
              alignment: Alignment.topLeft,
              child: FractionallySizedBox(
                widthFactor: 0.75,
                heightFactor: 0.65,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF2DD4BF).withValues(alpha: 0.12),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: FractionallySizedBox(
                widthFactor: 0.75,
                heightFactor: 0.65,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF6F6F6A).withValues(alpha: 0.15),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
