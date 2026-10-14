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

void main() {
  group('planEntryFor', () {
    test('for today it is the card the suggested plan shows', () {
      final pantry = [item('Leche entera', 1, FoodUnit.l, 1)];
      final suggested = buildMealPlan([oatmeal], pantry, today: today).first;

      final saved = planEntryFor(oatmeal, today, pantry, today: today);

      expect(saved.date, today);
      expect(saved.day, 'Mié');
      expect(saved.reason, suggested.reason);
      expect(saved.urgency, suggested.urgency);
    });

    test('counts the days left from today, not from the date of the card', () {
      final pantry = [item('Leche entera', 1, FoodUnit.l, 5)];

      final friday = planEntryFor(
        oatmeal,
        DateTime(2026, 10, 16, 18),
        pantry,
        today: today,
      );

      expect(friday.date, DateTime(2026, 10, 16));
      expect(friday.day, 'Vie');
      expect(friday.reason, startsWith('Usa Leche entera (caduca en 5 días)'));
      expect(friday.urgency, ExpirationUrgency.soon);
    });

    test('a later day has the reason the suggested plan shows', () {
      final pantry = [item('Leche entera', 1, FoodUnit.l, 1)];
      final suggested = buildMealPlan([oatmeal], pantry, today: today);

      final saturday = planEntryFor(
        oatmeal,
        DateTime(2026, 10, 17),
        pantry,
        today: today,
      );

      expect(saturday.reason, suggested[3].reason);
      expect(saturday.reason, startsWith('Usa Leche entera (caduca mañana)'));
      expect(saturday.urgency, ExpirationUrgency.urgent);
    });
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

      expect(planServings(const [], party), MealPlanEdits.maxServings);
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
    expect(MealPlanEdits.problem(plan), isNull);
  });
}
