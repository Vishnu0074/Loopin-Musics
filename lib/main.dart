import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'screens/login_page.dart';
import 'screens/home_shell.dart';
import 'screens/splash.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';
import 'bloc/auth_bloc.dart';

final GlobalKey<ScaffoldMessengerState> loopinScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

class LoopinApp extends StatelessWidget {
  const LoopinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AuthBloc(AuthService())..add(const AuthStarted()),
      child: Builder(
        builder: (context) {
          AuthService.onSessionExpired = () async {
            context.read<AuthBloc>().add(const SessionExpiredRequested());
          };

          return MaterialApp(
            scaffoldMessengerKey: loopinScaffoldMessengerKey,
            debugShowCheckedModeBanner: false,
            title: 'Loopin',
            theme: AppTheme.dark(),
            home: BlocListener<AuthBloc, AuthState>(
              listenWhen: (previous, current) =>
                  current is AuthUnauthenticated &&
                  current.message != null &&
                  current.message!.isNotEmpty,
              listener: (context, state) {
                if (state is AuthUnauthenticated) {
                  loopinScaffoldMessengerKey.currentState
                    ?..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(state.message!),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                }
              },
              child: const _AuthGate(),
            ),
          );
        },
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (state is AuthChecking) return const SplashScreen();
        if (state is AuthAuthenticated || state is AuthGuest) {
          return const HomeShell();
        }
        return const LoginPage();
      },
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LoopinApp());
}
