import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/delivery.dart';
import 'package:bank_storage_app/data/models/pantry_item.dart';

DeliveryItem buildItem({
  String productId = 'Leche entera',
  double quantity = 2,
  DateTime? expirationDate,
}) => DeliveryItem(
  productId: productId,
  type: FoodType.dairy,
  quantity: quantity,
  unit: FoodUnit.l,
  expirationDate: expirationDate ?? DateTime(2026, 9, 30),
);

Delivery buildDelivery({
  String familyId = 'familia-1',
  String familyName = 'Familia Ramírez',
  int packages = 1,
  double? recoveryFee,
  String? justification,
  String? notes,
  DeliveryStatus status = DeliveryStatus.scheduled,
  List<DeliveryItem>? items,
}) => Delivery(
  deliveryId: '',
  familyId: familyId,
  familyName: familyName,
  deliveryDate: DateTime(2026, 9, 25),
  packages: packages,
  recoveryFee: recoveryFee,
  justification: justification,
  status: status,
  notes: notes,
  items: items ?? [buildItem()],
  createdAt: DateTime(2026, 9, 21),
);

void main() {
  group('DeliveryItem.validate', () {
    test('accepts a valid item', () {
      expect(buildItem().validate(), isNull);
    });

    test('rejects blank names and names over 100 characters', () {
      expect(buildItem(productId: '').validate(), isNotNull);
      expect(buildItem(productId: '   ').validate(), isNotNull);
      expect(buildItem(productId: 'a' * 100).validate(), isNull);
      expect(buildItem(productId: 'a' * 101).validate(), isNotNull);
    });

    test('rejects zero, negative, NaN, infinite and huge quantities', () {
      expect(buildItem(quantity: 0).validate(), isNotNull);
      expect(buildItem(quantity: -1).validate(), isNotNull);
      expect(buildItem(quantity: double.nan).validate(), isNotNull);
      expect(buildItem(quantity: double.infinity).validate(), isNotNull);
      expect(buildItem(quantity: PantryItem.maxQuantity).validate(), isNull);
      expect(
        buildItem(quantity: PantryItem.maxQuantity + 1).validate(),
        isNotNull,
      );
    });
  });

  group('DeliveryItem.toMap', () {
    test('writes the item fields with a trimmed name', () {
      final data = buildItem(productId: '  Arroz  ').toMap();

      expect(data.keys.toSet(), {
        'productId',
        'type',
        'quantity',
        'unit',
        'expirationDate',
      });
      expect(data['productId'], 'Arroz');
      expect(data['type'], 'dairy');
      expect(data['unit'], 'l');
      expect(data['quantity'], 2.0);
      expect(data['expirationDate'], isA<Timestamp>());
    });

    test('round trips through fromMap', () {
      final item = buildItem(quantity: 3.5);
      final copy = DeliveryItem.fromMap(item.toMap());

      expect(copy.productId, item.productId);
      expect(copy.type, item.type);
      expect(copy.quantity, item.quantity);
      expect(copy.unit, item.unit);
      expect(copy.expirationDate, item.expirationDate);
    });
  });

  group('Delivery.toFirestore', () {
    test('omits recoveryFee, justification and notes when not set', () {
      final delivery = buildDelivery();
      final data = delivery.toFirestore();

      expect(delivery.isExempt, isTrue);
      expect(data.keys.toSet(), {
        'familyId',
        'familyName',
        'deliveryDate',
        'packages',
        'status',
        'items',
        'createdAt',
      });
      expect(data['status'], 'scheduled');
      expect(data['packages'], 1);
      expect(data['deliveryDate'], isA<Timestamp>());
      expect(data['createdAt'], isA<Timestamp>());
      expect(data['items'], hasLength(1));
      expect((data['items'] as List).first, isA<Map<String, dynamic>>());
    });

    test('omits blank notes and justification', () {
      final data = buildDelivery(
        recoveryFee: 25,
        justification: '   ',
        notes: '\n ',
      ).toFirestore();

      expect(data.containsKey('justification'), isFalse);
      expect(data.containsKey('notes'), isFalse);
      expect(data['recoveryFee'], 25.0);
    });

    test('trims the family name, justification and notes', () {
      final delivery = buildDelivery(
        familyName: '  Familia Ramírez ',
        recoveryFee: 0,
        justification: '  Nivel de ingreso medio  ',
        notes: ' Tocar el timbre ',
        status: DeliveryStatus.delivered,
      );
      final data = delivery.toFirestore();

      expect(delivery.isExempt, isFalse);
      expect(data['familyName'], 'Familia Ramírez');
      expect(data['justification'], 'Nivel de ingreso medio');
      expect(data['notes'], 'Tocar el timbre');
      expect(data['recoveryFee'], 0.0);
      expect(data['status'], 'delivered');
    });

    test('enum names match the values allowed by the rules', () {
      expect(DeliveryStatus.values.map((e) => e.name), [
        'scheduled',
        'delivered',
        'cancelled',
        'reassigned',
      ]);
    });

    test('cuts the family name to the 100 characters the rules allow', () {
      // Un hogar sin nombre usa su dirección, que puede llegar a 200.
      final address = 'Av. Siempre Viva ${'muy larga ' * 30}';
      final data = Delivery(
        deliveryId: '',
        familyId: 'familia-1',
        familyName: address,
        deliveryDate: DateTime(2026, 9, 25),
        packages: 1,
        status: DeliveryStatus.scheduled,
        items: [buildItem()],
        createdAt: DateTime(2026, 9, 21),
      ).toFirestore();

      expect((data['familyName'] as String).length, 100);
      expect(data['familyName'], address.substring(0, 100));
    });

    test('writes reassignedFrom only when set and never reassignedTo', () {
      final plain = buildDelivery().toFirestore();
      expect(plain.containsKey('reassignedFrom'), isFalse);
      expect(plain.containsKey('reassignedTo'), isFalse);

      final reassigned = Delivery(
        deliveryId: 'nueva',
        familyId: 'familia-2',
        familyName: 'Familia López',
        deliveryDate: DateTime(2026, 9, 25),
        packages: 1,
        status: DeliveryStatus.scheduled,
        items: [buildItem()],
        createdAt: DateTime(2026, 9, 21),
        reassignedFrom: 'original',
        reassignedTo: 'no-se-escribe',
      ).toFirestore();
      expect(reassigned['reassignedFrom'], 'original');
      expect(reassigned.containsKey('reassignedTo'), isFalse);
    });
  });

  group('DeliveryItem.isExpiredOn', () {
    test('the expiration day itself is not expired, the next day is', () {
      final item = DeliveryItem(
        productId: 'Leche',
        type: FoodType.dairy,
        quantity: 1,
        unit: FoodUnit.l,
        expirationDate: DateTime(2026, 10, 1, 8),
      );

      expect(item.isExpiredOn(DateTime(2026, 9, 30, 23)), isFalse);
      expect(item.isExpiredOn(DateTime(2026, 10, 1, 23, 59)), isFalse);
      expect(item.isExpiredOn(DateTime(2026, 10, 2)), isTrue);
    });
  });

  group('Delivery.validate', () {
    test('accepts a valid delivery', () {
      expect(buildDelivery().validate(), isNull);
      expect(buildDelivery(recoveryFee: 25).validate(), isNull);
    });

    test('requires a family', () {
      expect(buildDelivery(familyId: ' ').validate(), isNotNull);
    });

    test('packages must be between 1 and 100', () {
      expect(buildDelivery(packages: 0).validate(), isNotNull);
      expect(buildDelivery(packages: Delivery.maxPackages).validate(), isNull);
      expect(
        buildDelivery(packages: Delivery.maxPackages + 1).validate(),
        isNotNull,
      );
    });

    test('requires between 1 and 100 items', () {
      expect(buildDelivery(items: const []).validate(), isNotNull);
      expect(
        buildDelivery(
          items: List.generate(Delivery.maxItems, (_) => buildItem()),
        ).validate(),
        isNull,
      );
      expect(
        buildDelivery(
          items: List.generate(Delivery.maxItems + 1, (_) => buildItem()),
        ).validate(),
        isNotNull,
      );
    });

    test('reports the error of an invalid item', () {
      final invalid = buildItem(quantity: 0);
      expect(
        buildDelivery(items: [buildItem(), invalid]).validate(),
        invalid.validate(),
      );
    });

    test('rejects negative, NaN and excessive recovery fees', () {
      expect(buildDelivery(recoveryFee: -1).validate(), isNotNull);
      expect(buildDelivery(recoveryFee: double.nan).validate(), isNotNull);
      expect(buildDelivery(recoveryFee: 100001).validate(), isNotNull);
      expect(buildDelivery(recoveryFee: 0).validate(), isNull);
    });
  });
}
