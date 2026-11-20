import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/auth_bloc.dart';
import '../theme/app_theme.dart';
import 'signup_page.dart';
import '../widgets/loopin_snackbar.dart';

class LoginPage extends StatefulWidget {
  final String initialEmail;
  const LoginPage({super.key, this.initialEmail = ''});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  late final TextEditingController id;
  final pass = TextEditingController();
  late final AnimationController _intro;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  bool obscure = true;

  @override
  void initState() {
    super.initState();
    id = TextEditingController(text: widget.initialEmail);
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _fade = CurvedAnimation(parent: _intro, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic));
    _intro.forward();
  }

  @override
  void dispose() {
    id.dispose();
    pass.dispose();
    _intro.dispose();
    super.dispose();
  }

  Future<void> _openSignup() async {
    final email = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const SignupPage()),
    );
    if (email != null && mounted) id.text = email;
  }

  void _submit() {
    final email = id.text.trim();
    final password = pass.text;
    if (email.isEmpty || password.isEmpty) {
      LoopinSnackBar.show(
        context,
        'Enter your email and password.',
        type: LoopinSnackBarType.error,
      );
      return;
    }
    context.read<AuthBloc>().add(LoginSubmitted(email, password));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Subtle ambient radial glow at the top center
          Positioned(
            top: -100,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 360,
                height: 360,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.accent.withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 390),
                  child: FadeTransition(
                    opacity: _fade,
                    child: SlideTransition(
                      position: _slide,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. Compact Minimal Branding
                          Center(
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.accent.withValues(alpha: 0.16),
                                    blurRadius: 28,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                'assets/images/Lloopin.png',
                                height: 50,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Display Tagline
                          Text(
                            'Because one play is never enough.',
                            textAlign: TextAlign.center,
                            style: AppFonts.display(
                              fontSize: 23,
                              fontWeight: FontWeight.bold,
                              color: Colors.white.withValues(alpha: 0.90),
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 32),

                          // 2. Minimal Heading
                          Text(
                            'Sign In',
                            style: AppFonts.mono(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Enter your credentials to continue listening.',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 13,
                              letterSpacing: 0.1,
                            ),
                          ),
                          const SizedBox(height: 26),

                          // 3. Email Input
                          TextField(
                            controller: id,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              labelText: 'Email address',
                              labelStyle: const TextStyle(fontSize: 13, color: AppColors.muted),
                              prefixIcon: const Icon(
                                Icons.mail_outline_rounded,
                                size: 19,
                                color: AppColors.muted,
                              ),
                              filled: true,
                              fillColor: AppColors.surface,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // 4. Password Input
                          TextField(
                            controller: pass,
                            obscureText: obscure,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submit(),
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              labelStyle: const TextStyle(fontSize: 13, color: AppColors.muted),
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                                size: 19,
                                color: AppColors.muted,
                              ),
                              suffixIcon: IconButton(
                                iconSize: 19,
                                onPressed: () => setState(() => obscure = !obscure),
                                icon: Icon(
                                  obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: AppColors.muted,
                                ),
                              ),
                              filled: true,
                              fillColor: AppColors.surface,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),

                          // 5. Action Buttons & Bloc Handling
                          BlocConsumer<AuthBloc, AuthState>(
                            listener: (context, state) {
                              if (state is AuthAuthenticated && Navigator.of(context).canPop()) {
                                Navigator.of(context).pop();
                              } else if (state is AuthUnauthenticated && state.message != null) {
                                LoopinSnackBar.show(context, state.message!);
                              }
                            },
                            builder: (context, state) {
                              final loading = state is AuthLoading;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Primary Sign In Button
                                  SizedBox(
                                    height: 48,
                                    child: FilledButton(
                                      onPressed: loading ? null : _submit,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: AppColors.accent,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: loading
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Text(
                                              'Sign In',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  // Subtle Divider
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Divider(
                                          color: Colors.white.withValues(alpha: 0.08),
                                          thickness: 1,
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 14),
                                        child: Text(
                                          'or',
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.35),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Divider(
                                          color: Colors.white.withValues(alpha: 0.08),
                                          thickness: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),

                                  // Secondary Continue as Guest Button
                                  SizedBox(
                                    height: 46,
                                    child: OutlinedButton.icon(
                                      onPressed: loading
                                          ? null
                                          : () => context.read<AuthBloc>().add(
                                                const GuestRequested(),
                                              ),
                                      icon: const Icon(
                                        Icons.person_outline_rounded,
                                        size: 18,
                                        color: Colors.white70,
                                      ),
                                      label: const Text(
                                        'Continue as guest',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.white70,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        side: BorderSide(
                                          color: Colors.white.withValues(alpha: 0.12),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        backgroundColor: Colors.white.withValues(alpha: 0.02),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 24),

                          // 6. Minimal Footer
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Text(
                                "Don't have an account?",
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 13,
                                ),
                              ),
                              TextButton(
                                onPressed: _openSignup,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  foregroundColor: AppColors.accent,
                                  textStyle: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                child: const Text('Create one'),
                              ),
                            ],
                          ),
                        ],
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
}
