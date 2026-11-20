import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/auth_bloc.dart';
import '../theme/app_theme.dart';
import '../widgets/loopin_snackbar.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});
  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage>
    with SingleTickerProviderStateMixin {
  final email = TextEditingController();
  final phone = TextEditingController();
  final pass = TextEditingController();
  final confirm = TextEditingController();
  late final AnimationController _intro;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  bool obscure = true;
  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fade = CurvedAnimation(parent: _intro, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, .12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic));
    _intro.forward();
  }

  @override
  void dispose() {
    email.dispose();
    phone.dispose();
    pass.dispose();
    confirm.dispose();
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Create account'),
      ),
      body: ColoredBox(
        color: AppColors.background,
        child: Stack(
          children: [
            const Positioned(
              top: 75,
              right: 28,
              child: Text(
                '♫⋆',
                style: TextStyle(color: Colors.white24, fontSize: 20),
              ),
            ),
            const Positioned(
              top: 220,
              left: 16,
              child: Text(
                '♪',
                style: TextStyle(color: Colors.white24, fontSize: 18),
              ),
            ),
            const Positioned(
              top: 360,
              right: 30,
              child: Text(
                '₊˚♬',
                style: TextStyle(color: Colors.white24, fontSize: 17),
              ),
            ),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 30),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: FadeTransition(
                      opacity: _fade,
                      child: SlideTransition(
                        position: _slide,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            Center(
                              child: Image.asset(
                                'assets/images/Lloopin.png',
                                height: 68,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Center(
                              child: Text(
                                '♫  Your music. Your loop.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(height: 44),
                            Text(
                              'Create your account.',
                              style: AppFonts.mono(
                                fontSize: 48,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 7),
                            const Text(
                              'Join Loopin and make every play count.',
                              style: TextStyle(color: Colors.white60),
                            ),
                            const SizedBox(height: 28),
                            TextField(
                              controller: email,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Email address',
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: phone,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Phone number',
                                prefixIcon: Icon(Icons.phone_outlined),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: pass,
                              obscureText: obscure,
                              decoration: const InputDecoration(
                                labelText: 'Password (8+ characters)',
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: confirm,
                              obscureText: obscure,
                              decoration: const InputDecoration(
                                labelText: 'Confirm password',
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                            ),
                            const SizedBox(height: 24),
                            BlocConsumer<AuthBloc, AuthState>(
                              listener: (context, state) {
                                if (state is AuthUnauthenticated &&
                                    state.message != null) {
                                  final message = state.message!;
                                  LoopinSnackBar.show(context, message);
                                  if (message.startsWith('Account created')) {
                                    Navigator.pop(context, email.text.trim());
                                  }
                                }
                              },
                              builder: (context, state) {
                                final loading = state is AuthLoading;
                                return SizedBox(
                                  width: double.infinity,
                                  height: 54,
                                  child: FilledButton(
                                    onPressed: loading
                                        ? null
                                        : () {
                                            final emailValue = email.text
                                                .trim();
                                            final phoneValue = phone.text
                                                .trim();
                                            final password = pass.text;
                                            final confirmation = confirm.text;
                                            if (emailValue.isEmpty ||
                                                phoneValue.isEmpty ||
                                                password.isEmpty ||
                                                confirmation.isEmpty) {
                                              LoopinSnackBar.show(
                                                context,
                                                'Complete all fields to create your account.',
                                                type: LoopinSnackBarType.error,
                                              );
                                              return;
                                            }
                                            context.read<AuthBloc>().add(
                                              SignupSubmitted(
                                                emailValue,
                                                phoneValue,
                                                password,
                                                confirmation,
                                              ),
                                            );
                                          },
                                    child: loading
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Text('Create account'),
                                  ),
                                );
                              },
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
      ),
    );
  }
}
