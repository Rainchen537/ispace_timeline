import 'dart:ui';

import 'package:flutter/material.dart';

import '../state/app_session_controller.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.controller});

  final AppSessionController controller;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _usernameController.addListener(_clearError);
    _passwordController.addListener(_clearError);
  }

  @override
  void dispose() {
    _usernameController.removeListener(_clearError);
    _passwordController.removeListener(_clearError);
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  void _clearError() {
    if (widget.controller.error != null) {
      widget.controller.clearError();
    }
  }

  Future<void> _handleLogin() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    await widget.controller.login(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        final busy = widget.controller.isBusy;
        final restoring =
            widget.controller.isRestoringSession &&
            !widget.controller.isLoggedIn;

        return Scaffold(
          backgroundColor: Colors.white,
          resizeToAvoidBottomInset: false,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final heroHeight = (constraints.maxHeight * 0.31)
                  .clamp(210.0, 280.0)
                  .toDouble();
              final footerTopSpacing =
                  (constraints.maxHeight - heroHeight - 340)
                      .clamp(44.0, 180.0)
                      .toDouble();

              return Stack(
                children: [
                  SingleChildScrollView(
                    padding: EdgeInsets.only(bottom: bottomInset),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Column(
                        children: [
                          _LoginHero(height: heroHeight),
                          Transform.translate(
                            offset: const Offset(0, -24),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                34,
                                20,
                                32,
                              ),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(16),
                                  topRight: Radius.circular(16),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildForm(context, busy: busy),
                                  SizedBox(height: footerTopSpacing),
                                  _buildFooterNote(context),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (restoring) const _RestoreOverlay(),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildForm(BuildContext context, {required bool busy}) {
    final error = widget.controller.error;

    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InputField(
              label: 'User Id',
              child: TextFormField(
                controller: _usernameController,
                focusNode: _usernameFocusNode,
                enabled: !busy,
                autofillHints: const [AutofillHints.username],
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                onFieldSubmitted: (_) => _passwordFocusNode.requestFocus(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
                decoration: const InputDecoration(
                  hintText: 'Enter your BNBU account',
                  hintStyle: TextStyle(
                    color: Color(0xFFA0A8B5),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your user ID';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 22),
            _InputField(
              label: 'Password',
              child: TextFormField(
                controller: _passwordController,
                focusNode: _passwordFocusNode,
                enabled: !busy,
                autofillHints: const [AutofillHints.password],
                autocorrect: false,
                enableSuggestions: false,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                onFieldSubmitted: (_) => _handleLogin(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
                decoration: const InputDecoration(
                  hintText: 'Enter your iSpace password',
                  hintStyle: TextStyle(
                    color: Color(0xFFA0A8B5),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your password';
                  }
                  return null;
                },
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 22),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFDA4AF)),
                ),
                child: Text(
                  error,
                  style: const TextStyle(
                    color: Color(0xFFBE123C),
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 30),
            _LoginButton(
              enabled: !busy,
              onTap: _handleLogin,
              child: widget.controller.isLoggingIn
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Sign In'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooterNote(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text.rich(
        TextSpan(
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 12.5,
            height: 1.65,
            color: const Color(0xFF7C8797),
          ),
          children: const [
            TextSpan(
              text: '感谢您使用掌上BNBU\n',
              style: TextStyle(
                color: Color(0xFF5B6676),
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(text: '登录凭据仅保存在设备系统安全存储中，用于恢复登录；退出登录会清除凭据。\n'),
            TextSpan(text: '本应用为非官方客户端。使用问题可反馈至 '),
            TextSpan(
              text: 'v530026091@mail.bnbu.edu.cn',
              style: TextStyle(
                color: Color(0xFF1D4E89),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _LoginHero extends StatelessWidget {
  const _LoginHero({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/branding/new2.jpg',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.08),
                  Colors.black.withValues(alpha: 0.18),
                  Colors.black.withValues(alpha: 0.30),
                ],
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Align(
              alignment: const Alignment(0, -0.58),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Image.asset(
                  'assets/branding/bnbu.png',
                  height: 80,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _LoginButton extends StatelessWidget {
  const _LoginButton({
    required this.enabled,
    required this.onTap,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(18);
    final background = enabled
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xD92788BA), Color(0xC91573AD)],
          )
        : const LinearGradient(colors: [Color(0x8894A3B8), Color(0x8894A3B8)]);

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: background,
              borderRadius: borderRadius,
              border: Border.all(
                color: enabled
                    ? const Color(0xCCE1F4FF)
                    : const Color(0x80FFFFFF),
              ),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: const Color(0x99156EA8).withValues(alpha: 0.24),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: enabled ? onTap : null,
                child: Center(
                  child: DefaultTextStyle(
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    child: IconTheme(
                      data: const IconThemeData(color: Colors.white),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RestoreOverlay extends StatelessWidget {
  const _RestoreOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xFF06143B).withValues(alpha: 0.22),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 28),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.10),
                  blurRadius: 20,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
                SizedBox(width: 14),
                Text(
                  'Restoring previous session',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
