import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/repositories/auth_repository.dart';
import 'package:bank_storage_app/ui/screens/sign_in/staff_sign_up_screen.dart';
import 'package:bank_storage_app/ui/screens/staff/register_account_sheet.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:bank_storage_app/ui/widgets/app_buttons.dart';

Future<void> _pumpSheet(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: RegisterAccountSheet()),
    ),
  );
  await tester.pumpAndSettle();
}

PrimaryButton _createButton(WidgetTester tester) => tester
    .widget<PrimaryButton>(find.widgetWithText(PrimaryButton, 'Crear cuenta'));

void main() {
  test('Registrar cuenta y Registro de Staff piden el mismo mínimo', () {
    expect(AuthRepository.minPasswordLength, 8);
    expect(
      StaffSignUpScreen.minPasswordLength,
      AuthRepository.minPasswordLength,
    );
  });

  testWidgets('Crear cuenta se habilita hasta que la contraseña tiene 8 '
      'caracteres', (tester) async {
    await _pumpSheet(tester);

    expect(
      find.textContaining('Mínimo 8 caracteres', findRichText: true),
      findsOneWidget,
    );

    // Familia (el tipo por omisión): nombre, dirección, correo y contraseña.
    await tester.enterText(find.byType(TextField).at(0), 'Familia Prueba');
    await tester.enterText(
      find.byType(TextField).at(1),
      'Calle 1, Guadalajara',
    );
    await tester.enterText(find.byType(TextField).at(2), 'prueba@bamx.test');
    await tester.enterText(find.byType(TextField).at(3), 'bamx123');
    await tester.pump();
    expect(_createButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField).at(3), 'bamx1234');
    await tester.pump();
    expect(_createButton(tester).onPressed, isNotNull);
  });
}
