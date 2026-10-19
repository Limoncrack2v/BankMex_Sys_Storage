// Pruebas de firestore.rules para nutritionist contra el emulador de
// Firestore (127.0.0.1:8080).
//
// Uso: flutter test test_emulator/rules_nutritionist_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'support/emulator.dart';

/// Proyecto propio de este archivo, para que otros archivos de pruebas puedan
/// correr al mismo tiempo sin borrarse los datos entre ellos.
const _project = 'demo-bamx-nutritionist';

Map<String, Object?> now() => ts(DateTime.utc(2026, 10, 7, 12));

Map<String, Map<String, Object?>> profile(String role) => {
  'name': str('Nombre'),
  'email': str('x@y.com'),
  'role': str(role),
  'createdAt': now(),
};

Db staff() => Db.user('staff1');
Db fam1() => Db.user('fam1');
Db nutri1() => Db.user('nutri1');

const b = 'standardBaskets/despensa-basica';

void main() {
  useProject(_project);

  setUpAll(requireEmulator);

  setUp(() async {
    await clearFirestore();
    final admin = Db.admin();
    await admin.setDoc('users/staff1', profile('staff'));
    await admin.setDoc('users/fam1', profile('family'));
    await admin.setDoc(b, {'name': str('Despensa')});
    await admin.setDoc('users/nutri1', profile('nutritionist'));
    await admin.setDoc('families/famA', {'authUid': str('fam1')});
    await admin.setDoc('families/famA/members/m1', {'name': str('Ana')});
    await admin.setDoc('families/famA/pantryItems/p1', {'unit': str('kg')});
    await admin.setDoc('deliveries/d1', {'status': str('scheduled')});
    await admin.setDoc('staffRequests/nueva', {'status': str('pending')});
    await admin.setDoc('recipes/rPending', {'status': str('pending')});
  });

  group('recetas', () {
    test('nutriólogo lee recetas pendientes', () async {
      await assertAllowed(nutri1().getDoc('recipes/rPending'));
      await assertAllowed(
        nutri1().listDocs('recipes', where: ('status', str('pending'))),
      );
    });

    test('nutriólogo no lista recetas sin filtrar', () async {
      await assertDenied(nutri1().listDocs('recipes'));
    });

    // Aprobar y rechazar una pendiente (lo único que escribe, con sesión
    // reciente) se prueba en rules_recipes_test.dart.
    test(
      'nutriólogo no crea ni borra recetas ni aprueba sin sus datos',
      () async {
        await assertDenied(
          nutri1().setDoc('recipes/nueva', {'status': str('pending')}),
        );
        await assertDenied(
          nutri1().updateDoc('recipes/rPending', {'status': str('approved')}),
        );
        await assertDenied(nutri1().deleteDoc('recipes/rPending'));
      },
    );

    test('la rama nueva no cambia a familia ni a staff', () async {
      await assertDenied(fam1().getDoc('recipes/rPending'));
      await assertAllowed(staff().listDocs('recipes'));
    });
  });

  group('datos de otros roles', () {
    test('nutriólogo no lee hogares, integrantes ni despensa', () async {
      await assertDenied(nutri1().getDoc('families/famA'));
      await assertDenied(nutri1().getDoc('families/famA/members/m1'));
      await assertDenied(nutri1().getDoc('families/famA/pantryItems/p1'));
    });

    test('nutriólogo no lee entregas, solicitudes, despensas estándar ni perfiles ajenos', () async {
      await assertDenied(nutri1().getDoc('deliveries/d1'));
      await assertDenied(nutri1().getDoc('staffRequests/nueva'));
      await assertDenied(nutri1().getDoc(b));
      await assertDenied(nutri1().getDoc('users/staff1'));
    });
  });
}
