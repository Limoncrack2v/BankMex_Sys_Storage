import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/pantry_item.dart';
import 'package:bank_storage_app/data/models/standard_basket.dart';

void main() {
  group('StandardBasket.fromMap', () {
    test('reads the fields written by tool/standard_baskets.mjs', () {
      final basket = StandardBasket.fromMap('despensa-basica', {
        'name': 'Despensa básica',
        'description': 'Abarrotes',
        'items': [
          {
            'productId': 'Arroz',
            'type': 'grain',
            'quantity': 1,
            'unit': 'kg',
            'shelfLifeDays': 365,
          },
          {
            'productId': 'Atún en lata',
            'type': 'canned',
            'quantity': 2.0,
            'unit': 'can',
            'shelfLifeDays': 730,
          },
        ],
      });

      expect(basket.basketId, 'despensa-basica');
      expect(basket.name, 'Despensa básica');
      expect(basket.items, hasLength(2));
      expect(basket.items.first.type, FoodType.grain);
      expect(basket.items.first.quantity, 1.0);
      expect(basket.items.last.unit, FoodUnit.can);
      expect(basket.items.last.shelfLifeDays, 730);
    });

    test('a basket without description or items is still valid', () {
      final basket = StandardBasket.fromMap('vacia', {'name': 'Vacía'});

      expect(basket.description, isEmpty);
      expect(basket.items, isEmpty);
    });
  });

  group('StandardBasket.toDeliveryItems', () {
    test('each product expires shelfLifeDays after the delivery', () {
      const basket = StandardBasket(
        basketId: 'frescos',
        name: 'Frescos',
        description: '',
        items: [
          StandardBasketItem(
            productId: 'Jitomate',
            type: FoodType.produce,
            quantity: 1,
            unit: FoodUnit.kg,
            shelfLifeDays: 7,
          ),
          StandardBasketItem(
            productId: 'Huevo',
            type: FoodType.protein,
            quantity: 12,
            unit: FoodUnit.piece,
            shelfLifeDays: 21,
          ),
        ],
      );

      final items = basket.toDeliveryItems(DateTime(2026, 10, 28, 15, 30));

      expect(items.map((i) => i.productId), ['Jitomate', 'Huevo']);
      expect(items.first.expirationDate, DateTime(2026, 11, 4));
      expect(items.last.expirationDate, DateTime(2026, 11, 18));
      expect(items.last.quantity, 12);
      expect(items.every((i) => i.validate() == null), isTrue);
    });
  });
}
