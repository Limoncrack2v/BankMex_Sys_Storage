import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/pantry_item.dart';
import 'package:bank_storage_app/ui/models/expiration_urgency.dart';
import 'package:bank_storage_app/ui/models/recipe.dart';
import 'package:bank_storage_app/ui/sample_data.dart';

/// Lunes.
final today = DateTime(2026, 9, 21);
var _nextId = 0;

PantryItem item(
  String productId,
  double quantity,
  FoodUnit unit, {
  int days = 30,
}) => PantryItem(
  pantryItemId: 'item-${_nextId++}',
  productId: productId,
  deliveryId: 'entrega-001',
  type: FoodType.other,
  quantity: quantity,
  unit: unit,
  daysUntilExpiration: days,
  deviceId: 'device-test',
  localTimestamp: today,
);

Recipe recipe(List<RecipeIngredient> ingredients) => Recipe(
  name: 'Prueba',
  image: '',
  minutes: 10,
  servings: 2,
  kcalPerServing: 100,
  ingredients: ingredients,
  steps: const ['Paso 1.'],
);

MealPlanEntry entry(Recipe recipe, {DateTime? date}) => MealPlanEntry(
  date: date ?? today,
  day: 'Lun',
  recipe: recipe,
  reason: '',
  urgency: ExpirationUrgency.fresh,
);

PlanLeftover of(List<PlanLeftover> leftovers, PantryItem item) =>
    leftovers.singleWhere((leftover) => identical(leftover.item, item));

void main() {
  final rice = recipe(const [RecipeIngredient('Arroz', 1, FoodUnit.kg)]);

  group('planLeftovers', () {
    test('an item no recipe uses is untouched', () {
      final beans = item('Frijol', 2, FoodUnit.kg);

      final leftovers = planLeftovers([entry(rice)], [beans], today: today);

      expect(leftovers.single.status, LeftoverStatus.untouched);
      expect(leftovers.single.used, 0);
      expect(leftovers.single.remaining, 2);
    });

    test('an item the plan takes a part of is partly used', () {
      final arroz = item('Arroz', 2.5, FoodUnit.kg);

      final leftover = planLeftovers(
        [entry(rice)],
        [arroz],
        today: today,
      ).single;

      expect(leftover.status, LeftoverStatus.partlyUsed);
      expect(leftover.used, 1);
      expect(leftover.remaining, 1.5);
    });

    test('an item the plan takes all of is used up', () {
      final arroz = item('Arroz', 1, FoodUnit.kg);

      final leftover = planLeftovers(
        [entry(rice)],
        [arroz],
        today: today,
      ).single;

      expect(leftover.status, LeftoverStatus.usedUp);
      expect(leftover.used, 1);
      expect(leftover.remaining, 0);
    });

    test('quantities are reported in the unit of the pantry item', () {
      final grams = recipe(const [RecipeIngredient('Arroz', 500, FoodUnit.g)]);
      final kilos = item('Arroz', 2, FoodUnit.kg);
      final bulk = item('Frijol', 1500, FoodUnit.g);
      final beans = recipe(const [
        RecipeIngredient('Frijol', 0.5, FoodUnit.kg),
      ]);

      final leftovers = planLeftovers(
        [entry(grams), entry(beans)],
        [kilos, bulk],
        today: today,
      );

      expect(of(leftovers, kilos).used, 0.5);
      expect(of(leftovers, kilos).remaining, 1.5);
      expect(of(leftovers, bulk).used, 500);
      expect(of(leftovers, bulk).remaining, 1000);
    });

    test('units that do not convert are not mixed', () {
      final tins = item('Arroz', 3, FoodUnit.can);

      final leftover = planLeftovers(
        [entry(rice)],
        [tins],
        today: today,
      ).single;

      expect(leftover.status, LeftoverStatus.untouched);
    });

    test('a recipe that repeats uses what is left when its turn comes', () {
      final arroz = item('Arroz', 2.5, FoodUnit.kg);

      final leftover = planLeftovers(
        [entry(rice), entry(rice), entry(rice)],
        [arroz],
        today: today,
      ).single;

      // 1 kg + 1 kg + los 0.5 kg que quedaban.
      expect(leftover.used, 2.5);
      expect(leftover.remaining, 0);
      expect(leftover.status, LeftoverStatus.usedUp);
    });

    test('a repeat after the item ran out uses nothing', () {
      final arroz = item('Arroz', 2, FoodUnit.kg);

      final leftover = planLeftovers(
        [for (var day = 0; day < 7; day++) entry(rice)],
        [arroz],
        today: today,
      ).single;

      expect(leftover.used, 2);
      expect(leftover.remaining, 0);
    });

    test('a repeat moves on to the next lot once the first one runs out', () {
      final soon = item('Arroz', 1, FoodUnit.kg, days: 2);
      final later = item('Arroz', 3, FoodUnit.kg, days: 30);

      final leftovers = planLeftovers(
        [entry(rice), entry(rice)],
        [soon, later],
        today: today,
      );

      expect(of(leftovers, soon).status, LeftoverStatus.usedUp);
      expect(of(leftovers, later).used, 1);
      expect(of(leftovers, later).remaining, 2);
    });

    test('never goes negative however many times the plan asks', () {
      final pantry = [
        item('Arroz', 0.3, FoodUnit.kg),
        item('Arroz', 0.25, FoodUnit.kg, days: 5),
      ];

      final leftovers = planLeftovers(
        [for (var day = 0; day < 7; day++) entry(rice)],
        pantry,
        today: today,
      );

      for (final leftover in leftovers) {
        expect(leftover.remaining, greaterThanOrEqualTo(0));
        expect(leftover.used, lessThanOrEqualTo(leftover.item.quantity));
      }
      expect(
        leftovers.map((l) => l.status),
        everyElement(LeftoverStatus.usedUp),
      );
    });

    test('floating point residue does not leave a sliver', () {
      final tenth = recipe(const [RecipeIngredient('Arroz', 0.1, FoodUnit.kg)]);
      final arroz = item('Arroz', 0.3, FoodUnit.kg);

      final leftover = planLeftovers(
        [entry(tenth), entry(tenth), entry(tenth)],
        [arroz],
        today: today,
      ).single;

      expect(leftover.remaining, 0);
      expect(leftover.status, LeftoverStatus.usedUp);
    });

    test('takes from the item that expires first', () {
      final soon = item('Arroz', 1, FoodUnit.kg, days: 2);
      final later = item('Arroz', 3, FoodUnit.kg, days: 30);
      final twoKilos = recipe(const [
        RecipeIngredient('Arroz', 2, FoodUnit.kg),
      ]);

      final leftovers = planLeftovers(
        [entry(twoKilos)],
        [later, soon],
        today: today,
      );

      expect(of(leftovers, soon).status, LeftoverStatus.usedUp);
      expect(of(leftovers, later).used, 1);
      expect(of(leftovers, later).remaining, 2);
    });

    test('two ingredients on the same item add up', () {
      final pair = recipe(const [
        RecipeIngredient('Arroz', 0.5, FoodUnit.kg),
        RecipeIngredient('Arroz', 300, FoodUnit.g),
      ]);
      final arroz = item('Arroz', 1, FoodUnit.kg);

      final leftover = planLeftovers(
        [entry(pair)],
        [arroz],
        today: today,
      ).single;

      expect(leftover.used, 0.8);
      expect(leftover.remaining, 0.2);
    });

    test('expired items and empty items are left out', () {
      final fresh = item('Frijol', 1, FoodUnit.kg);
      final pantry = [
        item('Arroz', 5, FoodUnit.kg, days: -1),
        item('Lenteja', 0, FoodUnit.kg),
        fresh,
      ];

      final leftovers = planLeftovers([entry(rice)], pantry, today: today);

      expect(leftovers.map((l) => l.item), [fresh]);
    });

    test('an item that expires today still counts', () {
      final arroz = item('Arroz', 2, FoodUnit.kg, days: 0);

      final leftover = planLeftovers(
        [entry(rice)],
        [arroz],
        today: today,
      ).single;

      expect(leftover.used, 1);
    });

    test('an empty pantry has no leftovers', () {
      expect(planLeftovers([entry(rice)], const [], today: today), isEmpty);
    });

    test('an empty plan leaves everything untouched', () {
      final pantry = [
        item('Arroz', 2, FoodUnit.kg),
        item('Frijol', 1, FoodUnit.kg),
      ];

      final leftovers = planLeftovers(const [], pantry, today: today);

      expect(leftovers, hasLength(2));
      expect(
        leftovers.map((l) => l.status),
        everyElement(LeftoverStatus.untouched),
      );
      expect(leftovers.map((l) => l.remaining), [2, 1]);
    });

    test('lists what expires first, then by name', () {
      final b = item('Frijol', 1, FoodUnit.kg, days: 10);
      final a = item('Avena', 1, FoodUnit.kg, days: 10);
      final urgent = item('Zanahoria', 1, FoodUnit.kg, days: 1);

      final leftovers = planLeftovers(const [], [b, a, urgent], today: today);

      expect(leftovers.map((l) => l.item), [urgent, a, b]);
    });

    test('does not change the pantry it is given', () {
      final arroz = item('Arroz', 2, FoodUnit.kg);

      planLeftovers([entry(rice), entry(rice)], [arroz], today: today);

      expect(arroz.quantity, 2);
    });

    test('for a single recipe it matches planConsumption', () {
      final pantry = [
        item('Arroz', 0.4, FoodUnit.kg, days: 3),
        item('Arroz', 3, FoodUnit.kg),
        item('Frijol', 2, FoodUnit.kg),
      ];
      final stew = recipe(const [
        RecipeIngredient('Arroz', 600, FoodUnit.g),
        RecipeIngredient('Frijol', 0.25, FoodUnit.kg),
      ]);

      final leftovers = planLeftovers([entry(stew)], pantry, today: today);

      final consumption = planConsumption(stew, pantry, today: today);
      for (final (:item, :amount) in consumption) {
        expect(of(leftovers, item).used, closeTo(amount, 1e-9));
      }
      expect(leftovers.where((l) => l.used > 0).length, consumption.length);
    });

    test(
      'keeps used + remaining equal to the quantity over a real weekly plan',
      () {
        final pantry = [
          item('Leche entera', 1, FoodUnit.l, days: 1),
          item('Jamón de pavo', 0.5, FoodUnit.kg, days: 3),
          item('Jitomate', 1, FoodUnit.kg, days: 5),
          item('Arroz', 2, FoodUnit.kg, days: 200),
          item('Frijol', 1, FoodUnit.kg, days: 90),
          item('Avena', 0.2, FoodUnit.kg, days: 60),
        ];
        final plan = buildMealPlan(SampleData.recipes, pantry, today: today);

        final leftovers = planLeftovers(plan, pantry, today: today);

        expect(leftovers, hasLength(pantry.length));
        for (final leftover in leftovers) {
          expect(leftover.remaining, greaterThanOrEqualTo(0));
          expect(
            leftover.used + leftover.remaining,
            closeTo(leftover.item.quantity, 1e-9),
            reason: leftover.item.productId,
          );
        }
        // Avena con fruta sale dos veces (0.15 kg cada vez): la segunda solo
        // quedan 0.05 kg y se acaban.
        expect(of(leftovers, pantry.last).status, LeftoverStatus.usedUp);
      },
    );

    test('una receta de un día posterior a la caducidad ya no usa el producto',
        () {
      final leche = item('Leche entera', 1, FoodUnit.l, days: 2);
      final conLeche = recipe(const [
        RecipeIngredient('Leche entera', 0.4, FoodUnit.l),
      ]);

      final leftover = planLeftovers(
        [
          entry(conLeche),
          entry(conLeche, date: today.add(const Duration(days: 2))),
          // Ya caducó: no se cocina con ella aunque la receta la pida.
          entry(conLeche, date: today.add(const Duration(days: 3))),
        ],
        [leche],
        today: today,
      ).single;

      expect(leftover.used, closeTo(0.8, 1e-9));
      expect(leftover.remaining, closeTo(0.2, 1e-9));
      expect(leftover.status, LeftoverStatus.partlyUsed);
    });

    test('concuerda con las tarjetas de un plan de 14 días', () {
      final conLeche = recipe(const [
        RecipeIngredient('Leche entera', 0.5, FoodUnit.l),
      ]);
      final conArroz = recipe(const [
        RecipeIngredient('Arroz', 0.2, FoodUnit.kg),
      ]);
      final leche = item('Leche entera', 3, FoodUnit.l, days: 3);
      final arroz = item('Arroz', 5, FoodUnit.kg, days: 200);
      final pantry = [leche, arroz];

      final plan = buildMealPlan(
        [conLeche, conArroz],
        pantry,
        today: today,
        days: 14,
      );
      final leftovers = planLeftovers(plan, pantry, today: today);

      // La leche solo se nombra mientras sirve (hoy y pasado mañana, que le
      // queda 1 día); las demás veces que sale la receta ya caducó.
      final milkCards = plan.where((e) => e.reason.contains('Leche'));
      expect(milkCards.map((e) => e.date.day), [21, 23]);
      expect(plan.where((e) => e.recipe == conLeche), hasLength(7));
      expect(of(leftovers, leche).used, closeTo(0.5 * milkCards.length, 1e-9));
      expect(of(leftovers, leche).remaining, closeTo(2, 1e-9));
      // El arroz alcanza para los 7 días que sale la receta.
      final riceCards = plan.where((e) => e.recipe == conArroz).length;
      expect(of(leftovers, arroz).used, closeTo(0.2 * riceCards, 1e-9));
    });
  });
}
