// Prueba las Cloud Functions de functions/index.js contra los emuladores:
// - onDeliveryWritten: al quedar una entrega como entregada, sus productos
//   deben aparecer en la despensa de la familia.
// - syncNextDelivery: families/{familyId}.nextDeliveryDate debe quedar en la
//   entrega programada más cercana de hoy en adelante, o desaparecer si no hay.
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
final _families = <String>[];

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
  DateTime? deliveryDate,
  String? familyId,
}) async {
  _created.add(id);
  await assertAllowed(
    Db.admin().setDoc('deliveries/$id', {
      'familyId': str(familyId ?? _familyId),
      'familyName': str('Familia Emulador'),
      'deliveryDate': ts(deliveryDate ?? DateTime.now()),
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

/// Espera a que families/{familyId}.nextDeliveryDate sea [expected], o a que
/// no exista si [expected] es null.
Future<void> _expectNextDelivery(String familyId, DateTime? expected) async {
  final end = DateTime.now().add(const Duration(seconds: 30));
  Object? last;
  while (DateTime.now().isBefore(end)) {
    final family = await adminDoc('families/$familyId');
    last = fieldValue(family, 'nextDeliveryDate');
    if (expected == null) {
      if (last == null) return;
    } else if (last is String &&
        DateTime.parse(last).isAtSameMomentAs(expected)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw StateError(
    'families/$familyId.nextDeliveryDate quedó en $last y se esperaba '
    '$expected. ¿Está corriendo el emulador de Functions?',
  );
}

/// Familia nueva solo para una prueba, para que las entregas de otras pruebas
/// no cambien su próxima entrega.
Future<String> _newFamily(String name) async {
  final id = '$_run-$name';
  _families.add(id);
  await assertAllowed(
    Db.admin().setDoc('families/$id', {
      'name': str('Familia Emulador'),
      'address': str('Calle 1'),
      'registrationDate': ts(DateTime.now()),
      'recoveryQuotaDefault': nul(),
      'authUid': str(id),
      'appliances': arr([]),
    }),
  );
  return id;
}

/// Mediodía de hoy con [offset] días. A mediodía no cae en otro día de
/// calendario de Guadalajara, y sin milisegundos se compara exacto con la
/// fecha que regresa la función (JS Date solo guarda milisegundos).
DateTime _dayAt(int offset) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + offset, 12);
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

  // Borrar una familia no borra su despensa (subcolección), y los datos del
  // emulador se guardan al cerrarlo: se borra todo lo que creó la corrida.
  tearDownAll(() async {
    final admin = Db.admin();
    for (final id in _created) {
      await admin.deleteDoc('deliveries/$id');
    }
    for (final family in [_familyId, ..._families]) {
      for (final item in await adminDocs('families/$family/pantryItems')) {
        await admin.deleteDoc('families/$family/pantryItems/${item.id}');
      }
      await admin.deleteDoc('families/$family');
    }
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

  group('syncNextDelivery', () {
    test(
      'una entrega programada para mañana pone su fecha en la familia',
      () async {
        final familyId = await _newFamily('proxima-programada');
        final tomorrow = _dayAt(1);
        await _writeDelivery(
          '$_run-proxima-programada',
          'scheduled',
          [_item('Arroz', 5)],
          familyId: familyId,
          deliveryDate: tomorrow,
        );

        await _expectNextDelivery(familyId, tomorrow);
      },
    );

    test('de dos entregas programadas, gana la más cercana', () async {
      final familyId = await _newFamily('proxima-dos');
      final tomorrow = _dayAt(1);
      final inThreeDays = _dayAt(3);

      // La lejana primero: si la función solo tomara la última escritura,
      // la prueba fallaría.
      await _writeDelivery(
        '$_run-proxima-dos-lejana',
        'scheduled',
        [_item('Arroz', 5)],
        familyId: familyId,
        deliveryDate: inThreeDays,
      );
      await _writeDelivery(
        '$_run-proxima-dos-cercana',
        'scheduled',
        [_item('Arroz', 5)],
        familyId: familyId,
        deliveryDate: tomorrow,
      );

      await _expectNextDelivery(familyId, tomorrow);
    });

    test('al cancelar la más cercana, pasa a la siguiente', () async {
      final familyId = await _newFamily('proxima-cancelada');
      final tomorrow = _dayAt(1);
      final inThreeDays = _dayAt(3);
      final nearId = '$_run-proxima-cancelada-cercana';

      await _writeDelivery(
        '$_run-proxima-cancelada-lejana',
        'scheduled',
        [_item('Arroz', 5)],
        familyId: familyId,
        deliveryDate: inThreeDays,
      );
      await _writeDelivery(
        nearId,
        'scheduled',
        [_item('Arroz', 5)],
        familyId: familyId,
        deliveryDate: tomorrow,
      );
      await _expectNextDelivery(familyId, tomorrow);

      await assertAllowed(
        Db.admin().updateDoc('deliveries/$nearId', {
          'status': str('cancelled'),
        }),
      );
      await _expectNextDelivery(familyId, inThreeDays);
    });

    test('al entregar la última programada, el campo desaparece', () async {
      final familyId = await _newFamily('proxima-entregada');
      final tomorrow = _dayAt(1);
      final id = '$_run-proxima-entregada';

      await _writeDelivery(
        id,
        'scheduled',
        [_item('Arroz', 5)],
        familyId: familyId,
        deliveryDate: tomorrow,
      );
      await _expectNextDelivery(familyId, tomorrow);

      await assertAllowed(
        Db.admin().updateDoc('deliveries/$id', {'status': str('delivered')}),
      );
      await _expectNextDelivery(familyId, null);
    });

    // Esperar null de una vez pasaría antes de que la función corra (el campo
    // nunca existió). Primero se confirma que corrió con la de mañana y la de
    // ayer no cuenta; al cancelar la de mañana, solo queda la de ayer.
    test('una programada con fecha pasada no cuenta', () async {
      final familyId = await _newFamily('proxima-pasada');
      final tomorrow = _dayAt(1);
      final tomorrowId = '$_run-proxima-pasada-manana';

      await _writeDelivery(
        '$_run-proxima-pasada-ayer',
        'scheduled',
        [_item('Arroz', 5)],
        familyId: familyId,
        deliveryDate: _dayAt(-1),
      );
      await _writeDelivery(
        tomorrowId,
        'scheduled',
        [_item('Arroz', 5)],
        familyId: familyId,
        deliveryDate: tomorrow,
      );
      await _expectNextDelivery(familyId, tomorrow);

      await assertAllowed(
        Db.admin().updateDoc('deliveries/$tomorrowId', {
          'status': str('cancelled'),
        }),
      );
      await _expectNextDelivery(familyId, null);
    });
  });
}
