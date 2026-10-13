import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/delivery.dart';
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

  group('StandardBasket.deliveryItemsFor', () {
    StandardBasketItem product(
      String productId,
      double quantity, {
      FoodType type = FoodType.grain,
      FoodUnit unit = FoodUnit.kg,
      int shelfLifeDays = 365,
    }) => StandardBasketItem(
      productId: productId,
      type: type,
      quantity: quantity,
      unit: unit,
      shelfLifeDays: shelfLifeDays,
    );

    StandardBasket basket(String id, List<StandardBasketItem> items) =>
        StandardBasket(basketId: id, name: id, description: '', items: items);

    final date = DateTime(2026, 10, 28);
    final basica = basket('despensa-basica', [
      product('Arroz', 1),
      product('Avena', 0.4, shelfLifeDays: 270),
      product('Atún en lata', 2, type: FoodType.canned, unit: FoodUnit.can),
    ]);
    final frescos = basket('frescos', [
      product(
        'Huevo',
        12,
        type: FoodType.protein,
        unit: FoodUnit.piece,
        shelfLifeDays: 21,
      ),
    ]);

    test('multiplies every quantity by packages', () {
      final items = StandardBasket.deliveryItemsFor(
        [basica],
        packages: 3,
        deliveryDate: date,
      );

      expect(items.map((i) => i.productId), ['Arroz', 'Avena', 'Atún en lata']);
      expect(items.map((i) => i.quantity), [3, 1.2, 6]);
      expect(items[1].expirationDate, DateTime(2027, 7, 25));
      expect(items.every((i) => i.validate() == null), isTrue);
    });

    test('one package keeps the basket quantities', () {
      final items = StandardBasket.deliveryItemsFor(
        [basica],
        packages: 1,
        deliveryDate: date,
      );

      expect(items.map((i) => i.quantity), [1, 0.4, 2]);
    });

    test('joins several baskets into one list', () {
      final items = StandardBasket.deliveryItemsFor(
        [basica, frescos],
        packages: 2,
        deliveryDate: date,
      );

      expect(items.map((i) => i.productId), [
        'Arroz',
        'Avena',
        'Atún en lata',
        'Huevo',
      ]);
      expect(items.last.quantity, 24);
      expect(items.last.expirationDate, DateTime(2026, 11, 18));
    });

    test('the same product in two baskets is added up in one line', () {
      final extra = basket('extra', [product(' arroz ', 0.5)]);

      final items = StandardBasket.deliveryItemsFor(
        [basica, extra],
        packages: 2,
        deliveryDate: date,
      );

      expect(items.where((i) => i.productId == 'Arroz').single.quantity, 3);
      expect(items, hasLength(3));
    });

    test('a product with another expiration stays apart', () {
      final extra = basket('extra', [product('Arroz', 1, shelfLifeDays: 30)]);

      final items = StandardBasket.deliveryItemsFor(
        [basica, extra],
        packages: 1,
        deliveryDate: date,
      );

      expect(items.where((i) => i.productId == 'Arroz'), hasLength(2));
    });

    test('rejects packages outside 1..maxPackages', () {
      for (final packages in [0, -1, Delivery.maxPackages + 1]) {
        expect(
          () => StandardBasket.deliveryItemsFor(
            [basica],
            packages: packages,
            deliveryDate: date,
          ),
          throwsArgumentError,
        );
      }
    });

    test('rejects more than maxItems products', () {
      final big = basket('grande', [
        for (var i = 0; i <= Delivery.maxItems; i++) product('Producto $i', 1),
      ]);

      expect(
        () => StandardBasket.deliveryItemsFor(
          [big],
          packages: 1,
          deliveryDate: date,
        ),
        throwsArgumentError,
      );
    });

    test('no baskets give no products', () {
      expect(
        StandardBasket.deliveryItemsFor(
          const [],
          packages: 1,
          deliveryDate: date,
        ),
        isEmpty,
      );
    });
  });
}
