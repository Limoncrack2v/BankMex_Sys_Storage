import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/domain/meal_plan_edits.dart';
import 'package:bank_storage_app/domain/models/meal_plan.dart';

/// Miércoles a media tarde: el plan empieza a medianoche de este día.
final today = DateTime(2026, 10, 14, 15, 30);

DateTime day(int offset) => DateTime(2026, 10, 14 + offset);

MealPlanMeal meal(
  DateTime date, {
  String recipeId = 'rec_a',
  double servings = 3.4,
}) => MealPlanMeal(date: date, recipeId: recipeId, servings: servings);

MealPlan planFrom(
  DateTime start, {
  String id = 'plan',
  int days = 7,
  List<MealPlanMeal> meals = const [],
}) => MealPlan(
  id: id,
  familyId: 'famA',
  dateRangeStart: start,
  dateRangeEnd: DateTime(start.year, start.month, start.day + days),
  meals: meals,
);

void main() {
  group('MealPlanEdits.create', () {
    test('starts at midnight of today and ends the day after the last', () {
      final plan = MealPlanEdits.create(
        familyId: 'famA',
        start: today,
        days: 7,
        meals: [
          for (var i = 0; i < 7; i++)
            meal(day(i).add(const Duration(hours: 12)), recipeId: 'rec_$i'),
        ],
      );

      expect(plan.id, isEmpty);
      expect(plan.familyId, 'famA');
      expect(plan.dateRangeStart, day(0));
      expect(plan.dateRangeEnd, day(7));
      expect(plan.meals.map((m) => m.date), [
        for (var i = 0; i < 7; i++) day(i),
      ]);
      expect(plan.meals.map((m) => m.recipeId), [
        for (var i = 0; i < 7; i++) 'rec_$i',
      ]);
      expect(plan.meals.map((m) => m.servings), everyElement(3.4));
      expect(MealPlanEdits.problem(plan), isNull);
    });

    test('a 14 day plan can cross into the next month', () {
      final start = DateTime(2026, 10, 25);
      final plan = MealPlanEdits.create(
        familyId: 'famA',
        start: start,
        days: 14,
        meals: [
          for (var i = 0; i < 14; i++)
            meal(DateTime(2026, 10, 25 + i), recipeId: 'rec_$i'),
        ],
      );

      expect(plan.dateRangeEnd, DateTime(2026, 11, 8));
      expect(plan.meals, hasLength(14));
      expect(plan.meals.last.date, DateTime(2026, 11, 7));
    });

    test('sorts the meals, keeps the first of each day and drops the days '
        'outside the plan', () {
      final plan = MealPlanEdits.create(
        familyId: 'famA',
        start: today,
        days: 7,
        meals: [
          meal(day(2), recipeId: 'rec_c'),
          meal(day(0), recipeId: 'rec_a'),
          meal(day(2).add(const Duration(hours: 8)), recipeId: 'rec_repeat'),
          meal(day(-1), recipeId: 'rec_yesterday'),
          meal(day(7), recipeId: 'rec_after'),
        ],
      );

      expect(plan.meals.map((m) => m.recipeId), ['rec_a', 'rec_c']);
      expect(plan.meals.map((m) => m.date), [day(0), day(2)]);
    });

    test('refuses meals that cannot be saved', () {
      MealPlan create(MealPlanMeal meal) => MealPlanEdits.create(
        familyId: 'famA',
        start: today,
        days: 7,
        meals: [meal],
      );

      // Las recetas de ejemplo sin id y un hogar sin porciones.
      expect(() => create(meal(day(0), recipeId: '')), throwsArgumentError);
      expect(() => create(meal(day(0), servings: 0)), throwsArgumentError);
    });

    test('refuses plans shorter than 1 day or longer than 14', () {
      MealPlan create(int days) => MealPlanEdits.create(
        familyId: 'famA',
        start: today,
        days: days,
        meals: const [],
      );

      expect(() => create(0), throwsArgumentError);
      expect(() => create(15), throwsArgumentError);
      expect(create(1).dateRangeEnd, day(1));
      expect(create(14).meals, isEmpty);
    });
  });

  group('MealPlanEdits.current', () {
    test('is the plan that covers today, its last day included', () {
      final plan = planFrom(day(-6));

      expect(MealPlanEdits.current([plan], today), same(plan));
      expect(MealPlanEdits.current([plan], day(-6)), same(plan));
    });

    test('a plan that already ended or starts tomorrow is not current', () {
      final ended = planFrom(day(-7));
      final tomorrow = planFrom(day(1));

      expect(MealPlanEdits.current([ended, tomorrow], today), isNull);
      expect(MealPlanEdits.current(const [], today), isNull);
    });

    test('the plan that starts last wins; on the same day, the larger id', () {
      final older = planFrom(day(-3), id: 'zzz');
      final newer = planFrom(day(-1), id: 'aaa');
      final twin = planFrom(day(-1), id: 'bbb');

      expect(MealPlanEdits.current([older, newer], today), same(newer));
      expect(MealPlanEdits.current([newer, older], today), same(newer));
      expect(MealPlanEdits.current([twin, newer], today), same(twin));
      expect(MealPlanEdits.current([newer, twin], today), same(twin));
    });
  });

  test('mealOn finds the meal of a day whatever its hour', () {
    final plan = planFrom(
      day(0),
      meals: [
        meal(day(0), recipeId: 'rec_a'),
        meal(day(2), recipeId: 'rec_c'),
      ],
    );

    expect(MealPlanEdits.mealOn(plan, today)?.recipeId, 'rec_a');
    expect(MealPlanEdits.mealOn(plan, day(2))?.recipeId, 'rec_c');
    expect(MealPlanEdits.mealOn(plan, day(1)), isNull);
  });

  group('MealPlanEdits.problem', () {
    MealPlan withMeal(MealPlanMeal meal) => planFrom(day(0), meals: [meal]);

    test('a full 14 day plan is valid', () {
      final plan = planFrom(
        day(0),
        days: 14,
        meals: [for (var i = 0; i < 14; i++) meal(day(i), recipeId: 'rec_$i')],
      );

      expect(MealPlanEdits.problem(plan), isNull);
    });

    test('at most 14 meals', () {
      final plan = planFrom(
        day(0),
        days: 14,
        meals: [for (var i = 0; i < 15; i++) meal(day(i % 14))],
      );

      expect(MealPlanEdits.problem(plan), contains('14 comidas'));
    });

    test('each meal inside the range, its end included', () {
      expect(MealPlanEdits.problem(withMeal(meal(day(7)))), isNull);
      expect(
        MealPlanEdits.problem(withMeal(meal(day(8)))),
        'Comida 1: La fecha de la comida está fuera del rango del plan',
      );
      expect(MealPlanEdits.problem(withMeal(meal(day(-1)))), isNotNull);
    });

    test('the id of a recipe document', () {
      expect(
        MealPlanEdits.problem(withMeal(meal(day(0), recipeId: ''))),
        isNotNull,
      );
      expect(
        MealPlanEdits.problem(withMeal(meal(day(0), recipeId: 'recipes/a'))),
        isNotNull,
      );
      expect(
        MealPlanEdits.problem(withMeal(meal(day(0), recipeId: 'a' * 128))),
        isNull,
      );
      expect(
        MealPlanEdits.problem(withMeal(meal(day(0), recipeId: 'a' * 129))),
        isNotNull,
      );
    });

    test('servings over 0 and up to 100', () {
      for (final servings in [0.0, -1.0, 100.5, double.nan]) {
        expect(
          MealPlanEdits.problem(withMeal(meal(day(0), servings: servings))),
          isNotNull,
          reason: '$servings',
        );
      }
      expect(
        MealPlanEdits.problem(withMeal(meal(day(0), servings: 100))),
        isNull,
      );
      expect(
        MealPlanEdits.problem(withMeal(meal(day(0), servings: 0.2))),
        isNull,
      );
    });

    test('a range that ends before it starts', () {
      final plan = MealPlan(
        id: 'plan',
        familyId: 'famA',
        dateRangeStart: day(1),
        dateRangeEnd: day(0),
        meals: const [],
      );

      expect(MealPlanEdits.problem(plan), isNotNull);
    });
  });
}
