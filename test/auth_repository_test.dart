import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/app_user.dart';
import 'package:bank_storage_app/data/plan_reminder.dart';
import 'package:bank_storage_app/data/repositories/auth_repository.dart';

import 'helpers/fake_reminder_scheduler.dart';

const _weakPassword = 'La contraseña debe tener al menos 8 caracteres.';

/// La excepción de contraseña corta, con su mensaje.
final _weakPasswordError = throwsA(
  isA<AuthException>().having((e) => e.message, 'message', _weakPassword),
);

void main() {
  test('el mínimo para contraseñas nuevas es 8', () {
    expect(AuthRepository.minPasswordLength, 8);
  });

  // Sin Firebase en estas pruebas: una contraseña corta debe rechazarse antes
  // de llegar a Firebase; con 8 caracteres la validación pasa y lo siguiente
  // (Firebase) es lo que falla.
  group('Registro de Staff', () {
    Future<void> request(String password) =>
        AuthRepository().requestStaffAccount(
          name: 'Ana López',
          email: 'ana@bamx.test',
          password: password,
        );

    test('rechaza una contraseña de 7 caracteres', () async {
      await expectLater(request('bamx123'), _weakPasswordError);
    });

    test('acepta 8 caracteres', () async {
      await expectLater(
        request('bamx1234'),
        throwsA(isNot(isA<AuthException>())),
      );
    });
  });

  group('Registrar cuenta', () {
    Future<void> register(String password) => AuthRepository().registerAccount(
      role: AppUser.roleFamily,
      name: 'Familia Prueba',
      email: 'familia@bamx.test',
      password: password,
      address: 'Calle 1, Guadalajara',
    );

    test('rechaza una contraseña de 7 caracteres', () async {
      await expectLater(register('bamx123'), _weakPasswordError);
    });

    test('acepta 8 caracteres', () async {
      await expectLater(
        register('bamx1234'),
        throwsA(isNot(isA<AuthException>())),
      );
    });
  });

  // Sin Firebase en estas pruebas, cerrar la sesión de Firebase falla: si se
  // llega a ese paso, el recordatorio ya se canceló.
  test('cerrar sesión cancela primero el recordatorio del plan', () async {
    final scheduler = FakeReminderScheduler()..cancelGate = Completer<void>();
    final repository = AuthRepository(
      planReminder: PlanReminder(scheduler: scheduler, isWeb: false),
    );

    Object? firebaseError;
    final signOut = repository.signOut().catchError((Object error) {
      firebaseError = error;
    });
    await pumpEventQueue();
    // Mientras el teléfono cancela, todavía no toca Firebase.
    expect(scheduler.calls, ['cancel']);
    expect(firebaseError, isNull);

    scheduler.cancelGate!.complete();
    await signOut;
    expect(firebaseError, isNotNull);
  });
}
