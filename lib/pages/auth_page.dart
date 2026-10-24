import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_model.dart';
import '../models/verification_models.dart';
import '../providers/ai_server_provider.dart';
import '../providers/auth_provider.dart';
import 'verification_page.dart';

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key});

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  late final AnimationController _meshController;

  bool _isLogin = true;
  bool _hidePassword = true;
  bool _submitting = false;
  AuthMethod _signupMethod = AuthMethod.email;
  String _selectedCountryCode = '+1';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _meshController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _meshController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _toggleMode(bool isLogin) {
    if (_isLogin == isLogin) return;
    setState(() {
      _isLogin = isLogin;
      _errorMessage = null;
    });
    _formKey.currentState?.reset();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    final authService = ref.read(authServiceProvider);

    if (_isLogin) {
      final result = await authService.login(
        identifier: _emailController.text,
        password: _passwordController.text,
      );

      if (!mounted) return;
      setState(() => _submitting = false);

      if (result.isSuccess) {
        final user = result.user as User;
        ref.read(currentUserProvider.notifier).state = user;
        ref.read(embeddedBackendProvider).devLogin(userName: user.name);
        Navigator.of(context).pushReplacementNamed('/projects');
      } else if (result.status == AuthStatus.pendingVerification) {
        // Redirect user to verification page to complete pending verification
        if (result.challenge != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VerificationPage(
                challenge: result.challenge,
                user: result.user as User?,
              ),
            ),
          );
        } else {
          setState(() {
            _errorMessage =
                'Account requires verification, but no active challenge found. Please re-register or contact support.';
          });
        }
      } else {
        setState(() => _errorMessage = result.message);
      }
    } else {
      // Signup flow
      final result = await authService.signUp(
        name: _nameController.text,
        password: _passwordController.text,
        email: _signupMethod == AuthMethod.email ? _emailController.text : null,
        phone: _signupMethod == AuthMethod.phone ? _phoneController.text : null,
        defaultCountryCode: _selectedCountryCode,
        method: _signupMethod,
      );

      if (!mounted) return;
      setState(() => _submitting = false);

      if (result.status == AuthStatus.pendingVerification &&
          result.challenge != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VerificationPage(
              challenge: result.challenge,
              user: result.user as User?,
            ),
          ),
        );
      } else {
        setState(() => _errorMessage = result.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AuthColors.background,
      body: Stack(
        children: [
          _MeshBackground(animation: _meshController),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: _AuthCard(
                    formKey: _formKey,
                    isLogin: _isLogin,
                    hidePassword: _hidePassword,
                    submitting: _submitting,
                    signupMethod: _signupMethod,
                    countryCode: _selectedCountryCode,
                    errorMessage: _errorMessage,
                    nameController: _nameController,
                    emailController: _emailController,
                    phoneController: _phoneController,
                    passwordController: _passwordController,
                    onModeChanged: _toggleMode,
                    onSignupMethodChanged: (method) {
                      setState(() {
                        _signupMethod = method;
                        _errorMessage = null;
                      });
                    },
                    onCountryCodeChanged: (code) {
                      setState(() => _selectedCountryCode = code);
                    },
                    onTogglePassword: () =>
                        setState(() => _hidePassword = !_hidePassword),
                    onSubmit: _submit,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthCard extends StatelessWidget {
  const _AuthCard({
    required this.formKey,
    required this.isLogin,
    required this.hidePassword,
    required this.submitting,
    required this.signupMethod,
    required this.countryCode,
    required this.errorMessage,
    required this.nameController,
    required this.emailController,
    required this.phoneController,
    required this.passwordController,
    required this.onModeChanged,
    required this.onSignupMethodChanged,
    required this.onCountryCodeChanged,
    required this.onTogglePassword,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final bool isLogin;
  final bool hidePassword;
  final bool submitting;
  final AuthMethod signupMethod;
  final String countryCode;
  final String? errorMessage;
  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final TextEditingController passwordController;
  final ValueChanged<bool> onModeChanged;
  final ValueChanged<AuthMethod> onSignupMethodChanged;
  final ValueChanged<String> onCountryCodeChanged;
  final VoidCallback onTogglePassword;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _AuthColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _AuthColors.border),
          ),
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _BrandMark(),
                const SizedBox(height: 24),
                Text(
                  isLogin ? 'welcome back' : 'create your account',
                  style: const TextStyle(
                    color: _AuthColors.text,
                    fontFamily: 'monospace',
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isLogin
                      ? 'login to manage your local services.'
                      : 'choose your verification method to activate your account.',
                  style: const TextStyle(
                    color: _AuthColors.muted,
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                if (errorMessage != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _AuthColors.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _AuthColors.error.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      errorMessage!,
                      style: const TextStyle(
                        color: _AuthColors.error,
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Signup verification method selector
                if (!isLogin) ...[
                  const Text(
                    'verification method:',
                    style: TextStyle(
                      color: _AuthColors.text,
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _MethodTab(
                          label: 'Email Link',
                          icon: Icons.alternate_email,
                          isSelected: signupMethod == AuthMethod.email,
                          onTap: () => onSignupMethodChanged(AuthMethod.email),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MethodTab(
                          label: 'Phone OTP',
                          icon: Icons.phone_android,
                          isSelected: signupMethod == AuthMethod.phone,
                          onTap: () => onSignupMethodChanged(AuthMethod.phone),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    signupMethod == AuthMethod.email
                        ? 'A single-use link (valid for 30m) will be sent to your email.'
                        : 'A 6-digit SMS OTP code (valid for 5m) will be sent to your phone.',
                    style: const TextStyle(
                      color: _AuthColors.muted,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 18),
                ],

                // Name field for signup
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: isLogin
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _AuthField(
                            controller: nameController,
                            label: 'display name',
                            hint: 'your name or handle',
                            icon: Icons.person_outline,
                            validator: (value) => _required(value, 'name'),
                          ),
                        ),
                ),

                // Identifier fields
                if (isLogin) ...[
                  _AuthField(
                    controller: emailController,
                    label: 'email, phone, or username',
                    hint: 'you@example.com, +14155552671, or username',
                    icon: Icons.badge_outlined,
                    keyboardType: TextInputType.text,
                    validator: (value) => _required(value, 'credentials'),
                  ),
                ] else if (signupMethod == AuthMethod.email) ...[
                  _AuthField(
                    controller: emailController,
                    label: 'email address',
                    hint: 'you@example.com',
                    icon: Icons.alternate_email,
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'email is required';
                      }
                      if (!value.contains('@') || !value.contains('.')) {
                        return 'enter a valid email address';
                      }
                      return null;
                    },
                  ),
                ] else ...[
                  // Phone Number with Country Code
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: _AuthColors.field,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _AuthColors.border.withValues(alpha: 0.65),
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: countryCode,
                            dropdownColor: const Color(0xFF20201E),
                            style: const TextStyle(
                              color: _AuthColors.text,
                              fontFamily: 'monospace',
                              fontSize: 13,
                            ),
                            items: const [
                              DropdownMenuItem(value: '+1', child: Text('+1 US/CA')),
                              DropdownMenuItem(value: '+44', child: Text('+44 UK')),
                              DropdownMenuItem(value: '+91', child: Text('+91 IN')),
                              DropdownMenuItem(value: '+49', child: Text('+49 DE')),
                              DropdownMenuItem(value: '+33', child: Text('+33 FR')),
                              DropdownMenuItem(value: '+81', child: Text('+81 JP')),
                              DropdownMenuItem(value: '+61', child: Text('+61 AU')),
                              DropdownMenuItem(value: '+86', child: Text('+86 CN')),
                              DropdownMenuItem(value: '+55', child: Text('+55 BR')),
                              DropdownMenuItem(value: '+234', child: Text('+234 NG')),
                            ],
                            onChanged: (val) {
                              if (val != null) onCountryCodeChanged(val);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _AuthField(
                          controller: phoneController,
                          label: 'phone number',
                          hint: '4155552671',
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'phone number is required';
                            }
                            final digits = value.replaceAll(RegExp(r'\D'), '');
                            if (digits.length < 7 || digits.length > 15) {
                              return 'valid phone number required';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 16),
                _AuthField(
                  controller: passwordController,
                  label: 'password',
                  hint: 'minimum 8 characters',
                  icon: Icons.lock_outline,
                  obscureText: hidePassword,
                  suffixIcon: IconButton(
                    onPressed: onTogglePassword,
                    tooltip: hidePassword ? 'show password' : 'hide password',
                    icon: Icon(
                      hidePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: _AuthColors.muted,
                      size: 20,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'password is required';
                    }
                    if (value.length < 8) {
                      return 'use at least 8 characters';
                    }
                    return null;
                  },
                ),
                if (isLogin)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('password reset is coming soon.'),
                          ),
                        );
                      },
                      child: const Text('forgot password?'),
                    ),
                  )
                else
                  const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: submitting ? null : onSubmit,
                    style: FilledButton.styleFrom(
                      backgroundColor: _AuthColors.primary,
                      foregroundColor: _AuthColors.background,
                      disabledBackgroundColor: _AuthColors.primary.withValues(
                        alpha: 0.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: submitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _AuthColors.background,
                            ),
                          )
                        : Text(isLogin ? 'login' : 'verify & signup'),
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: TextButton(
                    onPressed: () => onModeChanged(!isLogin),
                    child: Text(
                      isLogin
                          ? 'new to buildify? signup'
                          : 'already have an account? login',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'by continuing, you agree to our terms and privacy policy.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _AuthColors.muted,
                      fontFamily: 'monospace',
                      fontSize: 10,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String? _required(String? value, String label) {
    return value == null || value.trim().isEmpty ? '$label is required' : null;
  }
}

class _MethodTab extends StatelessWidget {
  const _MethodTab({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? _AuthColors.primary.withValues(alpha: 0.12)
              : _AuthColors.field,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF2DD4BF)
                : _AuthColors.border.withValues(alpha: 0.5),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? const Color(0xFF2DD4BF) : _AuthColors.muted,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? _AuthColors.text : _AuthColors.muted,
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.validator,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final String? Function(String?) validator;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: const TextStyle(
        color: _AuthColors.text,
        fontFamily: 'monospace',
        fontSize: 14,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: _AuthColors.muted, size: 20),
        suffixIcon: suffixIcon,
        labelStyle: const TextStyle(
          color: _AuthColors.muted,
          fontFamily: 'monospace',
          fontSize: 12,
        ),
        hintStyle: const TextStyle(
          color: _AuthColors.muted,
          fontFamily: 'monospace',
          fontSize: 13,
        ),
        filled: true,
        fillColor: _AuthColors.field,
        errorStyle: const TextStyle(
          color: _AuthColors.error,
          fontFamily: 'monospace',
          fontSize: 10,
        ),
        border: _fieldBorder(_AuthColors.border),
        enabledBorder: _fieldBorder(_AuthColors.border),
        focusedBorder: _fieldBorder(const Color(0xFF2DD4BF)),
        errorBorder: _fieldBorder(_AuthColors.error),
        focusedErrorBorder: _fieldBorder(_AuthColors.error),
      ),
    );
  }

  InputBorder _fieldBorder(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: color.withValues(alpha: 0.65)),
      );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _AuthColors.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            '>_',
            style: TextStyle(
              color: _AuthColors.background,
              fontFamily: 'monospace',
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Text(
          'buildify',
          style: TextStyle(
            color: _AuthColors.text,
            fontFamily: 'monospace',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}

class _MeshBackground extends StatelessWidget {
  const _MeshBackground({required this.animation});

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
            Container(color: _AuthColors.background),
            Align(
              alignment: Alignment.topLeft,
              child: _glow(const Color(0xFF6F6F6A), 0.2),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: _glow(const Color(0xFF4E5552), 0.14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glow(Color color, double opacity) {
    return FractionallySizedBox(
      widthFactor: 0.75,
      heightFactor: 0.65,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: opacity), Colors.transparent],
          ),
        ),
      ),
    );
  }
}

class _AuthColors {
  static const background = Color(0xFF131312);
  static const card = Color(0x6620201E);
  static const field = Color(0x662A2A29);
  static const border = Color(0x1AFFFFFF);
  static const primary = Color(0xFFFFFFFF);
  static const text = Color(0xFFE5E2E0);
  static const muted = Color(0x99C4C7C8);
  static const error = Color(0xFFFFB4AB);
}
