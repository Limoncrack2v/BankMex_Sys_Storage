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
  });
}
