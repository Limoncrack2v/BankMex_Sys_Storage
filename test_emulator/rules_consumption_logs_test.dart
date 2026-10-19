// Pruebas de validConsumptionLog en firestore.rules (families/{id}/
// consumptionLogs) contra el emulador de Firestore (127.0.0.1:8080).
//
// Uso: flutter test test_emulator/rules_consumption_logs_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'support/emulator.dart';

Map<String, Object?> now() => ts(DateTime.utc(2026, 10, 14, 12));

Map<String, Map<String, Object?>> log({
  Map<String, Map<String, Object?>> change = const {},
  List<String> remove = const [],
}) {
  final fields = <String, Map<String, Object?>>{
    'productId': str('Arroz'),
    'quantity': number(0.5),
    'unit': str('kg'),
    'category': str('grain'),
    'at': now(),
    'deviceId': str('device-1'),
    'reason': str('consumed'),
    ...change,
  };
  for (final key in remove) {
    fields.remove(key);
  }
  return fields;
}

Map<String, Map<String, Object?>> profile(String role) => {
  'name': str('Nombre'),
  'email': str('x@y.com'),
  'role': str(role),
  'createdAt': now(),
};

const _path = 'families/famA/consumptionLogs/log1';

Db fam1() => Db.user('fam1');
Db fam2() => Db.user('fam2');
Db staff() => Db.user('staff1');

void main() {
  useProject('demo-bamx-consumption-logs');

  setUpAll(requireEmulator);
  setUp(() async {
    await clearFirestore();
    final admin = Db.admin();
    await admin.setDoc('users/staff1', profile('staff'));
    await admin.setDoc('users/fam1', profile('family'));
    await admin.setDoc('users/fam2', profile('family'));
    await admin.setDoc('families/famA', {
      'address': str('Calle 1'),
      'registrationDate': now(),
      'authUid': str('fam1'),
      'appliances': arr([]),
    });
  });

  group('consumptionLogs', () {
    test('la familia dueña agrega un registro válido', () async {
      await assertAllowed(fam1().setDoc(_path, log()));
    });

    test('un desperdicio caducado también es válido', () async {
      await assertAllowed(
        fam1().setDoc(_path, log(change: {'reason': str('expired')})),
      );
    });

    test('otra familia no agrega registros', () async {
      await assertDenied(fam2().setDoc(_path, log()));
    });

    test('falta un campo', () async {
      for (final key in log().keys) {
        await assertDenied(fam1().setDoc(_path, log(remove: [key])));
      }
    });

    test('un campo de más', () async {
      await assertDenied(fam1().setDoc(_path, log(change: {'note': str('x')})));
    });

    test('valores inválidos', () async {
      final cases = <Map<String, Map<String, Object?>>>[
        {'quantity': number(0)},
        {'quantity': number(-1)},
        {'quantity': number(1000001)},
        {'quantity': str('1')},
        {'unit': str('cucharada')},
        {'category': str('postre')},
        {'reason': str('regalado')},
        {'productId': str('')},
        {'productId': str('a' * 101)},
        {'deviceId': str('')},
        {'deviceId': str('a' * 65)},
        {'at': str('hoy')},
      ];
      for (final change in cases) {
        await assertDenied(fam1().setDoc(_path, log(change: change)));
      }
    });

    test('la hora no puede estar en el futuro', () async {
      final future = ts(DateTime.now().toUtc().add(const Duration(hours: 1)));
      await assertDenied(fam1().setDoc(_path, log(change: {'at': future})));
    });

    test('un registro viejo (sin conexión) sí se acepta', () async {
      final old = ts(DateTime.utc(2026, 9, 1));
      await assertAllowed(fam1().setDoc(_path, log(change: {'at': old})));
    });

    test('un registro no se edita ni se borra', () async {
      await Db.admin().setDoc(_path, log());
      await assertDenied(fam1().updateDoc(_path, {'quantity': number(99)}));
      await assertDenied(fam1().deleteDoc(_path));
      await assertDenied(staff().updateDoc(_path, {'quantity': number(99)}));
      await assertDenied(staff().deleteDoc(_path));
    });

    test('la familia y el staff los leen, otra familia no', () async {
      await Db.admin().setDoc(_path, log());
      await assertAllowed(fam1().getDoc(_path));
      await assertAllowed(staff().getDoc(_path));
      await assertDenied(fam2().getDoc(_path));
    });
  });
}
