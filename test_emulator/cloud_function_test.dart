// Prueba la Cloud Function onDeliveryWritten (functions/index.js) contra los
// emuladores: al quedar una entrega como entregada, sus productos deben
// aparecer en la despensa de la familia.
//
// Corre en el proyecto real del emulador (bank-storage-bamx) porque el
// emulador de Functions solo escucha ese proyecto; por eso NO borra la base,
// usa ids propios de cada corrida y limpia lo suyo al terminar.
//
// Requisitos: firebase emulators:start --only auth,firestore,functions --import=exported-dev-data --export-on-exit=exported-dev-data
import 'package:flutter_test/flutter_test.dart';

import 'support/emulator.dart';

const _day = Duration(days: 1);
final _run = 'fn-${DateTime.now().millisecondsSinceEpoch}';
final _familyId = '$_run-familia';
final _created = <String>[];

Map<String, Object?> _item(
  String productId,
  int days, {
  String type = 'grain',
  num quantity = 2,
  String unit = 'kg',
}) => mapValue({
  'productId': str(productId),
  'type': str(type),
  'quantity': number(quantity),
  'unit': str(unit),
  'expirationDate': ts(DateTime.now().add(_day * days)),
});

Future<void> _writeDelivery(
  String id,
  String status,
  List<Map<String, Object?>> items, {
  String? deviceId,
  DateTime? localTimestamp,
}) async {
  _created.add(id);
  await assertAllowed(
    Db.admin().setDoc('deliveries/$id', {
      'familyId': str(_familyId),
      'familyName': str('Familia Emulador'),
      'deliveryDate': ts(DateTime.now()),
      'packages': integer(1),
      'status': str(status),
      'items': arr(items),
      'createdAt': ts(DateTime.now()),
      if (deviceId != null) 'deviceId': str(deviceId),
      if (localTimestamp != null) 'localTimestamp': ts(localTimestamp),
    }),
  );
}

Future<List<({String id, Map<String, Object?> fields})>> _pantryOf(
  String deliveryId,
) async {
  final items = await adminDocs('families/$_familyId/pantryItems');
  return [
    for (final item in items)
      if (fieldValue(item.fields, 'deliveryId') == deliveryId) item,
  ];
}

/// Espera a que la función marque la entrega (pantryStockedAt) y regresa sus
/// campos.
Future<Map<String, Object?>> _stockedMark(String deliveryId) async {
  final end = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(end)) {
    final delivery = await adminDoc('deliveries/$deliveryId');
    if (delivery?['pantryStockedAt'] != null) return delivery!;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw StateError(
    'La entrega $deliveryId no se marcó con pantryStockedAt. '
    '¿Está corriendo el emulador de Functions?',
  );
}

void main() {
  useProject('bank-storage-bamx');

  setUpAll(() async {
    await requireEmulator();
    await assertAllowed(
      Db.admin().setDoc('families/$_familyId', {
        'name': str('Familia Emulador'),
        'address': str('Calle 1'),
        'registrationDate': ts(DateTime.now()),
        'recoveryQuotaDefault': nul(),
        'authUid': str(_familyId),
        'appliances': arr([]),
      }),
    );
  });

  tearDownAll(() async {
    final admin = Db.admin();
    for (final item in await adminDocs('families/$_familyId/pantryItems')) {
      await admin.deleteDoc('families/$_familyId/pantryItems/${item.id}');
    }
    for (final id in _created) {
      await admin.deleteDoc('deliveries/$id');
    }
    await admin.deleteDoc('families/$_familyId');
  });

  group('onDeliveryWritten', () {
    test(
      'una entrega entregada llena la despensa, sin los caducados ni estampa',
      () async {
        final id = '$_run-entregada';
        await _writeDelivery(id, 'delivered', [
          _item('Arroz', 5),
          _item('Leche', -3, type: 'dairy', unit: 'l'),
          _item('Frijol', 30, type: 'legume', quantity: 1.5),
        ]);

        final mark = await _stockedMark(id);
        expect(fieldValue(mark, 'pantryItemsAdded'), 2);
        expect(fieldValue(mark, 'pantryItemsSkipped'), 1);

        final pantry = await _pantryOf(id);
        expect(pantry.map((item) => item.id), containsAll(['$id-1', '$id-3']));

        final arroz = pantry.firstWhere((item) => item.id == '$id-1').fields;
        expect(fieldValue(arroz, 'productId'), 'Arroz');
        expect(fieldValue(arroz, 'type'), 'grain');
        expect(fieldValue(arroz, 'quantity'), 2);
        expect(fieldValue(arroz, 'unit'), 'kg');
        expect(fieldValue(arroz, 'daysUntilExpiration'), 5);
        expect(arroz.containsKey('synchronized'), isFalse);
        expect(fieldValue(arroz, 'deviceId'), 'cloud-function');
        expect(arroz['localTimestamp'], isNotNull);

        final frijol = pantry.firstWhere((item) => item.id == '$id-3').fields;
        expect(fieldValue(frijol, 'quantity'), 1.5);
        expect(fieldValue(frijol, 'daysUntilExpiration'), 30);
      },
    );

    test('una programada no llena la despensa hasta que se entrega', () async {
      final id = '$_run-programada';
      await _writeDelivery(id, 'scheduled', [_item('Avena', 90)]);

      await Future<void>.delayed(const Duration(seconds: 3));
      expect(await _pantryOf(id), isEmpty);
      expect((await adminDoc('deliveries/$id'))?['pantryStockedAt'], isNull);

      await assertAllowed(
        Db.admin().updateDoc('deliveries/$id', {'status': str('delivered')}),
      );
      final mark = await _stockedMark(id);
      expect(fieldValue(mark, 'pantryItemsAdded'), 1);
      expect(await _pantryOf(id), hasLength(1));
    });

    test('otra escritura sobre una entrega ya surtida no duplica', () async {
      final id = '$_run-sin-duplicar';
      await _writeDelivery(id, 'delivered', [_item('Lenteja', 60)]);
      await _stockedMark(id);

      await assertAllowed(
        Db.admin().updateDoc('deliveries/$id', {
          'notes': str('otra escritura'),
        }),
      );
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(await _pantryOf(id), hasLength(1));
    });

    test('una cancelada no llena la despensa', () async {
      final id = '$_run-cancelada';
      await _writeDelivery(id, 'scheduled', [_item('Atún', 300)]);
      await assertAllowed(
        Db.admin().updateDoc('deliveries/$id', {'status': str('cancelled')}),
      );

      await Future<void>.delayed(const Duration(seconds: 3));
      expect(await _pantryOf(id), isEmpty);
      expect((await adminDoc('deliveries/$id'))?['pantryStockedAt'], isNull);
    });

    test(
      'con estampa: la despensa lleva el deviceId y la hora de entrega',
      () async {
        final id = '$_run-con-estampa';
        // JS Date solo guarda milisegundos
        final handover = DateTime.fromMillisecondsSinceEpoch(
          DateTime.now().millisecondsSinceEpoch,
        );
        await _writeDelivery(
          id,
          'delivered',
          [_item('Arroz', 5)],
          deviceId: 'staff-phone',
          localTimestamp: handover,
        );

        await _stockedMark(id);
        final pantry = await _pantryOf(id);
        final arroz = pantry.firstWhere((item) => item.id == '$id-1').fields;
        expect(fieldValue(arroz, 'deviceId'), 'staff-phone');
        expect(
          DateTime.parse(fieldValue(arroz, 'localTimestamp') as String)
              .isAtSameMomentAs(handover),
          isTrue,
        );
      },
    );

    test(
      'offline: un producto que caducó después de entregarlo sí entra',
      () async {
        final id = '$_run-offline';
        // JS Date solo guarda milisegundos
        final handover = DateTime.fromMillisecondsSinceEpoch(
          DateTime.now()
              .subtract(const Duration(days: 2))
              .millisecondsSinceEpoch,
        );
        await _writeDelivery(
          id,
          'delivered',
          [_item('Leche', -1, type: 'dairy', unit: 'l')],
          deviceId: 'staff-phone',
          localTimestamp: handover,
        );

        final mark = await _stockedMark(id);
        final stockedAt = DateTime.parse(
          fieldValue(mark, 'pantryStockedAt') as String,
        );
        expect(
          stockedAt.difference(handover),
          greaterThanOrEqualTo(const Duration(days: 1)),
        );
        final pantry = await _pantryOf(id);
        final leche = pantry.firstWhere((item) => item.id == '$id-1').fields;
        expect(
          DateTime.parse(fieldValue(leche, 'localTimestamp') as String)
              .isAtSameMomentAs(handover),
          isTrue,
        );
        expect(fieldValue(leche, 'daysUntilExpiration'), 1);
      },
    );

    test('hora no creíble: se usa la del servidor', () async {
      final id = '$_run-reloj-no-creible';
      await _writeDelivery(
        id,
        'delivered',
        [_item('Leche', -1, type: 'dairy', unit: 'l')],
        deviceId: 'staff-phone',
        localTimestamp: DateTime.now().subtract(const Duration(days: 30)),
      );

      final mark = await _stockedMark(id);
      expect(fieldValue(mark, 'pantryItemsSkipped'), 1);
      expect(fieldValue(mark, 'pantryItemsAdded'), 0);
    });
  });
}
