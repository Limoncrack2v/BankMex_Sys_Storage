import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/repositories/auth_repository.dart';
import 'package:bank_storage_app/ui/screens/session/session_gate.dart';
import 'package:bank_storage_app/ui/screens/sign_in/sign_in_screen.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';

/// Usuario de Firebase de mentira; la prueba no usa ninguno de sus campos.
class _FakeUser extends Fake implements User {}

Future<void> _pumpGate(WidgetTester tester, SessionGate gate) =>
    tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: gate));

void main() {
  testWidgets('sin sesión guardada muestra el inicio de sesión', (
    tester,
  ) async {
    await _pumpGate(tester, SessionGate(restoreUser: () async => null));
    await tester.pumpAndSettle();
    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('espera a que Firebase cargue la sesión antes de decidir', (
    tester,
  ) async {
    final completer = Completer<User?>();
    await _pumpGate(
      tester,
      SessionGate(restoreUser: () async => completer.future),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(SignInScreen), findsNothing);
    completer.complete(null);
    await tester.pumpAndSettle();
    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('una sesión que ya no es válida regresa al inicio de sesión', (
    tester,
  ) async {
    await _pumpGate(
      tester,
      SessionGate(
        restoreUser: () async => _FakeUser(),
        resolveSession: (_) async => throw AuthException('x'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SignInScreen), findsOneWidget);
  });
}
