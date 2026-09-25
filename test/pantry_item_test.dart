import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/pantry_item.dart';

PantryItem buildItem({
  String productId = 'arroz',
  String deliveryId = 'entrega-001',
  double quantity = 2.5,
  int daysUntilExpiration = 30,
  String deviceId = 'device-test',
}) => PantryItem(
  pantryItemId: '',
  productId: productId,
  deliveryId: deliveryId,
  type: FoodType.grain,
  quantity: quantity,
  unit: FoodUnit.kg,
  daysUntilExpiration: daysUntilExpiration,
  deviceId: deviceId,
  localTimestamp: DateTime(2026, 9, 21),
);

void main() {
  group('PantryItem.validate', () {
    test('accepts a valid item', () {
      expect(buildItem().validate(), isNull);
    });

    test('rejects empty productId, deliveryId and deviceId', () {
      expect(buildItem(productId: ' ').validate(), isNotNull);
      expect(buildItem(deliveryId: '').validate(), isNotNull);
      expect(buildItem(deviceId: '').validate(), isNotNull);
    });

    test('rejects zero, negative, NaN and infinite quantities', () {
      expect(buildItem(quantity: 0).validate(), isNotNull);
      expect(buildItem(quantity: -1).validate(), isNotNull);
      expect(buildItem(quantity: double.nan).validate(), isNotNull);
      expect(buildItem(quantity: double.infinity).validate(), isNotNull);
    });

    test('quantity upper bound is inclusive', () {
      expect(buildItem(quantity: PantryItem.maxQuantity).validate(), isNull);
      expect(
        buildItem(quantity: PantryItem.maxQuantity + 1).validate(),
        isNotNull,
      );
    });

    test('rejects negative daysUntilExpiration, accepts zero', () {
      expect(buildItem(daysUntilExpiration: -1).validate(), isNotNull);
      expect(buildItem(daysUntilExpiration: 0).validate(), isNull);
    });
  });

  group('PantryItem.withDeliveryId', () {
    test('replaces only the deliveryId', () {
      final original = buildItem(deliveryId: 'viejo');
      final moved = original.withDeliveryId('nuevo');

      expect(moved.deliveryId, 'nuevo');
      expect(moved.productId, original.productId);
      expect(moved.quantity, original.quantity);
      expect(moved.type, original.type);
      expect(moved.unit, original.unit);
    });
  });

  group('PantryItem.toFirestore', () {
    test('writes exactly the fields the security rules allow', () {
      final data = buildItem().toFirestore();

      expect(data.keys.toSet(), {
        'productId',
        'deliveryId',
        'type',
        'quantity',
        'unit',
        'daysUntilExpiration',
        'deviceId',
        'localTimestamp',
      });
      expect(data['type'], 'grain');
      expect(data['unit'], 'kg');
      expect(data['quantity'], 2.5);
      expect(data['localTimestamp'], isA<Timestamp>());
    });

    test('enum names match the values allowed by the rules', () {
      expect(FoodType.values.map((e) => e.name), [
        'grain',
        'legume',
        'canned',
        'dairy',
        'produce',
        'protein',
        'beverage',
        'other',
      ]);
      expect(FoodUnit.values.map((e) => e.name), [
        'kg',
        'g',
        'l',
        'ml',
        'piece',
        'can',
        'pack',
      ]);
    });
  });
}
