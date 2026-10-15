import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/member.dart';
import 'package:bank_storage_app/data/models/pantry_item.dart';
import 'package:bank_storage_app/domain/meal_plan_edits.dart';
import 'package:bank_storage_app/domain/models/meal_plan.dart';
import 'package:bank_storage_app/ui/models/expiration_urgency.dart';
import 'package:bank_storage_app/ui/models/recipe.dart';
import 'package:bank_storage_app/ui/sample_data.dart';
import 'package:bank_storage_app/ui/screens/meal_plan/meal_plan_saving.dart';

/// Miércoles.
final today = DateTime(2026, 10, 14);

PantryItem item(
  String name,
  double quantity,
  FoodUnit unit,
  int days, {
  String? id,
}) => PantryItem(
  pantryItemId: id ?? 'item-$name',
  productId: name,
  deliveryId: 'entrega-001',
  type: FoodType.other,
  quantity: quantity,
  unit: unit,
  daysUntilExpiration: days,
  deviceId: 'device-test',
  localTimestamp: today,
);

Member member(
  String name, {
  MemberType type = MemberType.adult,
  int? age,
  double? weightKg,
}) => Member(
  memberId: name,
  name: name,
  memberType: type,
  createdAt: DateTime(2026, 9, 1),
  age: age,
  weightKg: weightKg,
);

const oatmeal = SampleData.avenaConFruta;

/// Medio litro de leche y nada más.
const withMilk = Recipe(
  id: 'rec_con_leche',
  name: 'Con leche',
  image: '',
  minutes: 10,
  servings: 2,
  kcalPerServing: 100,
  ingredients: [RecipeIngredient('Leche entera', 0.5, FoodUnit.l)],
  steps: ['Servir.'],
);

DateTime day(int offset) => DateTime(2026, 10, 14 + offset);

void main() {
  group('planEntryFor', () {
    test('for today it is the card the suggested plan shows', () {
      final pantry = [item('Leche entera', 1, FoodUnit.l, 1)];
      final suggested = buildMealPlan([oatmeal], pantry, today: today).first;

      final saved = planEntryFor(oatmeal, today, pantry);

      expect(saved.date, today);
      expect(saved.day, 'Mié');
      expect(saved.reason, suggested.reason);
      expect(saved.urgency, suggested.urgency);
    });

    test('counts the days left from the date of the card, like the '
        'suggested plan', () {
      final pantry = [item('Leche entera', 1, FoodUnit.l, 5)];

      final friday = planEntryFor(oatmeal, DateTime(2026, 10, 16, 18), pantry);

      expect(friday.date, DateTime(2026, 10, 16));
      expect(friday.day, 'Vie');
      expect(friday.reason, startsWith('Usa Leche entera (caduca en 3 días)'));
      expect(friday.urgency, ExpirationUrgency.urgent);
    });

    test('a later day has the reason the suggested plan shows', () {
      final pantry = [item('Leche entera', 1, FoodUnit.l, 1)];
      final suggested = buildMealPlan([oatmeal], pantry, today: today);

      final saturday = planEntryFor(
        oatmeal,
        DateTime(2026, 10, 17),
        pantry,
        earlier: suggested.take(3).toList(),
      );

      expect(saturday.reason, suggested[3].reason);
      // La leche caducó el jueves.
      expect(saturday.reason, 'Te faltan 3 ingredientes');
      expect(saturday.urgency, ExpirationUrgency.fresh);
    });

    test('what an earlier day uses up is missing the next day', () {
      final pantry = [item('Leche entera', 0.5, FoodUnit.l, 6)];
      final wednesday = planEntryFor(withMilk, today, pantry);

      final thursday = planEntryFor(
        withMilk,
        day(1),
        pantry,
        earlier: [wednesday],
      );

      expect(wednesday.reason, 'Usa Leche entera (caduca en 6 días)');
      expect(thursday.reason, 'Te falta 1 ingrediente');
      expect(thursday.urgency, ExpirationUrgency.fresh);
    });

    test('a free day in between uses nothing', () {
      final pantry = [item('Leche entera', 1, FoodUnit.l, 6)];
      final wednesday = planEntryFor(withMilk, today, pantry);

      // El jueves está libre: el viernes aún queda medio litro.
      final friday = planEntryFor(
        withMilk,
        day(2),
        pantry,
        earlier: [wednesday],
      );
      final saturday = planEntryFor(
        withMilk,
        day(3),
        pantry,
        earlier: [wednesday, friday],
      );

      expect(friday.reason, 'Usa Leche entera (caduca en 4 días)');
      expect(friday.urgency, ExpirationUrgency.soon);
      expect(saturday.reason, 'Te falta 1 ingrediente');
    });

    test('an earlier day cooks on its own date, with the lot that expires '
        'first', () {
      // Dos lotes de leche: el miércoles usa el que caduca mañana, así que el
      // viernes queda completo el otro.
      final pantry = [
        item('Leche entera', 0.5, FoodUnit.l, 1, id: 'leche-1'),
        item('Leche entera', 0.5, FoodUnit.l, 10, id: 'leche-2'),
      ];
      final wednesday = planEntryFor(withMilk, today, pantry);

      final friday = planEntryFor(
        withMilk,
        day(2),
        pantry,
        earlier: [wednesday],
      );

      expect(wednesday.reason, 'Usa Leche entera (caduca mañana)');
      expect(friday.reason, 'Con productos de tu despensa');
    });

    test('the cards of that day and later ones do not count', () {
      final pantry = [item('Leche entera', 0.5, FoodUnit.l, 6)];
      final notEarlier = [
        planEntryFor(withMilk, day(1), pantry),
        planEntryFor(withMilk, day(2), pantry),
      ];

      final thursday = planEntryFor(
        withMilk,
        day(1),
        pantry,
        earlier: notEarlier,
      );

      expect(thursday.reason, 'Usa Leche entera (caduca en 5 días)');
    });
  });

  test('a plan saved right away has the cards and leftovers of the '
      'suggestion', () {
    final members = [member('Ana'), member('Luis')];
    // El jitomate y el frijol se acaban a media quincena.
    final pantry = [
      item('Leche entera', 1, FoodUnit.l, 3),
      item('Plátano', 4, FoodUnit.piece, 4),
      item('Lenteja', 0.25, FoodUnit.kg, 6),
      item('Jitomate', 0.3, FoodUnit.kg, 5),
      item('Arroz', 2, FoodUnit.kg, 200),
      item('Frijol', 0.2, FoodUnit.kg, 90),
    ];
    final recipes = [
      for (final recipe in SampleData.recipes)
        scaledForHousehold(recipe, members),
    ];
    final suggested = buildMealPlan(recipes, pantry, today: today, days: 14);
    final plan = MealPlanEdits.create(
      familyId: 'famA',
      start: today,
      days: 14,
      meals: [
        for (final entry in suggested)
          MealPlanMeal(
            date: entry.date,
            recipeId: entry.recipe.id,
            servings: planServings(members, entry.recipe),
          ),
      ],
    );

    // Como SavedPlanView: cada día con lo que dejan los anteriores.
    final byId = {for (final recipe in recipes) recipe.id: recipe};
    final saved = <MealPlanEntry>[];
    for (final meal in plan.meals) {
      final recipe = byId[meal.recipeId]!;
      saved.add(
        planEntryFor(recipe, meal.date, pantry, earlier: List.of(saved)),
      );
    }

    expect(saved.map((e) => e.date), suggested.map((e) => e.date));
    expect(saved.map((e) => e.reason), suggested.map((e) => e.reason));
    expect(saved.map((e) => e.urgency), suggested.map((e) => e.urgency));
    // Sin lo que usan los días anteriores, alguna tarjeta diría otra cosa.
    final alone = [
      for (final e in suggested) planEntryFor(e.recipe, e.date, pantry).reason,
    ];
    expect(alone, isNot(suggested.map((e) => e.reason).toList()));
    String leftovers(List<MealPlanEntry> entries) => [
      for (final left in planLeftovers(entries, pantry, today: today))
        '${left.item.productId}: ${left.used} / ${left.remaining}',
    ].join('\n');
    expect(leftovers(saved), leftovers(suggested));
  });

  test('planDayLabel abbreviates the day like the plan cards', () {
    expect(planDayLabel(DateTime(2026, 10, 12)), 'Lun');
    expect(planDayLabel(DateTime(2026, 10, 14, 23)), 'Mié');
    expect(planDayLabel(DateTime(2026, 10, 18)), 'Dom');
  });

  group('planServings', () {
    test('is the portions the household eats, rounded to 2 decimals', () {
      final members = [
        member('Ana'),
        member('Luis'),
        member('Sofía', type: MemberType.child, age: 8, weightKg: 26),
      ];

      final servings = planServings(members, oatmeal);

      expect(servings, (householdPortions(members) * 100).round() / 100);
      expect(servings, greaterThan(2));
      expect(servings, lessThan(3));
    });

    test('without members it is the servings of the recipe, never 0', () {
      expect(planServings(const [], oatmeal), oatmeal.servings);
      expect(planServings(const [], oatmeal), greaterThan(0));
    });

    test('never goes over the limit of a meal', () {
      const party = Recipe(
        id: 'rec_party',
        name: 'Para fiesta',
        image: '',
        minutes: 60,
        servings: 150,
        kcalPerServing: 200,
        ingredients: [],
        steps: [],
      );

      expect(planServings(const [], party), MealPlanMeal.maxServings);
    });
  });

  group('planWriteError', () {
    test('a plan deleted on another device says so', () {
      expect(
        planWriteError(
          FirebaseException(plugin: 'cloud_firestore', code: 'not-found'),
          'Intenta de nuevo.',
        ),
        'Este plan ya no existe. Puede que se haya eliminado en otro '
        'dispositivo.',
      );
    });

    test('a plan that cannot be saved gives the reason', () {
      expect(
        planWriteError(
          ArgumentError('La receta es obligatoria'),
          'Intenta de nuevo.',
        ),
        'La receta es obligatoria.',
      );
    });

    test('anything else gives the fallback', () {
      expect(
        planWriteError(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
          'Intenta de nuevo.',
        ),
        'Intenta de nuevo.',
      );
    });
  });

  test('the plan the screen shows can be saved as it is', () {
    final members = [member('Ana'), member('Luis')];
    final pantry = [
      item('Leche entera', 1, FoodUnit.l, 1),
      item('Arroz', 2, FoodUnit.kg, 200),
    ];
    final shown = buildMealPlan(
      [
        for (final recipe in SampleData.recipes)
          scaledForHousehold(recipe, members),
      ],
      pantry,
      today: today.add(const Duration(hours: 9)),
      days: 14,
    );

    final plan = MealPlanEdits.create(
      familyId: 'famA',
      start: today.add(const Duration(hours: 9)),
      days: 14,
      meals: [
        for (final entry in shown)
          MealPlanMeal(
            date: entry.date,
            recipeId: entry.recipe.id,
            servings: planServings(members, entry.recipe),
          ),
      ],
    );

    expect(plan.dateRangeStart, today);
    expect(plan.dateRangeEnd, DateTime(2026, 10, 28));
    expect(plan.meals.map((m) => m.date), [for (final e in shown) e.date]);
    expect(plan.meals.map((m) => m.recipeId), [
      for (final e in shown) e.recipe.id,
    ]);
    expect(plan.meals.map((m) => m.servings), everyElement(2));
    expect(plan.validate(), isNull);
  });
}
