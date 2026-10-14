import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/pantry_item.dart';
import 'package:bank_storage_app/data/repositories/meal_plan_repository.dart';
import 'package:bank_storage_app/domain/meal_plan_edits.dart';
import 'package:bank_storage_app/domain/models/meal_plan.dart';
import 'package:bank_storage_app/ui/models/recipe.dart';
import 'package:bank_storage_app/ui/sample_data.dart';

/// Cualquier lectura o escritura falla: sirve para saber que el repositorio
/// rechazó el plan antes de tocar Firestore.
class _NoFirestore extends Fake implements FirebaseFirestore {}

DateTime day(int offset) => DateTime(2026, 10, 14 + offset);

MealPlanMeal meal(int offset, String recipeId, {double servings = 2}) =>
    MealPlanMeal(date: day(offset), recipeId: recipeId, servings: servings);

/// Miércoles 14 a martes 20 de octubre; el viernes 16 está libre.
MealPlan plan() => MealPlan(
  id: 'plan1',
  familyId: 'famA',
  dateRangeStart: day(0),
  dateRangeEnd: day(7),
  meals: [
    meal(0, 'rec_0'),
    meal(1, 'rec_1'),
    meal(3, 'rec_3'),
    meal(4, 'rec_4'),
    meal(5, 'rec_5'),
    meal(6, 'rec_6'),
  ],
);

PantryItem item(String name, double quantity, FoodUnit unit, int days) =>
    PantryItem(
      pantryItemId: 'item-$name',
      productId: name,
      deliveryId: 'entrega-001',
      type: FoodType.other,
      quantity: quantity,
      unit: unit,
      daysUntilExpiration: days,
      deviceId: 'device-test',
      localTimestamp: day(0),
    );

void main() {
  group('MealPlanEdits.withRecipe', () {
    test('changes the recipe and servings of one day only', () {
      final original = plan();

      final changed = MealPlanEdits.withRecipe(
        original,
        day(1).add(const Duration(hours: 13)),
        recipeId: 'rec_new',
        servings: 3.5,
      );

      expect(changed.id, 'plan1');
      expect(changed.familyId, 'famA');
      expect(changed.dateRangeStart, day(0));
      expect(changed.dateRangeEnd, day(7));
      expect(changed.meals.map((m) => m.recipeId), [
        'rec_0',
        'rec_new',
        'rec_3',
        'rec_4',
        'rec_5',
        'rec_6',
      ]);
      expect(changed.meals[1].date, day(1));
      expect(changed.meals[1].servings, 3.5);
      // El plan de antes no cambia.
      expect(original.meals[1].recipeId, 'rec_1');
    });

    test('fills a free day in date order', () {
      final changed = MealPlanEdits.withRecipe(
        plan(),
        day(2),
        recipeId: 'rec_2',
        servings: 2,
      );

      expect(changed.meals, hasLength(7));
      expect(changed.meals.map((m) => m.date), [
        for (var i = 0; i < 7; i++) day(i),
      ]);
      expect(MealPlanEdits.mealOn(changed, day(2))?.recipeId, 'rec_2');
    });

    test('refuses days outside the plan', () {
      for (final date in [day(-1), day(7)]) {
        expect(
          () => MealPlanEdits.withRecipe(
            plan(),
            date,
            recipeId: 'rec_x',
            servings: 2,
          ),
          throwsArgumentError,
          reason: '$date',
        );
      }
    });

    test('refuses a meal that cannot be saved', () {
      expect(
        () =>
            MealPlanEdits.withRecipe(plan(), day(2), recipeId: '', servings: 2),
        throwsArgumentError,
      );
      expect(
        () => MealPlanEdits.withRecipe(
          plan(),
          day(2),
          recipeId: 'rec_x',
          servings: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('MealPlanEdits.withoutMeal', () {
    test('leaves the day free and the rest as they were', () {
      final changed = MealPlanEdits.withoutMeal(plan(), day(3));

      expect(changed.id, 'plan1');
      expect(changed.meals.map((m) => m.recipeId), [
        'rec_0',
        'rec_1',
        'rec_4',
        'rec_5',
        'rec_6',
      ]);
      expect(MealPlanEdits.mealOn(changed, day(3)), isNull);
      expect(MealPlanEdits.problem(changed), isNull);
    });

    test('a free day stays free', () {
      final changed = MealPlanEdits.withoutMeal(plan(), day(2));

      expect(changed.meals.map((m) => m.recipeId), [
        for (final meal in plan().meals) meal.recipeId,
      ]);
    });

    test('freeing every day leaves an empty plan that can be saved', () {
      var changed = plan();
      for (var i = 0; i < 7; i++) {
        changed = MealPlanEdits.withoutMeal(changed, day(i));
      }

      expect(changed.meals, isEmpty);
      expect(MealPlanEdits.problem(changed), isNull);
    });
  });

  group('planOptionsFor', () {
    test('ranks the recipes as the plan does, counting from today', () {
      final pantry = [
        item('Leche entera', 1, FoodUnit.l, 1),
        item('Plátano', 4, FoodUnit.piece, 3),
        item('Lenteja', 1, FoodUnit.kg, 5),
      ];
      final recipes = [
        SampleData.sopaDeLentejas,
        SampleData.avenaConFruta,
        SampleData.frijolesDeLaOlla,
      ];

      final today = planOptionsFor(recipes, pantry, day(0), today: day(0));
      // Lo que caduca se cuenta desde hoy: el viernes 16 se ve igual.
      final friday = planOptionsFor(recipes, pantry, day(2), today: day(0));

      expect(today.map((e) => e.recipe.name), [
        'Avena con fruta',
        'Sopa de lentejas',
        'Frijoles de la olla',
      ]);
      expect(
        today.first.reason,
        startsWith('Usa Leche entera (caduca mañana)'),
      );
      expect(friday.map((e) => e.recipe), today.map((e) => e.recipe));
      expect(friday.map((e) => e.reason), today.map((e) => e.reason));
      expect(friday.map((e) => e.date), everyElement(day(2)));
    });
  });

  group('MealPlanRepository.updateMeals', () {
    final repository = MealPlanRepository(_NoFirestore());

    test('refuses a plan without id before writing', () async {
      final noId = MealPlan(
        id: '',
        familyId: 'famA',
        dateRangeStart: day(0),
        dateRangeEnd: day(7),
        meals: const [],
      );

      await expectLater(repository.updateMeals(noId), throwsArgumentError);
    });

    test('refuses meals that cannot be saved before writing', () async {
      final zero = MealPlan(
        id: 'plan1',
        familyId: 'famA',
        dateRangeStart: day(0),
        dateRangeEnd: day(7),
        meals: [meal(0, 'rec_0', servings: 0)],
      );
      final tooMany = MealPlan(
        id: 'plan1',
        familyId: 'famA',
        dateRangeStart: day(0),
        dateRangeEnd: day(14),
        meals: [for (var i = 0; i < 15; i++) meal(i % 14, 'rec_$i')],
      );

      await expectLater(repository.updateMeals(zero), throwsArgumentError);
      await expectLater(repository.updateMeals(tooMany), throwsArgumentError);
    });

    test('a valid plan goes on to Firestore', () async {
      await expectLater(
        repository.updateMeals(plan()),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });
}
