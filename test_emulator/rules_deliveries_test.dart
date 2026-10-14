// Pruebas de firestore.rules para las entregas (deliveries) y su reasignación,
// contra el emulador de Firestore (127.0.0.1:8080).
//
// Uso: flutter test test_emulator/rules_deliveries_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/delivery.dart';

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
  'deviceId': str('dev-1'),
  'localTimestamp': now(),
  ...extra,
};

/// Estampa nueva para actualización:
/// la regla exige que localTimestamp cambie;
/// no usar now(), que es la fecha fija con la que se creó del1.
Map<String, Object?> restamp() => {'localTimestamp': ts(DateTime.now())};

// Sesiones usadas en estos grupos.
Db staff() => Db.user('staff1');
// Cancelar y reasignar piden una sesión de menos de 5 minutos
// (recentlySignedIn en firestore.rules); marcar como entregada no.
Db staleStaff() => Db.user('staff1', signedInAgo: const Duration(minutes: 6));
Db recentStaff() => Db.user('staff1', signedInAgo: const Duration(minutes: 4));
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
          delivery({
            'recoveryFee': integer(-1),
            'justification': str('Nivel de ingreso'),
          }),
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
        staff().updateDoc('deliveries/del1', {
          'status': str('delivered'),
          ...restamp(),
        }),
      );
    });

    // La entrega se hace sin conexión: la escritura puede sincronizarse mucho
    // después de iniciar sesión, y si se rechazara no se llenaría la despensa.
    test('staff con sesión vieja sí marca como entregada', () async {
      await assertAllowed(
        staleStaff().updateDoc('deliveries/del1', {
          'status': str('delivered'),
          ...restamp(),
        }),
      );
    });

    test('cambiar la familia de una entrega rechazado', () async {
      await assertDenied(
        staff().updateDoc('deliveries/del1', {
          'familyId': str('famB'),
          ...restamp(),
        }),
      );
    });

    test('no se puede marcar como entregada dos veces', () async {
      await assertAllowed(
        staff().updateDoc('deliveries/del1', {
          'status': str('delivered'),
          ...restamp(),
        }),
      );
      await assertDenied(
        staff().updateDoc('deliveries/del1', {
          'status': str('delivered'),
          ...restamp(),
        }),
      );
    });

    test('una entregada no regresa a programada', () async {
      await assertAllowed(
        staff().updateDoc('deliveries/del1', {
          'status': str('delivered'),
          ...restamp(),
        }),
      );
      await assertDenied(
        staff().updateDoc('deliveries/del1', {
          'status': str('scheduled'),
          ...restamp(),
        }),
      );
    });

    test('staff cancela una programada', () async {
      await assertAllowed(
        staff().updateDoc('deliveries/del1', {
          'status': str('cancelled'),
          ...restamp(),
        }),
      );
    });

    test('staff con sesión vieja no cancela', () async {
      await assertDenied(
        staleStaff().updateDoc('deliveries/del1', {
          'status': str('cancelled'),
          ...restamp(),
        }),
      );
    });

    test('una cancelada no se entrega', () async {
      await assertAllowed(
        staff().updateDoc('deliveries/del1', {
          'status': str('cancelled'),
          ...restamp(),
        }),
      );
      await assertDenied(
        staff().updateDoc('deliveries/del1', {
          'status': str('delivered'),
          ...restamp(),
        }),
      );
    });

    test('al entregar no se cambian otros campos', () async {
      await assertDenied(
        staff().updateDoc('deliveries/del1', {
          'status': str('delivered'),
          'notes': str('x'),
          ...restamp(),
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
          updateWrite('deliveries/del1', {
            'status': str('delivered'),
            ...restamp(),
          }),
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
          ...restamp(),
        }),
      );
    });
  });

  group('productos de la entrega', () {
    const maxItems = Delivery.maxItems;

    // Una entrega con [count] productos válidos.
    Map<String, Map<String, Object?>> withItems(
      int count, [
      Map<String, Map<String, Object?>> extra = const {},
    ]) => delivery({
      'items': arr([for (var i = 0; i < count; i++) mapValue(deliveryItem)]),
      ...extra,
    });

    // Una entrega con un solo producto, el de prueba con [changes].
    Map<String, Map<String, Object?>> withItem(
      Map<String, Map<String, Object?>> changes,
    ) => delivery({
      'items': arr([
        mapValue({...deliveryItem, ...changes}),
      ]),
    });

    // Una entrega de [Delivery.maxItems] productos donde solo el que está en
    // [index] cambia.
    Map<String, Map<String, Object?>> withBadItemAt(
      int index,
      Map<String, Map<String, Object?>> changes,
    ) => delivery({
      'items': arr([
        for (var i = 0; i < maxItems; i++)
          mapValue(i == index ? {...deliveryItem, ...changes} : deliveryItem),
      ]),
    });

    Future<void> denied(Map<String, Map<String, Object?>> data) =>
        assertDenied(staff().setDoc('deliveries/new', data));

    test('un producto con todos los campos válidos', () async {
      await assertAllowed(
        staff().setDoc('deliveries/new', withItem({'quantity': number(0.5)})),
      );
    });

    test('cada tipo de alimento, uno por producto', () async {
      const types = [
        'grain',
        'legume',
        'canned',
        'dairy',
        'produce',
        'protein',
        'beverage',
        'other',
      ];
      await assertAllowed(
        staff().setDoc(
          'deliveries/new',
          delivery({
            'items': arr([
              for (final type in types)
                mapValue({...deliveryItem, 'type': str(type)}),
            ]),
          }),
        ),
      );
    });

    test('cada unidad, una por producto', () async {
      const units = ['kg', 'g', 'l', 'ml', 'piece', 'can', 'pack'];
      await assertAllowed(
        staff().setDoc(
          'deliveries/new',
          delivery({
            'items': arr([
              for (final unit in units)
                mapValue({...deliveryItem, 'unit': str(unit)}),
            ]),
          }),
        ),
      );
    });

    test('cantidad en el límite (1,000,000) y nombre de 100 caracteres', () async {
      await assertAllowed(
        staff().setDoc(
          'deliveries/new',
          withItem({
            'quantity': integer(1000000),
            'productId': str('a' * 100),
          }),
        ),
      );
    });

    test('tipo desconocido rechazado', () async {
      await denied(withItem({'type': str('gold')}));
    });

    test('el tipo distingue mayúsculas y no acepta texto de más', () async {
      await denied(withItem({'type': str('Grain')}));
      await denied(withItem({'type': str('grains')}));
      await denied(withItem({'type': str('')}));
    });

    test('tipo y unidad no se pueden repartir el separador', () async {
      await denied(withItem({'type': str('grain/kg'), 'unit': str('')}));
      await denied(withItem({'type': str('grain/'), 'unit': str('/kg')}));
    });

    test('tipo que no es texto rechazado', () async {
      await denied(withItem({'type': integer(1)}));
    });

    test('unidad desconocida rechazada', () async {
      await denied(withItem({'unit': str('lb')}));
    });

    test('unidad que no es texto o falta rechazada', () async {
      await denied(withItem({'unit': integer(1)}));
      await denied(
        delivery({
          'items': arr([mapValue({...deliveryItem}..remove('unit'))]),
        }),
      );
    });

    test('cantidad 0 rechazada', () async {
      await denied(withItem({'quantity': integer(0)}));
    });

    test('cantidad negativa rechazada', () async {
      await denied(withItem({'quantity': integer(-1)}));
      await denied(withItem({'quantity': number(-0.5)}));
    });

    // El tope de la cantidad no cabe en el presupuesto de expresiones de las
    // reglas (ver validDeliveryItem): lo aplican DeliveryItem.validate y
    // invalidReason en functions/pantry.js, que no agrega el producto a la
    // despensa.
    test('cantidad mayor a 1,000,000 aceptada: el tope no está en las reglas', () async {
      await assertAllowed(
        staff().setDoc('deliveries/new', withItem({'quantity': integer(1000001)})),
      );
    });

    test('cantidad que no es número o falta rechazada', () async {
      await denied(withItem({'quantity': str('2')}));
      await denied(withItem({'quantity': boolean(true)}));
      await denied(withItem({'quantity': ts(DateTime.utc(2026))}));
      await denied(
        delivery({
          'items': arr([mapValue({...deliveryItem}..remove('quantity'))]),
        }),
      );
    });

    test('sin expirationDate rechazado', () async {
      await denied(
        delivery({
          'items': arr([mapValue({...deliveryItem}..remove('expirationDate'))]),
        }),
      );
    });

    test('expirationDate que no es fecha rechazado', () async {
      await denied(withItem({'expirationDate': str('2026-10-01')}));
      await denied(withItem({'expirationDate': integer(20261001)}));
    });

    test('nombre vacío, de más de 100 caracteres o sin texto rechazado', () async {
      await denied(withItem({'productId': str('')}));
      await denied(withItem({'productId': str('a' * 101)}));
      await denied(withItem({'productId': integer(7)}));
      await denied(
        delivery({
          'items': arr([mapValue({...deliveryItem}..remove('productId'))]),
        }),
      );
    });

    test('producto que no es un mapa rechazado', () async {
      await denied(delivery({'items': arr([str('Arroz')])}));
      await denied(delivery({'items': arr([integer(1)])}));
    });

    test('lista de productos que no es lista rechazada', () async {
      await denied(delivery({'items': str('Arroz')}));
      await denied(delivery({'items': mapValue(deliveryItem)}));
    });

    group('cantidad máxima de productos', () {
      test('$maxItems productos, con todos los campos opcionales', () async {
        await assertAllowed(
          staff().setDoc(
            'deliveries/new',
            withItems(maxItems, {
              'recoveryFee': integer(25),
              'justification': str('Nivel de ingreso'),
              'notes': str('Todo bien'),
              'status': str('delivered'),
            }),
          ),
        );
      });

      test('${maxItems + 1} productos válidos rechazados', () async {
        await denied(withItems(maxItems + 1));
      });

      test('100 productos válidos rechazados', () async {
        await denied(withItems(100));
      });

      test('uno inválido al inicio de $maxItems rechazado', () async {
        await denied(withBadItemAt(0, {'quantity': integer(0)}));
      });

      test('uno inválido en medio de $maxItems rechazado', () async {
        await denied(withBadItemAt(8, {'type': str('gold')}));
      });

      test('uno inválido al final de $maxItems rechazado', () async {
        await denied(withBadItemAt(maxItems - 1, {'unit': str('lb')}));
      });

      test('el último producto de $maxItems se revisa por cada campo', () async {
        final last = maxItems - 1;
        await denied(withBadItemAt(last, {'quantity': integer(0)}));
        await denied(withBadItemAt(last, {'productId': str('a' * 101)}));
        await denied(withBadItemAt(last, {'expirationDate': str('x')}));
      });
    });

    group('una entrega que ya existe', () {
      // Entregas de antes de las reglas nuevas: validDelivery solo corre al
      // crear, así que cambiar su estado sigue siendo posible aunque tengan
      // más productos que el máximo de ahora.
      Future<void> seedLegacy({
        int count = 100,
        Map<String, Map<String, Object?>> item = const {},
      }) => Db.admin().setDoc(
        'deliveries/del1',
        delivery({
          'items': arr([
            for (var i = 0; i < count; i++)
              mapValue({...deliveryItem, ...item}),
          ]),
        }),
      );

      test('con 100 productos se puede marcar como entregada', () async {
        await seedLegacy();
        await assertAllowed(
          staff().updateDoc('deliveries/del1', {
            'status': str('delivered'),
            ...restamp(),
          }),
        );
      });

      test('con 100 productos se puede cancelar', () async {
        await seedLegacy();
        await assertAllowed(
          staff().updateDoc('deliveries/del1', {
            'status': str('cancelled'),
            ...restamp(),
          }),
        );
      });

      test('con un producto inválido se puede cancelar', () async {
        await seedLegacy(count: 2, item: {'type': str('gold')});
        await assertAllowed(
          staff().updateDoc('deliveries/del1', {
            'status': str('cancelled'),
            ...restamp(),
          }),
        );
      });
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
        ...restamp(),
        ...original,
      }),
    ]);

    test('staff reasigna una programada a otra familia', () async {
      await assertAllowed(reassign(staff()));
    });

    test('staff con sesión vieja no reasigna', () async {
      await assertDenied(reassign(staleStaff()));
    });

    test('staff reciente cancela y reasigna', () async {
      await assertAllowed(
        recentStaff().updateDoc('deliveries/del1', {
          'status': str('cancelled'),
          ...restamp(),
        }),
      );
      // del1 vuelve a quedar programada para poder reasignarla.
      await clearFirestore();
      await seed();
      await assertAllowed(reassign(recentStaff()));
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
          ...restamp(),
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
        staff().updateDoc('deliveries/del1', {
          'status': str('delivered'),
          ...restamp(),
        }),
      );
      await assertDenied(reassign(staff()));
    });

    test('una reasignada ya no cambia de estado', () async {
      await assertAllowed(reassign(staff()));
      await assertDenied(
        staff().updateDoc('deliveries/del1', {
          'status': str('delivered'),
          ...restamp(),
        }),
      );
    });

    // La entrega nueva pasa por validDelivery como cualquier otra: copiar los
    // productos de la original no la exime.
    Map<String, Map<String, Object?>> itemsOf(int count) => {
      'items': arr([for (var i = 0; i < count; i++) mapValue(deliveryItem)]),
    };

    test('se reasigna una entrega con el máximo de productos', () async {
      final items = itemsOf(Delivery.maxItems);
      await Db.admin().setDoc('deliveries/del1', delivery(items));
      await assertAllowed(reassign(staff(), next: items));
    });

    test('se reasigna el máximo con cuota y justificación', () async {
      final items = {
        ...itemsOf(Delivery.maxItems),
        'recoveryFee': integer(250),
        'justification': str('Nivel de ingreso'),
      };
      await Db.admin().setDoc('deliveries/del1', delivery(items));
      await assertAllowed(reassign(staff(), next: items));
    });

    test('no se reasigna una entrega con más del máximo de productos', () async {
      final items = itemsOf(Delivery.maxItems + 1);
      await Db.admin().setDoc('deliveries/del1', delivery(items));
      await assertDenied(reassign(staff(), next: items));
    });

    test('no se reasigna una entrega con un producto inválido', () async {
      final items = {
        'items': arr([
          mapValue(deliveryItem),
          mapValue({...deliveryItem, 'type': str('gold')}),
        ]),
      };
      await Db.admin().setDoc('deliveries/del1', delivery(items));
      await assertDenied(reassign(staff(), next: items));
    });

    test('la nueva se puede entregar después', () async {
      await assertAllowed(reassign(staff()));
      await assertAllowed(
        staff().updateDoc('deliveries/re1', {
          'status': str('delivered'),
          ...restamp(),
        }),
      );
    });

    // La entrega nueva copia la cuota y la justificación de la original
    // (DeliveryRepository.reassignDelivery) y pasa por validDelivery.
    test('se reasigna una entrega con cuota y justificación', () async {
      final quota = {
        'recoveryFee': integer(250),
        'justification': str('Cuota estándar'),
      };
      await Db.admin().setDoc('deliveries/del1', delivery(quota));
      await assertAllowed(reassign(staff(), next: quota));
    });

    test('una con cuota sin justificación no se reasigna', () async {
      final quota = {'recoveryFee': integer(250)};
      await Db.admin().setDoc('deliveries/del1', delivery(quota));
      await assertDenied(reassign(staff(), next: quota));
    });
  });

  group('trazabilidad offline', () {
    test('staff registra entrega con deviceId y localTimestamp', () async {
      await assertAllowed(
        staff().setDoc(
          'deliveries/new',
          delivery({'deviceId': str('abc123'), 'localTimestamp': now()}),
        ),
      );
    });

    test('deviceId que no es texto rechazado', () async {
      await assertDenied(
        staff().setDoc('deliveries/new', delivery({'deviceId': integer(5)})),
      );
    });

    test('staff marca como entregada con trazabilidad', () async {
      await assertAllowed(
        staff().updateDoc('deliveries/del1', {
          'status': str('delivered'),
          'deviceId': str('abc123'),
          'localTimestamp': ts(DateTime.now()),
        }),
      );
    });

    test('al entregar, deviceId inválido rechazado', () async {
      await assertDenied(
        staff().updateDoc('deliveries/del1', {
          'status': str('delivered'),
          'deviceId': integer(5),
          ...restamp(),
        }),
      );
    });

    test('entrega sin deviceId rechazada', () async {
      await assertDenied(
        staff().setDoc('deliveries/new', delivery()..remove('deviceId')),
      );
    });

    test('entrega sin localTimestamp rechazada', () async {
      await assertDenied(
        staff().setDoc('deliveries/new', delivery()..remove('localTimestamp')),
      );
    });

    test('al entregar sin estampa rechazado', () async {
      await assertDenied(
        staff().updateDoc('deliveries/del1', {'status': str('delivered')}),
      );
    });

    test('al entregar con el mismo localTimestamp rechazado', () async {
      await assertDenied(
        staff().updateDoc('deliveries/del1', {
          'status': str('delivered'),
          'localTimestamp': now(),
        }),
      );
    });
  });

  group('cuota de recuperación', () {
    test('cuota con justificación permitida', () async {
      await assertAllowed(
        staff().setDoc(
          'deliveries/new',
          delivery({
            'recoveryFee': integer(250),
            'justification': str('Cuota estándar'),
          }),
        ),
      );
    });

    test('cuota sin justificación rechazada', () async {
      await assertDenied(
        staff().setDoc(
          'deliveries/new',
          delivery({'recoveryFee': integer(250)}),
        ),
      );
    });

    test('cuota con justificación en blanco rechazada', () async {
      await assertDenied(
        staff().setDoc(
          'deliveries/new',
          delivery({'recoveryFee': integer(250), 'justification': str('   ')}),
        ),
      );
    });

    test('cuota en cero también pide justificación', () async {
      await assertDenied(
        staff().setDoc('deliveries/new', delivery({'recoveryFee': integer(0)})),
      );
    });

    test('exenta no pide justificación', () async {
      await assertAllowed(staff().setDoc('deliveries/new', delivery()));
    });
  });
}
