import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/ui/screens/sign_in/password_reset_screen.dart';
import 'package:bank_storage_app/ui/screens/sign_in/sign_in_screen.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:bank_storage_app/ui/widgets/app_buttons.dart';

Future<void> _pumpSignIn(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.light, home: const SignInScreen()),
  );
  await tester.pumpAndSettle();
}

Future<void> _openPasswordReset(WidgetTester tester) async {
  final link = find.text('¿Olvidaste tu contraseña?');
  await tester.ensureVisible(link);
  await tester.tap(link);
  await tester.pumpAndSettle();
}

PrimaryButton _button(WidgetTester tester, String label) =>
    tester.widget<PrimaryButton>(find.widgetWithText(PrimaryButton, label));

Future<void> _tapButton(WidgetTester tester, String label) async {
  final button = find.widgetWithText(PrimaryButton, label);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Sign In habilita el botón solo con correo y contraseña', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const SignInScreen()),
    );

    expect(find.text('Inicia sesión en tu cuenta BAMX'), findsOneWidget);
    expect(find.text('Correo electrónico'), findsOneWidget);
    expect(find.text('Usuario o correo'), findsNothing);

    PrimaryButton submitButton() => tester.widget<PrimaryButton>(
      find.widgetWithText(PrimaryButton, 'Iniciar sesión'),
    );

    expect(submitButton().onPressed, isNull);

    await tester.enterText(find.byType(TextField).at(0), 'maria@correo.com');
    await tester.pump();
    expect(submitButton().onPressed, isNull);

    await tester.enterText(find.byType(TextField).at(1), '123456');
    await tester.pump();
    expect(submitButton().onPressed, isNotNull);
  });

  testWidgets('Sign In muestra un error si no se puede iniciar sesión', (
    WidgetTester tester,
  ) async {
    await _pumpSignIn(tester);

    await tester.enterText(find.byType(TextField).at(0), 'maria@correo.com');
    await tester.enterText(find.byType(TextField).at(1), '123456');
    await tester.pump();

    await _tapButton(tester, 'Iniciar sesión');

    expect(
      find.text('No se pudo iniciar sesión. Intenta de nuevo.'),
      findsOneWidget,
    );
    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('¿Olvidaste tu contraseña? abre Recuperar contraseña', (
    WidgetTester tester,
  ) async {
    await _pumpSignIn(tester);
    await _openPasswordReset(tester);

    expect(find.byType(PasswordResetScreen), findsOneWidget);
    expect(find.text('Recuperar contraseña'), findsOneWidget);
    expect(find.text('Correo electrónico'), findsOneWidget);
    expect(find.text('Volver a inicio de sesión'), findsOneWidget);

    await tester.tap(find.text('Volver a inicio de sesión'));
    await tester.pumpAndSettle();

    expect(find.byType(PasswordResetScreen), findsNothing);
    expect(find.text('Inicia sesión en tu cuenta BAMX'), findsOneWidget);
  });

  testWidgets('Enviar instrucciones se habilita solo con un correo', (
    WidgetTester tester,
  ) async {
    await _pumpSignIn(tester);
    await _openPasswordReset(tester);

    expect(_button(tester, 'Enviar instrucciones').onPressed, isNull);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(_button(tester, 'Enviar instrucciones').onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'maria@correo.com');
    await tester.pump();
    expect(_button(tester, 'Enviar instrucciones').onPressed, isNotNull);
  });

  testWidgets('Recuperar contraseña muestra un error si no se puede enviar', (
    WidgetTester tester,
  ) async {
    await _pumpSignIn(tester);
    await _openPasswordReset(tester);

    await tester.enterText(find.byType(TextField), 'maria@correo.com');
    await tester.pump();
    await _tapButton(tester, 'Enviar instrucciones');

    expect(
      find.text('No se pudo enviar el correo. Intenta de nuevo.'),
      findsOneWidget,
    );
    expect(find.byType(PasswordResetScreen), findsOneWidget);
  });
}
