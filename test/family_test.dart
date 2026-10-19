import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/family.dart';

Family buildFamily({
  String familyId = 'familia-1',
  String address = 'Calle 1',
  DateTime? registrationDate,
  String authUid = 'familia-1',
  List<String> appliances = const [],
  DateTime? nextDeliveryDate,
}) => Family(
  familyId: familyId,
  address: address,
  registrationDate: registrationDate ?? DateTime(2026, 9, 1),
  authUid: authUid,
  appliances: appliances,
  nextDeliveryDate: nextDeliveryDate,
);

void main() {
  group('Family.toFirestore', () {
    test('nunca escribe nextDeliveryDate, solo syncNextDelivery lo hace)', () {
      final data = buildFamily(nextDeliveryDate: DateTime(2026, 10, 2)).toFirestore();
      expect(data.containsKey('nextDeliveryDate'), isFalse);
    });

    test('escribe los ids de los electrodomésticos', () {
      final data = buildFamily(
        appliances: [Appliance.stove.id, Appliance.fridge.id],
      ).toFirestore();
      expect(data['appliances'], ['estufa', 'refrigerador']);
    });
  });

  group('Family.validateAppliances', () {
    test('acepta ninguno y electrodomésticos conocidos', () {
      expect(Family.validateAppliances(const []), isNull);
      expect(
        Family.validateAppliances([
          for (final appliance in Appliance.values) appliance.id,
        ]),
        isNull,
      );
    });

    test('rechaza ids desconocidos y repetidos', () {
      expect(Family.validateAppliances(const ['freidora']), isNotNull);
      expect(Family.validateAppliances(const ['horno', 'horno']), isNotNull);
    });

    test('los ids coinciden con los que aceptan las reglas', () {
      expect(Appliance.values.map((a) => a.id), [
        'estufa',
        'refrigerador',
        'horno',
        'microondas',
        'licuadora',
        'ollaPresion',
      ]);
    });
  });

  group('Family.validateDetails', () {
    String? validate({
      String name = 'Familia Ramírez',
      String address = 'Calle 1',
      double? quota = 250,
    }) => Family.validateDetails(
      name: name,
      address: address,
      recoveryQuotaDefault: quota,
    );

    test('acepta datos válidos y la cuota Exenta', () {
      expect(validate(), isNull);
      expect(validate(quota: null), isNull);
      expect(validate(quota: 0), isNull);
    });

    test('pide nombre y dirección', () {
      expect(validate(name: '  '), isNotNull);
      expect(validate(address: ''), isNotNull);
    });

    test('usa los límites de validFamily', () {
      expect(validate(name: 'a' * 100), isNull);
      expect(validate(name: 'a' * 101), isNotNull);
      expect(validate(address: 'a' * 200), isNull);
      expect(validate(address: 'a' * 201), isNotNull);
    });

    test('rechaza una cuota negativa o que no es un número', () {
      expect(validate(quota: -1), isNotNull);
      expect(validate(quota: double.nan), isNotNull);
      expect(validate(quota: double.infinity), isNotNull);
    });
  });

  group('Family.detailChanges', () {
    final family = Family(
      familyId: 'familia-1',
      name: 'Familia Ramírez',
      address: 'Calle 1',
      registrationDate: DateTime(2026, 9, 1),
      recoveryQuotaDefault: 250,
      authUid: 'familia-1',
      appliances: const [],
      nextDeliveryDate: DateTime(2026, 10, 20),
    );

    test('sin cambios no escribe nada', () {
      expect(
        family.detailChanges(
          name: ' Familia Ramírez ',
          address: 'Calle 1',
          recoveryQuotaDefault: 250,
        ),
        isEmpty,
      );
    });

    test('solo trae los campos que cambian, sin espacios de más', () {
      expect(
        family.detailChanges(
          name: 'Familia Ramírez',
          address: ' Calle 2 ',
          recoveryQuotaDefault: 250,
        ),
        {'address': 'Calle 2'},
      );
    });

    test('Exenta escribe la cuota en null', () {
      expect(
        family.detailChanges(
          name: 'Familia Ramírez',
          address: 'Calle 1',
          recoveryQuotaDefault: null,
        ),
        {'recoveryQuotaDefault': null},
      );
    });

    test('nunca trae authUid ni nextDeliveryDate', () {
      final changes = family.detailChanges(
        name: 'Familia López',
        address: 'Calle 2',
        recoveryQuotaDefault: 100,
      );
      expect(
        changes.keys,
        unorderedEquals(['name', 'address', 'recoveryQuotaDefault']),
      );
    });

    test('a un hogar sin nombre le agrega el nombre', () {
      expect(
        buildFamily().detailChanges(
          name: 'Familia Nueva',
          address: 'Calle 1',
          recoveryQuotaDefault: null,
        ),
        {'name': 'Familia Nueva'},
      );
    });
  });
}
