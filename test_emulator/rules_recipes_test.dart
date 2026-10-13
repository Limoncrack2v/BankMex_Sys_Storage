// Pruebas de firestore.rules (colección recipes) contra el emulador de
// Firestore (127.0.0.1:8080).
//
// Uso: flutter test test_emulator/rules_recipes_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'support/emulator.dart';

Map<String, Object?> now() => ts(DateTime.utc(2026, 9, 21, 12));

/// Perfil de users/{uid}.
Map<String, Map<String, Object?>> profile(String role) => {
  'name': str('Nombre'),
  'email': str('x@y.com'),
  'role': str(role),
  'createdAt': now(),
};

/// Las reglas no validan los campos de una receta: con estos dos alcanza.
Map<String, Map<String, Object?>> recipe(String status) => {
  'name': str('Arroz con frijoles'),
  'status': str(status),
};

Future<void> seedFixtures() async {
  final admin = Db.admin();
  await admin.setDoc('users/staff1', profile('staff'));
  await admin.setDoc('users/fam1', profile('family'));
}

// Publicar pide una sesión de menos de 5 minutos (recentlySignedIn en
// firestore.rules).
Db staleStaff() => Db.user('staff1', signedInAgo: const Duration(minutes: 6));
Db recentStaff() => Db.user('staff1', signedInAgo: const Duration(minutes: 4));
Db fam1() => Db.user('fam1');

void main() {
  useProject('demo-bamx-recipes');

  setUpAll(requireEmulator);
  setUp(() async {
    await clearFirestore();
    await seedFixtures();
  });

  group('recipes', () {
    test('staff con sesión vieja crea una receta pendiente', () async {
      await assertAllowed(staleStaff().setDoc('recipes/r1', recipe('pending')));
    });

    test('staff con sesión vieja no publica una pendiente', () async {
      await Db.admin().setDoc('recipes/r1', recipe('pending'));
      await assertDenied(
        staleStaff().updateDoc('recipes/r1', {'status': str('approved')}),
      );
    });

    test('staff reciente publica una pendiente', () async {
      await Db.admin().setDoc('recipes/r1', recipe('pending'));
      await assertAllowed(
        recentStaff().updateDoc('recipes/r1', {'status': str('approved')}),
      );
    });

    test('staff con sesión vieja no crea una receta publicada', () async {
      await assertDenied(staleStaff().setDoc('recipes/r1', recipe('approved')));
    });

    test('staff con sesión vieja no edita una publicada', () async {
      await Db.admin().setDoc('recipes/r1', recipe('approved'));
      await assertDenied(
        staleStaff().updateDoc('recipes/r1', {'name': str('Otro nombre')}),
      );
    });

    test('staff con sesión vieja la regresa a pendiente', () async {
      await Db.admin().setDoc('recipes/r1', recipe('approved'));
      await assertAllowed(
        staleStaff().updateDoc('recipes/r1', {'status': str('pending')}),
      );
    });

    test('staff con sesión vieja borra una receta', () async {
      await Db.admin().setDoc('recipes/r1', recipe('approved'));
      await assertAllowed(staleStaff().deleteDoc('recipes/r1'));
    });

    test('la familia lee solo las publicadas', () async {
      await Db.admin().setDoc('recipes/r1', recipe('approved'));
      await Db.admin().setDoc('recipes/r2', recipe('pending'));
      await assertAllowed(fam1().getDoc('recipes/r1'));
      await assertDenied(fam1().getDoc('recipes/r2'));
    });
  });
}
