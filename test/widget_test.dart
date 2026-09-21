import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/ui/screens/sign_in/sign_in_screen.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:bank_storage_app/ui/widgets/app_buttons.dart';

void main() {
  testWidgets('Sign In habilita el botón solo con correo y contraseña', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const SignInScreen()),
    );

    expect(find.text('Inicia sesión en tu cuenta BAMX'), findsOneWidget);

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
}
