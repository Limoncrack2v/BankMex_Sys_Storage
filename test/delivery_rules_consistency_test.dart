import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/delivery.dart';
import 'package:bank_storage_app/data/models/pantry_item.dart';

// The delivery item limits are written in four places that cannot import each
// other: the Dart models, validDeliveryItem in firestore.rules, invalidReason
// in functions/pantry.js and the standard baskets in
// tool/standard_baskets.mjs. These tests read the files and fail when the
// copies drift apart. The rules themselves are exercised against the emulator
// in test_emulator/rules_deliveries_test.dart.
void main() {
  final rules = File('firestore.rules').readAsStringSync();
  final pantryJs = File('functions/pantry.js').readAsStringSync();
  final basketsMjs = File('tool/standard_baskets.mjs').readAsStringSync();

  // "(a|b|c)/(x|y)" from the type/unit check in validDeliveryItem.
  final typeUnit = RegExp(
    r"matches\('\(([a-z|]+)\)/\(([a-z|]+)\)'\)",
  ).firstMatch(rules);

  List<String> jsList(String name) {
    final match = RegExp('const $name = \\[([^\\]]*)\\]').firstMatch(pantryJs);
    return RegExp(
      "'([a-z]+)'",
    ).allMatches(match!.group(1)!).map((m) => m.group(1)!).toList();
  }

  group('delivery item limits in firestore.rules', () {
    test('the type and unit check was found', () {
      expect(typeUnit, isNotNull);
    });

    test('allowed types are the FoodType values', () {
      expect(
        typeUnit!.group(1)!.split('|'),
        unorderedEquals(FoodType.values.map((type) => type.name)),
      );
    });

    test('allowed units are the FoodUnit values', () {
      expect(
        typeUnit!.group(2)!.split('|'),
        unorderedEquals(FoodUnit.values.map((unit) => unit.name)),
      );
    });

    test('the name length is DeliveryItem.maxNameLength', () {
      final match = RegExp(
        r"productId\.matches\('\(\?s\)\.\{1,(\d+)\}'\)",
      ).firstMatch(rules);

      expect(int.parse(match!.group(1)!), DeliveryItem.maxNameLength);
    });

    test('the quantity ceiling is PantryItem.maxQuantity', () {
      final match = RegExp(
        r'item\.quantity > 0 && item\.quantity <= (\d+)',
      ).firstMatch(rules);

      expect(int.parse(match!.group(1)!), PantryItem.maxQuantity);
    });

    test('the item cap is Delivery.maxItems', () {
      final cap = RegExp(r'n >= 1 && n <= (\d+)').firstMatch(rules);

      expect(int.parse(cap!.group(1)!), Delivery.maxItems);
    });

    test('every position up to maxItems is checked, and none beyond', () {
      final checked = RegExp(
        r'validDeliveryItem\(items\[(\d+)\]\)',
      ).allMatches(rules).map((m) => int.parse(m.group(1)!)).toList();

      expect(checked, [for (var i = 0; i < Delivery.maxItems; i++) i]);
    });

    test('the item fields are the ones DeliveryItem.toMap writes', () {
      final item = DeliveryItem(
        productId: 'Arroz',
        type: FoodType.grain,
        quantity: 1,
        unit: FoodUnit.kg,
        expirationDate: DateTime(2026, 9, 30),
      );

      for (final field in item.toMap().keys) {
        expect(
          rules,
          contains('item.$field'),
          reason: 'validDeliveryItem does not read $field',
        );
      }
    });
  });

  group('delivery item limits in functions/pantry.js', () {
    test('FOOD_TYPES are the FoodType values', () {
      expect(
        jsList('FOOD_TYPES'),
        unorderedEquals(FoodType.values.map((type) => type.name)),
      );
    });

    test('FOOD_UNITS are the FoodUnit values', () {
      expect(
        jsList('FOOD_UNITS'),
        unorderedEquals(FoodUnit.values.map((unit) => unit.name)),
      );
    });
  });

  group('standard baskets', () {
    // One row per product: ['Arroz', 'grain', 1, 'kg', 365],
    final rows = RegExp(
      r"\['[^']+', '([a-z]+)', [\d.]+, '([a-z]+)', \d+\]",
    ).allMatches(basketsMjs).toList();

    test('the rows were found and use valid types and units', () {
      expect(rows, isNotEmpty);
      for (final row in rows) {
        expect(FoodType.values.map((type) => type.name), contains(row.group(1)));
        expect(FoodUnit.values.map((unit) => unit.name), contains(row.group(2)));
      }
    });

    test('all baskets together fit in one delivery', () {
      // Basic + fresh basket is the biggest delivery staff register from the
      // standard baskets; merging only shortens it.
      expect(rows.length, lessThanOrEqualTo(Delivery.maxItems));
    });
  });
}
