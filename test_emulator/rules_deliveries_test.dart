// Pruebas de firestore.rules para las entregas (deliveries) y su reasignación,
// contra el emulador de Firestore (127.0.0.1:8080).
//
// Uso: flutter test test_emulator/rules_deliveries_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'support/emulator.dart';

// ---------------------------------------------------------------------------
// Datos de ejemplo (los mismos del suite de Node)
// ---------------------------------------------------------------------------

Map<String, Object?> now() => ts(DateTime.utc(2026, 9, 21, 12));

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

Map<String, Map<String, Object?>> pantryItem([
  Map<String, Map<String, Object?>> extra = const {},
]) => {
  'productId': str('Arroz'),
  'deliveryId': str('d1'),
  'type': str('grain'),
  'quantity': integer(2),
  'unit': str('kg'),
  'daysUntilExpiration': integer(30),
  'synchronized': boolean(true),
  'deviceId': str('dev'),
  'localTimestamp': now(),
  ...extra,
};

Map<String, Map<String, Object?>> get deliveryItem => {
  'productId': str('Arroz'),
  'type': str('grain'),
  'quantity': integer(2),
  'unit': str('kg'),
  'expirationDate': now(),
};

Map<String, Map<String, Object?>> delivery([
  Map<String, Map<String, Object?>> extra = const {},
]) => {
  'familyId': str('famA'),
  'familyName': str('Familia A'),
  'deliveryDate': now(),
  'packages': integer(1),
  'status': str('scheduled'),
  'items': arr([mapValue(deliveryItem)]),
  'createdAt': now(),
  ...extra,
};

// Sesiones usadas en estos grupos.
Db staff() => Db.user('staff1');
Db fam1() => Db.user('fam1');

/// Datos que existen antes de cada caso (el beforeEach del suite de Node, solo
/// con lo que necesitan estos grupos).
Future<void> seed() async {
  final db = Db.admin();
  await db.setDoc('users/staff1', profile('staff'));
  await db.setDoc('users/fam1', profile('family'));
  await db.setDoc('users/fam2', profile('family'));
  await db.setDoc('families/famA', family('Familia A', 'Calle 1', 'fam1'));
  await db.setDoc('families/famB', family('Familia B', 'Calle 2', 'fam2'));
  await db.setDoc('deliveries/del1', delivery());
}

void main() {
  useProject('demo-bamx-deliveries');

  setUpAll(requireEmulator);
  setUp(() async {
    await clearFirestore();
    await seed();
  });

  group('deliveries', () {
    test('staff registra entrega programada', () async {
      await assertAllowed(staff().setDoc('deliveries/new', delivery()));
    });

    test('staff registra entrega con cuota, justificación y notas', () async {
      await assertAllowed(
        staff().setDoc(
          'deliveries/new',
          delivery({
            'recoveryFee': integer(25),
            'justification': str('Nivel de ingreso'),
            'notes': str('Todo bien'),
            'status': str('delivered'),
          }),
        ),
      );
    });

    test('entrega sin productos rechazada', () async {
      await assertDenied(
        staff().setDoc('deliveries/new', delivery({'items': arr([])})),
      );
    });

    test('0 despensas rechazado', () async {
      await assertDenied(
        staff().setDoc('deliveries/new', delivery({'packages': integer(0)})),
      );
    });

    test('estado inválido rechazado', () async {
      await assertDenied(
        staff().setDoc('deliveries/new', delivery({'status': str('lost')})),
      );
    });

    test('familia inexistente rechazada', () async {
      await assertDenied(
        staff().setDoc(
          'deliveries/new',
          delivery({'familyId': str('noexiste')}),
        ),
      );
    });

    test('cuota negativa rechazada', () async {
      await assertDenied(
        staff().setDoc(
          'deliveries/new',
          delivery({'recoveryFee': integer(-1)}),
        ),
      );
    });

    test('familia no registra entregas', () async {
      await assertDenied(fam1().setDoc('deliveries/new', delivery()));
    });

    test('familia no lee entregas', () async {
      await assertDenied(fam1().getDoc('deliveries/del1'));
    });

    test('staff lista entregas recientes', () async {
      await assertAllowed(
        staff().listDocs('deliveries', orderBy: 'createdAt', limit: 50),
      );
    });

    test('staff marca como entregada', () async {
      await assertAllowed(
        staff().updateDoc('deliveries/del1', {'status': str('delivered')}),
      );
    });

    test('cambiar la familia de una entrega rechazado', () async {
      await assertDenied(
        staff().updateDoc('deliveries/del1', {'familyId': str('famB')}),
      );
    });

    test('no se puede marcar como entregada dos veces', () async {
      await assertAllowed(
        staff().updateDoc('deliveries/del1', {'status': str('delivered')}),
      );
      await assertDenied(
        staff().updateDoc('deliveries/del1', {'status': str('delivered')}),
      );
    });

    test('una entregada no regresa a programada', () async {
      await assertAllowed(
        staff().updateDoc('deliveries/del1', {'status': str('delivered')}),
      );
      await assertDenied(
        staff().updateDoc('deliveries/del1', {'status': str('scheduled')}),
      );
    });

    test('staff cancela una programada', () async {
      await assertAllowed(
        staff().updateDoc('deliveries/del1', {'status': str('cancelled')}),
      );
    });

    test('una cancelada no se entrega', () async {
      await assertAllowed(
        staff().updateDoc('deliveries/del1', {'status': str('cancelled')}),
      );
      await assertDenied(
        staff().updateDoc('deliveries/del1', {'status': str('delivered')}),
      );
    });

    test('al entregar no se cambian otros campos', () async {
      await assertDenied(
        staff().updateDoc('deliveries/del1', {
          'status': str('delivered'),
          'notes': str('x'),
        }),
      );
    });

    test('no se registra una entrega ya cancelada', () async {
      await assertDenied(
        staff().setDoc(
          'deliveries/new',
          delivery({'status': str('cancelled')}),
        ),
      );
    });

    test(
      'el staff no puede meter productos a la despensa junto con la entrega',
      () async {
        await assertDenied(
          staff().commit([
            setWrite('deliveries/d2', delivery({'status': str('delivered')})),
            setWrite(
              'families/famA/pantryItems/p9',
              pantryItem({'deliveryId': str('d2')}),
            ),
          ]),
        );
      },
    );

    test('ni al marcarla como entregada', () async {
      await assertDenied(
        staff().commit([
          updateWrite('deliveries/del1', {'status': str('delivered')}),
          setWrite(
            'families/famA/pantryItems/p8',
            pantryItem({'deliveryId': str('del1')}),
          ),
        ]),
      );
    });

    test(
      'el cliente no puede crear la entrega con la marca de la Cloud Function',
      () async {
        await assertDenied(
          staff().setDoc(
            'deliveries/new',
            delivery({'status': str('delivered'), 'pantryStockedAt': now()}),
          ),
        );
      },
    );

    test('ni ponerla al marcarla como entregada', () async {
      await assertDenied(
        staff().updateDoc('deliveries/del1', {
          'status': str('delivered'),
          'pantryStockedAt': now(),
        }),
      );
    });
  });

  group('reasignar entrega', () {
    // Batch de DeliveryRepository.reassignDelivery: la nueva para famB + la
    // original (del1, de famA) marcada como reasignada. Va en batch porque la
    // regla usa getAfter sobre las dos entregas.
    Future<int> reassign(
      Db db, {
      Map<String, Map<String, Object?>> next = const {},
      Map<String, Object?> original = const {},
    }) => db.commit([
      setWrite(
        'deliveries/re1',
        delivery({
          'familyId': str('famB'),
          'familyName': str('Familia B'),
          'reassignedFrom': str('del1'),
          ...next,
        }),
      ),
      updateWrite('deliveries/del1', {
        'status': str('reassigned'),
        'reassignedTo': str('re1'),
        ...original,
      }),
    ]);

    test('staff reasigna una programada a otra familia', () async {
      await assertAllowed(reassign(staff()));
    });

    test('la familia no puede reasignar', () async {
      await assertDenied(reassign(fam1()));
    });

    test('no se reasigna a la misma familia', () async {
      await assertDenied(
        reassign(
          staff(),
          next: {'familyId': str('famA'), 'familyName': str('Familia A')},
        ),
      );
    });

    test('la nueva debe quedar programada', () async {
      await assertDenied(reassign(staff(), next: {'status': str('delivered')}));
    });

    test('no se cambian los productos al reasignar', () async {
      await assertDenied(
        reassign(
          staff(),
          next: {
            'items': arr([
              mapValue({...deliveryItem, 'quantity': integer(99)}),
            ]),
          },
        ),
      );
    });

    test('no se cambian las despensas al reasignar', () async {
      await assertDenied(reassign(staff(), next: {'packages': integer(3)}));
    });

    test('la original no puede apuntar a otra entrega', () async {
      await assertDenied(
        reassign(staff(), original: {'reassignedTo': str('otra')}),
      );
    });

    test('no se marca como reasignada sin crear la nueva', () async {
      await assertDenied(
        staff().updateDoc('deliveries/del1', {
          'status': str('reassigned'),
          'reassignedTo': str('re1'),
        }),
      );
    });

    test(
      'no se crea una entrega "reasignada de" sin marcar la original',
      () async {
        await assertDenied(
          staff().setDoc(
            'deliveries/re1',
            delivery({'familyId': str('famB'), 'reassignedFrom': str('del1')}),
          ),
        );
      },
    );

    test('al reasignar no cambian otros campos de la original', () async {
      await assertDenied(reassign(staff(), original: {'notes': str('x')}));
    });

    test('una entregada no se reasigna', () async {
      await assertAllowed(
        staff().updateDoc('deliveries/del1', {'status': str('delivered')}),
      );
      await assertDenied(reassign(staff()));
    });

    test('una reasignada ya no cambia de estado', () async {
      await assertAllowed(reassign(staff()));
      await assertDenied(
        staff().updateDoc('deliveries/del1', {'status': str('delivered')}),
      );
    });

    test('la nueva se puede entregar después', () async {
      await assertAllowed(reassign(staff()));
      await assertAllowed(
        staff().updateDoc('deliveries/re1', {'status': str('delivered')}),
      );
    });
  });
}
