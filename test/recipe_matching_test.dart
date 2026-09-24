import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/pantry_item.dart';
import 'package:bank_storage_app/ui/models/recipe.dart';
import 'package:bank_storage_app/ui/sample_data.dart';

final today = DateTime(2026, 9, 21);
var _nextId = 0;

PantryItem item(
  String productId,
  double quantity,
  FoodUnit unit, {
  int days = 30,
  DateTime? registered,
}) => PantryItem(
  pantryItemId: 'item-${_nextId++}',
  productId: productId,
  deliveryId: 'entrega-001',
  type: FoodType.other,
  quantity: quantity,
  unit: unit,
  daysUntilExpiration: days,
  deviceId: 'device-test',
  localTimestamp: registered ?? today,
);

Recipe recipe(List<RecipeIngredient> ingredients) => Recipe(
  name: 'Prueba',
  image: '',
  minutes: 10,
  servings: 2,
  kcalPerServing: 100,
  ingredients: ingredients,
  steps: const [],
);

bool matches(String ingredient, FoodUnit ingredientUnit, PantryItem pantry) =>
    ingredientMatches(RecipeIngredient(ingredient, 1, ingredientUnit), pantry);

void main() {
  group('normalizeName', () {
    test('lowercases, removes accents and collapses spaces', () {
      expect(normalizeName('  Atún   en LATA '), 'atun en lata');
      expect(normalizeName('Plátano'), 'platano');
      expect(normalizeName('Piña'), 'pina');
      final combiningAccent = String.fromCharCode(0x301);
      expect(normalizeName('Pla${combiningAccent}tano'), 'platano');
    });

    test('treats slugs and punctuation as spaces', () {
      expect(normalizeName('leche_entera'), 'leche entera');
      expect(normalizeName('arroz-1kg'), 'arroz 1kg');
    });

    test('drops plurals conservatively, per word', () {
      expect(normalizeName('Lentejas'), 'lenteja');
      expect(normalizeName('Jitomates'), 'jitomate');
      expect(normalizeName('Frijoles'), 'frijol');
      expect(normalizeName('Limones'), 'limon');
      expect(normalizeName('Frijoles negros'), 'frijol negro');
      expect(normalizeName('Leches enteras'), 'leche entera');
    });

    test('keeps short words and words that are not plurals', () {
      expect(normalizeName('Pan de caja'), 'pan de caja');
      expect(normalizeName('Arroz'), 'arroz');
      expect(normalizeName('Chips'), 'chips');
      expect(normalizeName('más'), 'mas');
    });
  });

  group('ingredientMatches', () {
    test('ignores accents, case and plurals', () {
      expect(
        matches(
          'Atún en lata',
          FoodUnit.can,
          item('atun en lata', 3, FoodUnit.can),
        ),
        isTrue,
      );
      expect(
        matches('Frijol', FoodUnit.kg, item('Frijoles', 2, FoodUnit.kg)),
        isTrue,
      );
      expect(
        matches('Plátano', FoodUnit.piece, item('PLATANOS', 8, FoodUnit.piece)),
        isTrue,
      );
      expect(
        matches('Chile', FoodUnit.kg, item('Chiles', 1, FoodUnit.kg)),
        isTrue,
      );
      expect(
        matches('Nuez', FoodUnit.kg, item('Nueces', 1, FoodUnit.kg)),
        isTrue,
      );
    });

    test('matches when one name starts the other by whole words', () {
      expect(
        matches('Leche', FoodUnit.l, item('Leche entera', 2, FoodUnit.l)),
        isTrue,
      );
      expect(
        matches('Leche entera', FoodUnit.l, item('leche', 2, FoodUnit.l)),
        isTrue,
      );
      expect(
        matches(
          'Leche entera',
          FoodUnit.l,
          item('leche_entera', 2, FoodUnit.l),
        ),
        isTrue,
      );
      expect(
        matches('Leche', FoodUnit.kg, item('Lechuga', 1, FoodUnit.kg)),
        isFalse,
      );
      expect(
        matches(
          'Leche entera',
          FoodUnit.l,
          item('Leche deslactosada', 1, FoodUnit.l),
        ),
        isFalse,
      );
      expect(
        matches('Arroz', FoodUnit.kg, item('Avena', 1, FoodUnit.kg)),
        isFalse,
      );
    });

    test('converts kg/g and L/ml', () {
      expect(
        matches('Lenteja', FoodUnit.kg, item('Lenteja', 500, FoodUnit.g)),
        isTrue,
      );
      expect(
        matches('Lenteja', FoodUnit.g, item('Lenteja', 1, FoodUnit.kg)),
        isTrue,
      );
      expect(
        matches(
          'Aceite vegetal',
          FoodUnit.l,
          item('Aceite vegetal', 900, FoodUnit.ml),
        ),
        isTrue,
      );
      expect(
        matches('Leche', FoodUnit.kg, item('Leche', 1, FoodUnit.l)),
        isFalse,
      );
    });

    test('count units only match the same unit', () {
      expect(
        matches(
          'Atún en lata',
          FoodUnit.can,
          item('Atún en lata', 2, FoodUnit.can),
        ),
        isTrue,
      );
      expect(
        matches(
          'Atún en lata',
          FoodUnit.can,
          item('Atún en lata', 2, FoodUnit.piece),
        ),
        isFalse,
      );
      expect(
        matches(
          'Pan de caja',
          FoodUnit.piece,
          item('Pan de caja', 1, FoodUnit.pack),
        ),
        isFalse,
      );
      expect(
        matches(
          'Pan de caja',
          FoodUnit.piece,
          item('Pan de caja', 1, FoodUnit.kg),
        ),
        isFalse,
      );
    });
  });

  group('convertQuantity', () {
    test('converts within mass and volume', () {
      expect(convertQuantity(0.25, FoodUnit.kg, FoodUnit.g), 250);
      expect(convertQuantity(500, FoodUnit.g, FoodUnit.kg), 0.5);
      expect(convertQuantity(0.05, FoodUnit.l, FoodUnit.ml), closeTo(50, 1e-9));
      expect(convertQuantity(250, FoodUnit.ml, FoodUnit.l), 0.25);
      expect(convertQuantity(3, FoodUnit.can, FoodUnit.can), 3);
    });

    test('returns null between different kinds of units', () {
      expect(convertQuantity(1, FoodUnit.kg, FoodUnit.l), isNull);
      expect(convertQuantity(1, FoodUnit.piece, FoodUnit.can), isNull);
      expect(convertQuantity(1, FoodUnit.pack, FoodUnit.g), isNull);
    });
  });

  group('checkAvailability', () {
    test('adds up matching items in the ingredient unit', () {
      final result = checkAvailability(SampleData.sopaDeLentejas, [
        item('Lenteja', 1, FoodUnit.kg),
        item('Jitomate', 300, FoodUnit.g),
        item('Jitomates', 0.25, FoodUnit.kg),
        item('Zanahoria', 0.1, FoodUnit.kg),
        item('Aceite vegetal', 1, FoodUnit.piece),
        item('Arroz', 2, FoodUnit.kg),
      ], today: today);

      expect(result.map((a) => a.ingredient.name), [
        'Lenteja',
        'Jitomate',
        'Zanahoria',
        'Aceite vegetal',
      ]);
      expect(result.map((a) => a.available), [true, true, false, false]);
      expect(result.map((a) => a.availableQuantity), [1, 0.55, 0.1, 0]);
    });

    test('an exact amount counts as available', () {
      final result = checkAvailability(
        recipe(const [RecipeIngredient('Aceite vegetal', 0.03, FoodUnit.l)]),
        [
          item('Aceite vegetal', 10, FoodUnit.ml),
          item('Aceite', 20, FoodUnit.ml),
        ],
        today: today,
      );

      expect(result.single.available, isTrue);
      expect(result.single.availableQuantity, 0.03);
    });

    test('nothing is available with an empty pantry', () {
      final result = checkAvailability(
        SampleData.avenaConFruta,
        const [],
        today: today,
      );

      expect(result.every((a) => !a.available), isTrue);
      expect(result.every((a) => a.availableQuantity == 0), isTrue);
    });

    test('expired items do not count, items expiring today do', () {
      final result = checkAvailability(
        recipe(const [
          RecipeIngredient('Leche entera', 1, FoodUnit.l),
          RecipeIngredient('Plátano', 2, FoodUnit.piece),
        ]),
        [
          item(
            'Leche entera',
            2,
            FoodUnit.l,
            days: 2,
            registered: DateTime(2026, 9, 18),
          ),
          item('Plátano', 3, FoodUnit.piece, days: 0),
        ],
        today: today,
      );

      expect(result.map((a) => a.available), [false, true]);
      expect(result.first.availableQuantity, 0);
    });
  });

  group('planConsumption', () {
    test('never consumes expired items', () {
      final expired = item(
        'Leche entera',
        1,
        FoodUnit.l,
        days: 1,
        registered: DateTime(2026, 9, 18),
      );
      final fresh = item('Leche entera', 1, FoodUnit.l, days: 5);

      final plan = planConsumption(
        recipe(const [RecipeIngredient('Leche entera', 0.5, FoodUnit.l)]),
        [expired, fresh],
        today: today,
      );

      expect(plan.single.item, same(fresh));
    });

    test('takes first from the item that expires sooner', () {
      final later = item('Leche entera', 1, FoodUnit.l, days: 10);
      final sooner = item('Leche', 1, FoodUnit.l, days: 2);

      final plan = planConsumption(
        recipe(const [RecipeIngredient('Leche entera', 0.5, FoodUnit.l)]),
        [later, sooner],
        today: today,
      );

      expect(plan, hasLength(1));
      expect(plan.single.item, same(sooner));
      expect(plan.single.amount, 0.5);
    });

    test('uses the days left today, not the days at registration', () {
      final old = item(
        'Jitomate',
        1,
        FoodUnit.kg,
        days: 10,
        registered: DateTime(2026, 9, 13),
      );
      final recent = item('Jitomate', 1, FoodUnit.kg, days: 5);

      final plan = planConsumption(
        recipe(const [RecipeIngredient('Jitomate', 0.2, FoodUnit.kg)]),
        [recent, old],
        today: today,
      );

      expect(plan.single.item, same(old));
    });

    test('splits an ingredient across items converting units', () {
      final grams = item('Jitomate', 200, FoodUnit.g, days: 2);
      final kilos = item('Jitomates', 1, FoodUnit.kg, days: 6);

      final plan = planConsumption(
        recipe(const [RecipeIngredient('Jitomate', 0.5, FoodUnit.kg)]),
        [kilos, grams],
        today: today,
      );

      expect(plan.map((c) => c.item), [same(grams), same(kilos)]);
      expect(plan.map((c) => c.amount), [200, 0.3]);
    });

    test('never takes more than what is left', () {
      final little = item('Frijol', 0.2, FoodUnit.kg);

      final plan = planConsumption(SampleData.frijolesDeLaOlla, [
        little,
      ], today: today);

      expect(plan.single.amount, 0.2);
    });

    test('merges ingredients that use the same item without exceeding it', () {
      final tomato = item('Jitomate', 0.5, FoodUnit.kg);

      final plan = planConsumption(
        recipe(const [
          RecipeIngredient('Jitomate', 0.3, FoodUnit.kg),
          RecipeIngredient('Jitomates', 400, FoodUnit.g),
        ]),
        [tomato],
        today: today,
      );

      expect(plan, hasLength(1));
      expect(plan.single.item, same(tomato));
      expect(plan.single.amount, 0.5);
    });

    test('rounds amounts to 3 decimals', () {
      final plan = planConsumption(
        recipe(const [RecipeIngredient('Arroz', 0.3333333, FoodUnit.kg)]),
        [item('Arroz', 1, FoodUnit.kg)],
        today: today,
      );

      expect(plan.single.amount, 0.333);
    });

    test('skips ingredients that are not in the pantry', () {
      final oats = item('Avena', 1, FoodUnit.kg);
      final canned = item('Leche entera', 2, FoodUnit.can);

      final plan = planConsumption(SampleData.avenaConFruta, [
        oats,
        canned,
      ], today: today);

      expect(plan, hasLength(1));
      expect(plan.single.item, same(oats));
      expect(plan.single.amount, 0.15);
      expect(
        planConsumption(SampleData.avenaConFruta, const [], today: today),
        isEmpty,
      );
    });

    test('every amount is positive and within the item quantity', () {
      final pantry = [
        item('Lenteja', 0.1, FoodUnit.kg, days: 1),
        item('Lentejas', 1000, FoodUnit.g, days: 90),
        item('Jitomate', 0.3, FoodUnit.kg, days: 3),
        item('Jitomate', 0.1, FoodUnit.kg, days: 1),
        item('Zanahoria', 3.5, FoodUnit.kg, days: 12),
        item('Aceite vegetal', 40, FoodUnit.ml, days: 150),
        item('Aceite', 1, FoodUnit.l, days: 200),
      ];

      final plan = planConsumption(
        SampleData.sopaDeLentejas,
        pantry,
        today: today,
      );

      expect(plan, hasLength(7));
      for (final (:item, :amount) in plan) {
        expect(amount, greaterThan(0));
        expect(amount, lessThanOrEqualTo(item.quantity));
      }
      final byId = {for (final c in plan) c.item.pantryItemId: c.amount};
      expect(byId[pantry[0].pantryItemId], 0.1);
      expect(byId[pantry[1].pantryItemId], 150);
      expect(byId[pantry[3].pantryItemId], 0.1);
      expect(byId[pantry[2].pantryItemId], 0.3);
      expect(byId[pantry[4].pantryItemId], 0.3);
      expect(byId[pantry[5].pantryItemId], 40);
      expect(byId[pantry[6].pantryItemId], 0.01);
    });
  });
}
