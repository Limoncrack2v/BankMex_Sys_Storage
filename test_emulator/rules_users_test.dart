// Pruebas de firestore.rules (colección users) contra el emulador de Firestore
// (127.0.0.1:8080). Portadas 1:1 de la suite de JavaScript.
//
// Uso: C:\src\flutter\bin\flutter.bat test test_emulator/rules_users_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'support/emulator.dart';

Map<String, Object?> now() => ts(DateTime.utc(2026, 9, 21, 12));

/// Perfil de users/{uid}; [extra] agrega o reemplaza campos.
Map<String, Map<String, Object?>> profile(
  String role, [
  Map<String, Map<String, Object?>> extra = const {},
]) => {
  'name': str('Nombre'),
  'email': str('x@y.com'),
  'role': str(role),
  'createdAt': now(),
  ...extra,
};

/// Los datos que la suite de JS prepara en cada beforeEach (solo los que
/// necesitan estos grupos), escritos saltándose las reglas.
Future<void> seedFixtures() async {
  final admin = Db.admin();
  await admin.setDoc('users/staff1', profile('staff'));
  await admin.setDoc('users/fam1', profile('family'));
  await admin.setDoc('users/fam2', profile('family'));
}

Db staff() => Db.user('staff1');
Db fam1() => Db.user('fam1');
Db newbie() => Db.user('newbie');
Db anon() => Db.anonymous();

void main() {
  useProject('demo-bamx-users');

  setUpAll(requireEmulator);
  setUp(() async {
    await clearFirestore();
    await seedFixtures();
  });

  group('users', () {
    test('nadie puede crearse a sí mismo como staff', () async {
      await assertDenied(newbie().setDoc('users/newbie', profile('staff')));
    });

    test('tampoco puede crearse su propio perfil de familia', () async {
      await assertDenied(newbie().setDoc('users/newbie', profile('family')));
    });

    test('staff crea perfil de familia para otra cuenta', () async {
      await assertAllowed(staff().setDoc('users/newbie', profile('family')));
    });

    test('staff crea perfil de staff para otra cuenta', () async {
      await assertAllowed(staff().setDoc('users/newbie', profile('staff')));
    });

    test('rol inválido rechazado', () async {
      await assertDenied(staff().setDoc('users/newbie', profile('admin')));
    });

    test('campo extra rechazado', () async {
      await assertDenied(
        staff().setDoc('users/newbie', profile('family', {'x': integer(1)})),
      );
    });

    test('familia no puede crear perfiles', () async {
      await assertDenied(fam1().setDoc('users/newbie', profile('family')));
    });

    test('cada quien lee su perfil', () async {
      await assertAllowed(fam1().getDoc('users/fam1'));
    });

    test('no se leen perfiles ajenos', () async {
      await assertDenied(fam1().getDoc('users/staff1'));
    });

    test('nadie puede borrar perfiles (ni el staff)', () async {
      await assertDenied(staff().deleteDoc('users/fam2'));
    });

    test('familia no puede borrar perfiles', () async {
      await assertDenied(fam1().deleteDoc('users/fam2'));
    });

    test('sin sesión no se lee nada', () async {
      await assertDenied(anon().getDoc('users/fam1'));
    });
  });

  group('registro de cuentas (registerAccount)', () {
    test('perfil de staff sin hogar', () async {
      await assertAllowed(staff().setDoc('users/newbie', profile('staff')));
    });
  });
}
