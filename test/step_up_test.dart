import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/repositories/auth_repository.dart';

void main() {
  final now = DateTime.utc(2026, 10, 12, 12);
  bool recent(DateTime? authTime) =>
      AuthRepository.isRecentSignIn(authTime, now: now);

  test('la ventana de la app es de 4 minutos', () {
    expect(AuthRepository.stepUpWindow, const Duration(minutes: 4));
  });

  test('sin auth_time no es reciente', () {
    expect(recent(null), isFalse);
  });

  test('hace 3 min 59 s es reciente', () {
    expect(
      recent(now.subtract(const Duration(minutes: 3, seconds: 59))),
      isTrue,
    );
  });

  test('hace exactamente 4 minutos ya no es reciente', () {
    expect(recent(now.subtract(const Duration(minutes: 4))), isFalse);
  });

  test('hace 1 hora no es reciente', () {
    expect(recent(now.subtract(const Duration(hours: 1))), isFalse);
  });

  test('30 s en el futuro (reloj atrasado) cuenta como reciente', () {
    expect(recent(now.add(const Duration(seconds: 30))), isTrue);
  });
}
