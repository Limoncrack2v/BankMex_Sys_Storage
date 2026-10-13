import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/delivery.dart';
import 'package:bank_storage_app/data/models/pantry_item.dart';
import 'package:bank_storage_app/data/models/standard_basket.dart';
import 'package:bank_storage_app/ui/models/basket_fill.dart';

ProductLine _line(
  String name, {
  double? quantity = 1,
  DateTime? expiration,
  FoodType type = FoodType.grain,
  FoodUnit unit = FoodUnit.kg,
}) => ProductLine(
  name: name,
  quantity: quantity,
  type: type,
  unit: unit,
  expiration: expiration ?? DateTime(2027, 1, 1),
);

const _blank = ProductLine(
  name: '',
  quantity: null,
  type: FoodType.grain,
  unit: FoodUnit.kg,
  expiration: null,
);

StandardBasket _basket(
  String id,
  List<(String, double, int)> items, {
  String? name,
}) => StandardBasket(
  basketId: id,
  name: name ?? id,
  description: '',
  items: [
    for (final (productId, quantity, shelfLifeDays) in items)
      StandardBasketItem(
        productId: productId,
        type: FoodType.grain,
        quantity: quantity,
        unit: FoodUnit.kg,
        shelfLifeDays: shelfLifeDays,
      ),
  ],
);

void main() {
  group('basketFillOn', () {
    final arroz = _line('Arroz');
    final frijol = _line('Frijol');
    final target = [arroz, frijol];

    test('una lista en blanco se llena con las despensas', () {
      expect(
        basketFillOn(current: [_blank], lastFilled: const [], target: target),
        BasketFillAction.fill,
      );
    });

    test('varias tarjetas en blanco también se llenan', () {
      expect(
        basketFillOn(
          current: [_blank, _blank],
          lastFilled: const [],
          target: target,
        ),
        BasketFillAction.fill,
      );
    });

    test('cambiar solo el tipo de una tarjeta vacía no cuenta como edición', () {
      const typed = ProductLine(
        name: '',
        quantity: null,
        type: FoodType.dairy,
        unit: FoodUnit.l,
        expiration: null,
      );

      expect(
        basketFillOn(current: [typed], lastFilled: const [], target: target),
        BasketFillAction.fill,
      );
    });

    test('una lista sin editar desde que se llenó se vuelve a llenar', () {
      final filled = [_line('Arroz'), _line('Lenteja')];

      expect(
        basketFillOn(current: filled, lastFilled: filled, target: target),
        BasketFillAction.fill,
      );
    });

    test('si la lista ya es la que toca no se toca nada', () {
      expect(
        basketFillOn(current: target, lastFilled: target, target: target),
        BasketFillAction.keep,
      );
    });

    test('un producto escrito a mano se conserva y se avisa', () {
      expect(
        basketFillOn(
          current: [_line('Galletas')],
          lastFilled: const [],
          target: target,
        ),
        BasketFillAction.askFirst,
      );
    });

    test('cambiar la cantidad de un producto llenado cuenta como edición', () {
      final filled = [_line('Arroz'), _line('Frijol')];
      final edited = [_line('Arroz', quantity: 2), _line('Frijol')];

      expect(
        basketFillOn(
          current: edited,
          lastFilled: filled,
          target: [_line('Arroz', quantity: 3), _line('Frijol', quantity: 3)],
        ),
        BasketFillAction.askFirst,
      );
    });

    test('quitar un producto llenado cuenta como edición', () {
      final filled = [_line('Arroz'), _line('Frijol')];

      expect(
        basketFillOn(
          current: [_line('Arroz')],
          lastFilled: filled,
          target: [_line('Arroz', quantity: 3), _line('Frijol', quantity: 3)],
        ),
        BasketFillAction.askFirst,
      );
    });

    test('agregar un producto a mano a una lista llenada cuenta como edición', () {
      final filled = [_line('Arroz')];

      expect(
        basketFillOn(
          current: [...filled, _line('Galletas')],
          lastFilled: filled,
          target: [_line('Arroz', quantity: 3)],
        ),
        BasketFillAction.askFirst,
      );
    });

    test('un producto a medio escribir cuenta como edición', () {
      expect(
        basketFillOn(
          current: [_line('Gal', quantity: null)],
          lastFilled: const [],
          target: target,
        ),
        BasketFillAction.askFirst,
      );
    });

    test('quitar todas las despensas vacía una lista sin editar', () {
      final filled = [_line('Arroz')];

      expect(
        basketFillOn(current: filled, lastFilled: filled, target: const []),
        BasketFillAction.fill,
      );
    });

    test('quitar todas las despensas no borra lo capturado a mano', () {
      expect(
        basketFillOn(
          current: [_line('Galletas')],
          lastFilled: [_line('Arroz')],
          target: const [],
        ),
        BasketFillAction.keep,
      );
    });

    test('sin despensas y con la lista en blanco no hay nada que hacer', () {
      expect(
        basketFillOn(current: [_blank], lastFilled: const [], target: const []),
        BasketFillAction.keep,
      );
    });
  });

  group('ProductLine', () {
    test('la caducidad se compara por día, sin la hora', () {
      final item = DeliveryItem(
        productId: ' Arroz ',
        type: FoodType.grain,
        quantity: 1,
        unit: FoodUnit.kg,
        expirationDate: DateTime(2027, 1, 1, 18, 30),
      );

      expect(ProductLine.fromItem(item), _line('Arroz'));
    });

    test('una cantidad de 0 no es una línea en blanco', () {
      const zero = ProductLine(
        name: '',
        quantity: 0,
        type: FoodType.grain,
        unit: FoodUnit.kg,
        expiration: null,
      );

      expect(zero.isBlank, isFalse);
    });
  });

  group('basketTarget', () {
    final date = DateTime(2026, 10, 28);
    final basica = _basket('basica', [
      ('Arroz', 1, 365),
      ('Avena', 0.4, 270),
    ], name: 'Despensa básica');
    final frescos = _basket('frescos', [('Huevo', 12, 21)]);

    test('multiplica cada cantidad por el número de despensas', () {
      final target = basketTarget(
        baskets: [basica, frescos],
        date: date,
        packages: 3,
      );

      expect(target.items!.map((i) => i.productId), ['Arroz', 'Avena', 'Huevo']);
      expect(target.items!.map((i) => i.quantity), [3, 1.2, 36]);
    });

    test('la caducidad se cuenta desde la fecha de entrega', () {
      final target = basketTarget(
        baskets: [basica, frescos],
        date: date,
        packages: 1,
      );

      expect(target.items![0].expirationDate, DateTime(2027, 10, 28));
      expect(target.items![2].expirationDate, DateTime(2026, 11, 18));
    });

    test('sin despensas elegidas la lista objetivo es vacía', () {
      final target = basketTarget(baskets: const [], date: null, packages: null);

      expect(target.items, isEmpty);
      expect(target.waitingFor, isNull);
    });

    test('sin fecha de entrega espera la fecha', () {
      final target = basketTarget(baskets: [basica], date: null, packages: 1);

      expect(target.items, isNull);
      expect(target.waitingFor, BasketWait.date);
    });

    test('sin un número de despensas válido espera el número', () {
      final target = basketTarget(baskets: [basica], date: date, packages: null);

      expect(target.items, isNull);
      expect(target.waitingFor, BasketWait.packages);
    });

    test('si pasan del límite de productos devuelve el problema sin lanzar', () {
      final huge = _basket('huge', [
        for (var i = 0; i <= Delivery.maxItems; i++) ('Producto $i', 1, 30),
      ]);

      final target = basketTarget(baskets: [huge], date: date, packages: 1);

      expect(target.items, isNull);
      expect(target.problem, contains('${Delivery.maxItems + 1} productos'));
      expect(target.problem, contains('hasta ${Delivery.maxItems}'));
    });

    test('justo en el límite de productos sí se llena', () {
      final full = _basket('full', [
        for (var i = 0; i < Delivery.maxItems; i++) ('Producto $i', 1, 30),
      ]);

      final target = basketTarget(baskets: [full], date: date, packages: 1);

      expect(target.items, hasLength(Delivery.maxItems));
      expect(target.problem, isNull);
    });
  });
}
