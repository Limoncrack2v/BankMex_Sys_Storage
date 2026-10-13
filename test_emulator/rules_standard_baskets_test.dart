// Pruebas de firestore.rules para standardBaskets contra el emulador de
// Firestore (127.0.0.1:8080).
//
// Uso: flutter test test_emulator/rules_standard_baskets_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'support/emulator.dart';

/// Proyecto propio de este archivo, para que otros archivos de pruebas puedan
/// correr al mismo tiempo sin borrarse los datos entre ellos.
const _project = 'demo-bamx-standard-baskets';

Map<String, Object?> now() => ts(DateTime.utc(2026, 10, 7, 12));

Map<String, Map<String, Object?>> profile(String role) => {
  'name': str('Nombre'),
  'email': str('x@y.com'),
  'role': str(role),
  'createdAt': now(),
};

Map<String, Map<String, Object?>> basket() => {
  'name': str('Despensa básica'),
  'description': str('Abarrotes'),
  'items': arr([
    mapValue({
      'productId': str('Arroz'),
      'type': str('grain'),
      'quantity': number(1),
      'unit': str('kg'),
      'shelfLifeDays': integer(365),
    }),
  ]),
  'updatedAt': now(),
};

Db staff() => Db.user('staff1');
Db fam1() => Db.user('fam1');

const b = 'standardBaskets/despensa-basica';

void main() {
  useProject(_project);

  setUpAll(requireEmulator);

  setUp(() async {
    await clearFirestore();
    final admin = Db.admin();
    await admin.setDoc('users/staff1', profile('staff'));
    await admin.setDoc('users/fam1', profile('family'));
    await admin.setDoc(b, basket());
  });

  group('standardBaskets', () {
    test('staff lee una despensa', () async {
      await assertAllowed(staff().getDoc(b));
    });

    test('staff lista las despensas', () async {
      await assertAllowed(staff().listDocs('standardBaskets'));
    });

    test('la familia no lee las despensas', () async {
      await assertDenied(fam1().getDoc(b));
    });

    test('sin sesión no se leen', () async {
      await assertDenied(Db.anonymous().getDoc(b));
    });

    test('staff no crea despensas', () async {
      await assertDenied(staff().setDoc('standardBaskets/nueva', basket()));
    });

    test('staff no cambia una despensa', () async {
      await assertDenied(staff().updateDoc(b, {'name': str('Otra')}));
    });

    test('staff no borra una despensa', () async {
      await assertDenied(staff().deleteDoc(b));
    });
  });
}
