import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/delivery.dart';
import 'package:bank_storage_app/domain/meal_plan_length.dart';
import 'package:bank_storage_app/domain/models/meal_plan.dart';

// Los límites de las comidas de un plan están escritos en dos lugares que no
// pueden importarse: los modelos de Dart (MealPlanMeal.validate y
// MealPlan.validate) y validMeal / validMeals en firestore.rules. Estas
// pruebas leen el archivo y fallan cuando las copias se separan. Las reglas se
// prueban contra el emulador en test_emulator/rules_meal_plans_test.dart.
void main() {
  final rules = File('firestore.rules').readAsStringSync();

  String functionBody(String name) {
    final start = rules.indexOf('function $name(');
    if (start < 0) throw StateError('no se encontró la función $name');
    final next = rules.indexOf(RegExp(r'\n    (//|function )'), start);
    return rules.substring(start, next == -1 ? rules.length : next);
  }

  List<String> fieldList(String source, String method) {
    final match = RegExp('$method\\(\\[([^\\]]*)\\]\\)').firstMatch(source);
    expect(match, isNotNull, reason: 'no se encontró $method([...])');
    return RegExp("'([A-Za-z]+)'")
        .allMatches(match!.group(1)!)
        .map((m) => m.group(1)!)
        .toList();
  }

  final validMeal = functionBody('validMeal');
  final validMeals = functionBody('validMeals');
  final validMealPlan = functionBody('validMealPlan');

  group('límites de las comidas en firestore.rules', () {
    test('el tope de comidas es MealPlan.maxMeals', () {
      final cap = RegExp(r'meals is list && n <= (\d+)').firstMatch(validMeals);

      expect(int.parse(cap!.group(1)!), MealPlan.maxMeals);
    });

    test('MealPlan.maxMeals es el plan quincenal de MealPlanLength', () {
      // Una comida por día; el plan más largo es el quincenal.
      expect(MealPlan.maxMeals, MealPlanLength.biweekly);
      expect(MealPlan.maxMeals, greaterThanOrEqualTo(MealPlanLength.weekly));
    });

    test('cada posición hasta maxMeals se revisa, y ninguna más', () {
      final checked = RegExp(r'validMeal\(meals\[(\d+)\], start, end\)')
          .allMatches(validMeals)
          .map((m) => int.parse(m.group(1)!))
          .toList();

      expect(checked, [for (var i = 0; i < MealPlan.maxMeals; i++) i]);
    });

    test('validMealPlan revisa las comidas con el rango del plan', () {
      expect(
        validMealPlan,
        contains(
          'validMeals(data.meals, data.dateRangeStart, data.dateRangeEnd)',
        ),
      );
    });

    test('el largo del recipeId es MealPlanMeal.maxRecipeIdLength', () {
      final match = RegExp(r"recipeId\.matches\('\[\^/\]\{1,(\d+)\}'\)")
          .firstMatch(validMeal);

      expect(int.parse(match!.group(1)!), MealPlanMeal.maxRecipeIdLength);
    });

    test('el tope de porciones es MealPlanMeal.maxServings', () {
      final match = RegExp(r'meal\.servings > 0 && meal\.servings <= (\d+)')
          .firstMatch(validMeal);

      expect(int.parse(match!.group(1)!), MealPlanMeal.maxServings);
    });

    test('el tope de porciones es el de paquetes de una entrega', () {
      expect(MealPlanMeal.maxServings, Delivery.maxPackages);
    });

    test('los campos de la comida son los que escribe MealPlanMeal.toMap', () {
      final meal = MealPlanMeal(
        date: DateTime(2026, 10, 12),
        recipeId: 'receta1',
        servings: 1,
      );
      final fields = meal.toMap().keys;

      expect(fieldList(validMeal, 'hasOnly'), unorderedEquals(fields));
      for (final field in fields) {
        expect(
          validMeal,
          contains('meal.$field'),
          reason: 'validMeal no lee $field',
        );
      }
    });

    test('los campos del plan son los que escribe MealPlan.toMap', () {
      final plan = MealPlan(
        id: '',
        familyId: 'famA',
        dateRangeStart: DateTime(2026, 10, 12),
        dateRangeEnd: DateTime(2026, 10, 19),
        meals: const [],
      );
      final fields = plan.toMap().keys;

      expect(fieldList(validMealPlan, 'hasOnly'), unorderedEquals(fields));
      expect(fieldList(validMealPlan, 'hasAll'), unorderedEquals(fields));
    });
  });
}
