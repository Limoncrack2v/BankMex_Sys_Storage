// Pruebas de firestore.rules para families/{familyId}/pantryItems contra el
// emulador de Firestore (127.0.0.1:8080).
//
// Port 1:1 del grupo describe('pantryItems (solo la Cloud Function los crea)')
// de rules.test.mjs: mismos nombres, mismas aserciones y en el mismo orden.
//
// Uso: flutter test test_emulator/rules_pantry_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'support/emulator.dart';

/// Proyecto propio de este archivo, para que otros archivos de pruebas puedan
/// correr al mismo tiempo sin borrarse los datos entre ellos.
const _project = 'demo-bamx-pantry';

Map<String, Object?> now() => ts(DateTime.utc(2026, 9, 21, 12));

// ---------------------------------------------------------------------------
// Constructores de documentos (los mismos valores por omisión que en JS; el
// mapa [extra] reemplaza campos, como el spread `...extra`).
// ---------------------------------------------------------------------------

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

Map<String, Map<String, Object?>> pantryItem([
  Map<String, Map<String, Object?>> extra = const {},
]) => {
  'productId': str('Arroz'),
  'deliveryId': str('d1'),
  'type': str('grain'),
  'quantity': integer(2),
  'unit': str('kg'),
  'daysUntilExpiration': integer(30),
  'deviceId': str('dev'),
  'localTimestamp': now(),
  ...extra,
};

Map<String, Map<String, Object?>> family(
  String name,
  String address,
  String authUid,
) => {
  'name': str(name),
  'address': str(address),
  'registrationDate': now(),
  'recoveryQuotaDefault': nul(),
  'authUid': str(authUid),
  'appliances': arr([]),
};

// Sesiones, como en el JS.
Db staff() => Db.user('staff1');
Db fam1() => Db.user('fam1');
Db fam2() => Db.user('fam2');

/// El producto que ya está en la despensa.
const p = 'families/famA/pantryItems/p1';

/// Un producto que todavía no existe (para los intentos de creación).
const nuevo = 'families/famA/pantryItems/p2';

void main() {
  useProject(_project);

  setUpAll(requireEmulator);

  setUp(() async {
    await clearFirestore();
    final admin = Db.admin();
    await admin.setDoc('users/staff1', profile('staff'));
    await admin.setDoc('users/fam1', profile('family'));
    // users/fam2 existe para que el rechazo venga de la regla (no es staff ni
    // dueña de famA) y no de un get() sobre un documento inexistente.
    await admin.setDoc('users/fam2', profile('family'));
    await admin.setDoc('families/famA', family('Familia A', 'Calle 1', 'fam1'));
    await admin.setDoc(p, pantryItem());
  });

  group('pantryItems (solo la Cloud Function los crea)', () {
    test('staff no crea productos en la despensa', () async {
      await assertDenied(staff().setDoc(nuevo, pantryItem()));
    });

    test('la familia no crea productos en su despensa', () async {
      await assertDenied(fam1().setDoc(nuevo, pantryItem()));
    });

    test('staff no crea productos con addDoc', () async {
      // Con id automático, la otra vía del cliente para crear.
      await assertDenied(
        staff().addDoc('families/famA/pantryItems', pantryItem()),
      );
    });

    test(
      'set sobre un producto existente tampoco sirve para reemplazarlo',
      () async {
        await assertDenied(
          staff().setDoc(p, pantryItem({'quantity': integer(50)})),
        );
      },
    );

    test('la familia lee su despensa', () async {
      await assertAllowed(
        fam1().listDocs('pantryItems', parent: 'families/famA'),
      );
    });

    test('otra familia no lee la despensa', () async {
      await assertDenied(
        fam2().listDocs('pantryItems', parent: 'families/famA'),
      );
    });

    test('familia descuenta consumo', () async {
      await assertAllowed(fam1().updateDoc(p, {'quantity': number(1.5)}));
    });

    test('familia descuenta con increment (registerConsumption)', () async {
      await assertAllowed(
        fam1().updateDoc(p, {'quantity': const Increment(-0.5)}),
      );
    });

    test('increment que deja 0 rechazado (debe borrarse)', () async {
      // 2 - 2 = 0, y la regla pide quantity > 0: el producto agotado se borra.
      await assertDenied(
        fam1().updateDoc(p, {'quantity': const Increment(-2)}),
      );
    });

    test('cantidad 0 rechazada (debe borrarse)', () async {
      await assertDenied(fam1().updateDoc(p, {'quantity': integer(0)}));
    });

    test('no se puede aumentar la cantidad', () async {
      await assertDenied(fam1().updateDoc(p, {'quantity': integer(5)}));
    });

    test('increment positivo rechazado', () async {
      await assertDenied(
        staff().updateDoc(p, {'quantity': const Increment(1)}),
      );
    });

    test('al consumir no cambian otros campos', () async {
      await assertDenied(
        fam1().updateDoc(p, {
          'quantity': integer(1),
          'daysUntilExpiration': integer(90),
        }),
      );
    });

    test('no se cambia la caducidad sola', () async {
      await assertDenied(
        staff().updateDoc(p, {'daysUntilExpiration': integer(90)}),
      );
    });

    test('cantidad como texto rechazada', () async {
      await assertDenied(fam1().updateDoc(p, {'quantity': str('1')}));
    });

    test('familia borra producto agotado', () async {
      await assertAllowed(fam1().deleteDoc(p));
    });

    test('staff corrige consumo (baja cantidad)', () async {
      await assertAllowed(staff().updateDoc(p, {'quantity': integer(1)}));
    });

    test('otra familia no puede consumir', () async {
      await assertDenied(fam2().updateDoc(p, {'quantity': integer(1)}));
    });

    test('otra familia no puede borrar', () async {
      await assertDenied(fam2().deleteDoc(p));
    });

    test('batch de consumo (update + delete)', () async {
      await Db.admin().setDoc(
        'families/famA/pantryItems/p3',
        pantryItem({'quantity': integer(1)}),
      );
      // Un solo batch con las dos escrituras, como writeBatch en JS.
      await assertAllowed(
        fam1().commit([
          updateWrite(p, {'quantity': number(0.5)}),
          deleteWrite('families/famA/pantryItems/p3'),
        ]),
      );
    });
  });
}
