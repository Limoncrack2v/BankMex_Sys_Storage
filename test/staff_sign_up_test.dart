import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/staff_request.dart';
import 'package:bank_storage_app/ui/screens/sign_in/sign_in_screen.dart';
import 'package:bank_storage_app/ui/screens/sign_in/staff_sign_up_screen.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:bank_storage_app/ui/widgets/app_buttons.dart';

Future<void> _pumpSignUp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.light, home: const SignInScreen()),
  );
  await tester.pumpAndSettle();

  final link = find.text('¿Eres personal de BAMX? Regístrate');
  await tester.ensureVisible(link);
  await tester.tap(link);
  await tester.pumpAndSettle();
}

Finder _field(int index) => find.byType(TextField).at(index);

Future<void> _submit(WidgetTester tester) async {
  final button = find.widgetWithText(PrimaryButton, 'Crear cuenta');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

const _errors = [
  'Escribe tu nombre completo',
  'Ingresa un correo válido',
  'La contraseña debe tener al menos 8 caracteres',
  'Las contraseñas no coinciden',
];

void main() {
  testWidgets('el link del Sign In abre Registro de Staff y regresa', (
    WidgetTester tester,
  ) async {
    await _pumpSignUp(tester);

    expect(find.byType(StaffSignUpScreen), findsOneWidget);
    expect(find.text('Registro de Staff'), findsOneWidget);
    for (final label in [
      'Nombre completo',
      'Correo institucional',
      'Contraseña',
      'Confirmar contraseña',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    // Solo cuentas de staff por ahora: sin selector de rol.
    expect(find.text('Nutriólogo'), findsNothing);

    await tester.tap(find.text('Volver a inicio de sesión'));
    await tester.pumpAndSettle();
    expect(find.byType(StaffSignUpScreen), findsNothing);
    expect(find.text('Inicia sesión en tu cuenta BAMX'), findsOneWidget);
  });

  testWidgets('los errores aparecen hasta el primer intento', (
    WidgetTester tester,
  ) async {
    await _pumpSignUp(tester);

    for (final error in _errors) {
      expect(find.text(error), findsNothing);
    }
    expect(
      tester
          .widget<PrimaryButton>(
            find.widgetWithText(PrimaryButton, 'Crear cuenta'),
          )
          .onPressed,
      isNotNull,
    );

    await _submit(tester);
    for (final error in _errors) {
      expect(find.text(error), findsOneWidget);
    }
  });

  testWidgets('cada error se quita al corregir su campo', (
    WidgetTester tester,
  ) async {
    await _pumpSignUp(tester);
    await _submit(tester);

    await tester.enterText(_field(0), 'Laura Méndez');
    await tester.enterText(_field(1), 'laura@bamx');
    await tester.enterText(_field(2), '1234567');
    await tester.enterText(_field(3), '1234567');
    await tester.pumpAndSettle();

    expect(find.text('Escribe tu nombre completo'), findsNothing);
    expect(find.text('Ingresa un correo válido'), findsOneWidget);
    expect(
      find.text('La contraseña debe tener al menos 8 caracteres'),
      findsOneWidget,
    );
    expect(find.text('Las contraseñas no coinciden'), findsNothing);

    await tester.enterText(_field(1), 'laura@bamx.org.mx');
    await tester.enterText(_field(2), '12345678');
    await tester.pumpAndSettle();

    expect(find.text('Ingresa un correo válido'), findsNothing);
    expect(
      find.text('La contraseña debe tener al menos 8 caracteres'),
      findsNothing,
    );
    expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
  });

  testWidgets('con datos válidos muestra el error si no se puede enviar', (
    WidgetTester tester,
  ) async {
    await _pumpSignUp(tester);

    await tester.enterText(_field(0), 'Laura Méndez');
    await tester.enterText(_field(1), 'laura@bamx.org.mx');
    await tester.enterText(_field(2), '12345678');
    await tester.enterText(_field(3), '12345678');
    await tester.pump();
    await _submit(tester);

    for (final error in _errors) {
      expect(find.text(error), findsNothing);
    }
    // Sin Firebase la solicitud falla y la pantalla se queda en el registro.
    expect(
      find.text('No se pudo enviar tu solicitud. Intenta de nuevo.'),
      findsOneWidget,
    );
    expect(find.text('Solicitud enviada'), findsNothing);
  });

  test('StaffRequest.toFirestore escribe solo los campos de la solicitud', () {
    final data = StaffRequest(
      uid: 'uid-1',
      name: '  Laura Méndez ',
      email: 'laura@bamx.org.mx',
      status: StaffRequestStatus.pending,
      createdAt: DateTime(2026, 9, 21),
      reviewedBy: 'staff-1',
    ).toFirestore();

    expect(data.keys.toSet(), {'name', 'email', 'status', 'createdAt'});
    expect(data['name'], 'Laura Méndez');
    expect(data['status'], 'pending');
    expect(data['createdAt'], isA<Timestamp>());
  });

  test('los estados coinciden con los que aceptan las reglas', () {
    expect(StaffRequestStatus.values.map((e) => e.name), [
      'pending',
      'approved',
      'rejected',
    ]);
  });
}
