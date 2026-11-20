import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:loopin/bloc/auth_bloc.dart';
import 'package:loopin/main.dart';
import 'package:loopin/screens/login_page.dart';
import 'package:loopin/screens/splash.dart';
import 'package:loopin/services/auth_service.dart';

void main() {
  testWidgets('Loopin app boots', (WidgetTester tester) async {
    await tester.pumpWidget(const LoopinApp());
    await tester.pump();

    expect(find.byType(LoopinApp), findsOneWidget);
  });

  testWidgets('SplashScreen renders and handles interactive touches', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashScreen(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('Because one play is never enough.'), findsOneWidget);

    // Simulate interactive tap on the background
    await tester.tap(find.byType(SplashScreen));
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('LoginPage renders minimal interface with fields and buttons', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider(
          create: (_) => AuthBloc(AuthService()),
          child: const LoginPage(initialEmail: 'test@example.com'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('Sign In'), findsWidgets);
    expect(find.text('Because one play is never enough.'), findsOneWidget);
    expect(find.text('test@example.com'), findsOneWidget);
    expect(find.text('Continue as guest'), findsOneWidget);
    expect(find.text('Create one'), findsOneWidget);
  });
}
