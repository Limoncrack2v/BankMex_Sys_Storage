import 'package:bank_storage_app/data/repositories/meal_plan_repository.dart';
import 'package:bank_storage_app/domain/meal_plan_generator.dart';
import 'package:bank_storage_app/domain/models/family_profile.dart';
import 'package:bank_storage_app/domain/models/meal_plan.dart';
import 'package:bank_storage_app/domain/models/pantry_item.dart';
import 'package:bank_storage_app/domain/models/recipe.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

// Los límites de cada comida y del plan son los de validMeal / validMeals en
// firestore.rules (ver test/meal_plan_rules_consistency_test.dart y
// test_emulator/rules_meal_plans_test.dart).

final _start = DateTime(2026, 10, 12);
final _end = DateTime(2026, 10, 19);

MealPlanMeal meal({
  DateTime? date,
  String recipeId = 'receta1',
  double servings = 3.5,
}) =>
    MealPlanMeal(date: date ?? _start, recipeId: recipeId, servings: servings);

MealPlan planOf(List<MealPlanMeal> meals, {DateTime? start, DateTime? end}) =>
    MealPlan(
      id: '',
      familyId: 'famA',
      dateRangeStart: start ?? _start,
      dateRangeEnd: end ?? _end,
      meals: meals,
    );

String? check(MealPlanMeal meal) =>
    meal.validate(rangeStart: _start, rangeEnd: _end);

/// Un firestore que falla con cualquier uso: si create tocara la base antes de
/// validar, la prueba vería un NoSuchMethodError en lugar de un ArgumentError.
class _NoFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('MealPlanMeal.validate', () {
    test('una comida normal es válida', () {
      expect(check(meal()), isNull);
    });

    test('la fecha puede ser exactamente el inicio o el fin del rango', () {
      expect(check(meal(date: _start)), isNull);
      expect(check(meal(date: _end)), isNull);
    });

    test('un milisegundo fuera del rango se rechaza', () {
      expect(
        check(meal(date: _start.subtract(const Duration(milliseconds: 1)))),
        isNotNull,
      );
      expect(
        check(meal(date: _end.add(const Duration(milliseconds: 1)))),
        isNotNull,
      );
    });

    test('recipeId vacío se rechaza', () {
      expect(check(meal(recipeId: '')), isNotNull);
    });

    test('recipeId de 128 caracteres es válido y de 129 se rechaza', () {
      expect(check(meal(recipeId: 'a' * 128)), isNull);
      expect(check(meal(recipeId: 'a' * 129)), isNotNull);
    });

    test('recipeId cuenta caracteres y no unidades UTF-16', () {
      // Cada emoji ocupa dos unidades UTF-16 y un solo carácter.
      expect(check(meal(recipeId: '🍲' * 128)), isNull);
      expect(check(meal(recipeId: '🍲' * 129)), isNotNull);
    });

    test('recipeId con "/" se rechaza', () {
      expect(check(meal(recipeId: 'recipes/r1')), isNotNull);
    });

    test('las porciones deben ser mayores a 0', () {
      expect(check(meal(servings: 0)), isNotNull);
      expect(check(meal(servings: -1)), isNotNull);
      expect(check(meal(servings: 0.25)), isNull);
    });

    test('las porciones llegan a 100 y no más', () {
      expect(check(meal(servings: 100)), isNull);
      expect(check(meal(servings: 100.01)), isNotNull);
    });

    test('porciones que no son un número finito se rechazan', () {
      expect(check(meal(servings: double.nan)), isNotNull);
      expect(check(meal(servings: double.infinity)), isNotNull);
    });
  });

  group('MealPlan.validate', () {
    test('un plan sin comidas es válido', () {
      expect(planOf(const []).validate(), isNull);
    });

    test('un plan de 7 comidas es válido', () {
      final meals = [
        for (var i = 0; i < 7; i++)
          meal(date: DateTime(2026, 10, 12 + i), recipeId: 'r$i'),
      ];
      expect(planOf(meals).validate(), isNull);
    });

    test('el tope es MealPlanLength.biweekly', () {
      expect(MealPlan.maxMeals, 14);
    });

    test('un plan con el máximo de comidas es válido', () {
      final meals = List.filled(MealPlan.maxMeals, meal());
      expect(planOf(meals).validate(), isNull);
    });

    test('un plan con una comida más que el máximo se rechaza', () {
      final meals = List.filled(MealPlan.maxMeals + 1, meal());
      expect(planOf(meals).validate(), isNotNull);
    });

    test('el rango no puede terminar antes de empezar', () {
      expect(planOf(const [], start: _end, end: _start).validate(), isNotNull);
    });

    test('una comida inválida al final del plan lo invalida', () {
      final meals = [
        ...List.filled(MealPlan.maxMeals - 1, meal()),
        meal(servings: 0),
      ];
      final error = planOf(meals).validate();
      expect(error, isNotNull);
      expect(error, startsWith('Comida ${MealPlan.maxMeals}:'));
    });

    test('una comida fuera del rango del plan lo invalida', () {
      final afterEnd = meal(date: _end.add(const Duration(days: 1)));
      expect(planOf([meal(), afterEnd]).validate(), startsWith('Comida 2:'));
    });
  });

  group('MealPlanRepository.create', () {
    final repository = MealPlanRepository(_NoFirestore());

    test('rechaza un plan con una comida inválida antes de escribir', () {
      expect(
        repository.create(planOf([meal(), meal(servings: 0)])),
        throwsArgumentError,
      );
      expect(
        repository.create(planOf([meal(recipeId: '')])),
        throwsArgumentError,
      );
      expect(
        repository.create(
          planOf([meal(date: _end.add(const Duration(days: 1)))]),
        ),
        throwsArgumentError,
      );
    });

    test('rechaza un plan con más del máximo de comidas', () {
      final meals = List.filled(MealPlan.maxMeals + 1, meal());
      expect(repository.create(planOf(meals)), throwsArgumentError);
    });

    test('el mensaje dice qué comida falla', () async {
      await expectLater(
        repository.create(planOf([meal(), meal(recipeId: '')])),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('Comida 2'),
          ),
        ),
      );
    });

    test('un plan válido llega a la base de datos', () {
      // El firestore de mentira falla con cualquier uso: pasar la validación
      // es llegar a él.
      expect(
        repository.create(planOf([meal()])),
        throwsA(isNot(isA<ArgumentError>())),
      );
    });
  });

  group('MealPlanGenerator', () {
    final now = DateTime(2026, 10, 12, 15, 30);
    const family = FamilyProfile(
      id: 'fam',
      authUid: 'fake',
      adults: 2,
      children: [],
      dietaryRestrictions: [],
    );
    final rice = PantryItem(
      id: 'arroz',
      familyId: 'fam',
      productId: 'arroz',
      name: 'arroz',
      quantity: 100000,
      unit: 'g',
      expirationDate: DateTime(2027, 12, 31),
      category: 'test',
      originalQuantity: 100000,
      consumedQuantity: 0,
      status: PantryItemStatus.available,
    );
    const riceRecipe = Recipe(
      id: 'arroz_blanco',
      name: 'Arroz blanco',
      ingredients: [
        RecipeIngredient(productName: 'arroz', quantity: 50, unit: 'g'),
      ],
      steps: ['x'],
      prepTimeMinutes: 1,
      caloriesPerServing: 1,
      status: RecipeStatus.approved,
    );

    MealPlanGeneration generate(int days, {DateTime? startDate}) =>
        MealPlanGenerator.generateMealPlan(
          family: family,
          pantryItems: [rice],
          recipes: [riceRecipe],
          days: days,
          startDate: startDate,
          now: now,
        );

    test('un plan de 14 días tiene 14 comidas y es válido', () {
      final generated = generate(MealPlan.maxMeals);

      expect(generated.plan.meals, hasLength(MealPlan.maxMeals));
      expect(generated.plan.validate(), isNull);
    });

    test('un plan de 7 días es válido', () {
      expect(generate(7).plan.validate(), isNull);
    });

    test('la última comida cae un día antes del fin del rango', () {
      final plan = generate(7).plan;

      expect(plan.dateRangeStart, DateTime(2026, 10, 12));
      expect(plan.dateRangeEnd, DateTime(2026, 10, 19));
      expect(plan.meals.last.date, DateTime(2026, 10, 18));
    });

    test('con una hora en startDate el rango empieza a medianoche', () {
      // La primera comida cae a medianoche: si el rango conservara la hora, esa
      // comida quedaría antes de su inicio y las reglas rechazarían el plan.
      final plan = generate(3, startDate: DateTime(2026, 10, 12, 15, 30)).plan;

      expect(plan.dateRangeStart, DateTime(2026, 10, 12));
      expect(plan.validate(), isNull);
    });

    test('no genera más días que el máximo de comidas', () {
      expect(() => generate(MealPlan.maxMeals + 1), throwsArgumentError);
      expect(() => generate(100), throwsArgumentError);
    });

    test('no genera un plan de 0 días ni de días negativos', () {
      expect(() => generate(0), throwsArgumentError);
      expect(() => generate(-1), throwsArgumentError);
    });
  });
}
