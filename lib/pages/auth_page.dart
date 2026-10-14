import 'dart:ui';

import 'package:flutter/material.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  late final AnimationController _meshController;

  bool _isLogin = true;
  bool _hidePassword = true;
  bool _submitting = false;

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
    _passwordController.dispose();
    super.dispose();
  }

  void _toggleMode(bool isLogin) {
    if (_isLogin == isLogin) return;
    setState(() => _isLogin = isLogin);
    _formKey.currentState?.reset();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);

    // Authentication can be connected to the backend here without changing
    // the form or navigation contract.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    setState(() => _submitting = false);
    Navigator.of(context).pushReplacementNamed('/projects');
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
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: _AuthCard(
                    formKey: _formKey,
                    isLogin: _isLogin,
                    hidePassword: _hidePassword,
                    submitting: _submitting,
                    nameController: _nameController,
                    emailController: _emailController,
                    passwordController: _passwordController,
                    onModeChanged: _toggleMode,
                    onTogglePassword:
                        () => setState(() => _hidePassword = !_hidePassword),
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
    required this.nameController,
    required this.emailController,
    required this.passwordController,
    required this.onModeChanged,
    required this.onTogglePassword,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final bool isLogin;
  final bool hidePassword;
  final bool submitting;
  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final ValueChanged<bool> onModeChanged;
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
                const SizedBox(height: 28),
                Text(
                  isLogin ? 'welcome back' : 'create your account',
                  style: TextStyle(
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
                      : 'start building your local service workspace.',
                  style: TextStyle(
                    color: _AuthColors.muted,
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child:
                      isLogin
                          ? const SizedBox.shrink()
                          : Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _AuthField(
                              controller: nameController,
                              label: 'display name',
                              hint: 'your name',
                              icon: Icons.person_outline,
                              validator: (value) => _required(value, 'name'),
                            ),
                          ),
                ),
                _AuthField(
                  controller: emailController,
                  label: isLogin ? 'email or username' : 'email address',
                  hint:
                      isLogin
                          ? 'you@example.com or username'
                          : 'you@example.com',
                  icon: Icons.alternate_email,
                  keyboardType:
                      isLogin ? TextInputType.text : TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'email or username is required';
                    }
                    if (!isLogin &&
                        (!value.contains('@') || !value.contains('.'))) {
                      return 'enter a valid email';
                    }
                    return null;
                  },
                ),
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
                    child:
                        submitting
                            ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _AuthColors.background,
                              ),
                            )
                            : Text(isLogin ? 'login' : 'signup'),
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
        focusedBorder: _fieldBorder(_AuthColors.primary),
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
      builder:
          (context, child) =>
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
