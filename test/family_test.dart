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
}
