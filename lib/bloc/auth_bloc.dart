import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/auth_user.dart';
import '../services/auth_service.dart';

sealed class AuthEvent {
  const AuthEvent();
}

class AuthStarted extends AuthEvent {
  const AuthStarted();
}

class LoginSubmitted extends AuthEvent {
  final String email;
  final String password;
  const LoginSubmitted(this.email, this.password);
}

class SignupSubmitted extends AuthEvent {
  final String email;
  final String phone;
  final String password;
  final String confirm;
  const SignupSubmitted(this.email, this.phone, this.password, this.confirm);
}

class GuestRequested extends AuthEvent {
  const GuestRequested();
}

class LogoutRequested extends AuthEvent {
  const LogoutRequested();
}

class SessionExpiredRequested extends AuthEvent {
  const SessionExpiredRequested();
}

sealed class AuthState {
  const AuthState();
}

class AuthChecking extends AuthState {
  const AuthChecking();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthUnauthenticated extends AuthState {
  final String? message;
  const AuthUnauthenticated([this.message]);
}

class AuthAuthenticated extends AuthState {
  final AuthUser user;
  const AuthAuthenticated(this.user);
}

class AuthGuest extends AuthState {
  const AuthGuest();
}

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthService service;

  AuthBloc(this.service) : super(const AuthChecking()) {
    on<AuthStarted>((event, emit) async {
      try {
        final user = await service.restore();
        // Listening is available without an account. Restore an existing account
        // when present; otherwise start directly in guest mode.
        emit(user == null ? const AuthGuest() : AuthAuthenticated(user));
      } catch (error) {
        // A storage/plugin failure must never leave the web app on a blank
        // splash screen. Authentication can still be completed interactively.
        // Authentication failures must not block local music playback.
        emit(const AuthGuest());
      }
    });

    on<LoginSubmitted>((event, emit) async {
      emit(const AuthLoading());
      try {
        emit(AuthAuthenticated(await service.login(event.email, event.password)));
      } catch (error) {
        emit(AuthUnauthenticated(error.toString()));
      }
    });

    on<SignupSubmitted>((event, emit) async {
      emit(const AuthLoading());
      try {
        await service.register(
          email: event.email,
          phone: event.phone,
          password: event.password,
          passwordConfirm: event.confirm,
        );
        emit(const AuthUnauthenticated(
          'Account created successfully. Please sign in.',
        ));
      } catch (error) {
        emit(AuthUnauthenticated(error.toString()));
      }
    });

    on<GuestRequested>((event, emit) async {
      await service.logout();
      emit(const AuthGuest());
    });

    on<LogoutRequested>((event, emit) async {
      await service.logout();
      emit(const AuthGuest());
    });

    on<SessionExpiredRequested>((event, emit) async {
      await service.logout();
      // An expired account session should downgrade gracefully to guest mode.
      emit(const AuthGuest());
    });
  }
}
