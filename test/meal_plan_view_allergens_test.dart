import 'package:bank_storage_app/data/models/family.dart';
import 'package:bank_storage_app/data/models/member.dart';
import 'package:bank_storage_app/data/models/pantry_item.dart' as data;
import 'package:bank_storage_app/domain/models/meal_plan.dart';
import 'package:bank_storage_app/ui/models/recipe.dart' as ui;
import 'package:bank_storage_app/ui/screens/meal_plan/meal_plan_screen.dart';
import 'package:bank_storage_app/ui/theme/app_assets.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/meal_plan_harness.dart';

// El plan de #43 (sugerido, guardar, guardado) con el filtro de alergias de
// #42: lo que se sugiere y se guarda nunca lleva un alérgeno del hogar.

ui.Recipe recipe(String id, String name, List<String> ingredients) => ui.Recipe(
  id: id,
  signature: 'sig-$id',
  name: name,
  image: AppImages.sopaDeLentejas,
  minutes: 20,
  servings: 4,
  kcalPerServing: 200,
  ingredients: [
    for (final ingredient in ingredients)
      ui.RecipeIngredient(ingredient, 0.1, data.FoodUnit.kg),
  ],
  steps: const ['Cocer'],
);

data.PantryItem item(String productId) => data.PantryItem(
  pantryItemId: 'item-$productId',
  productId: productId,
  deliveryId: 'entrega-001',
  type: data.FoodType.other,
  quantity: 5,
  unit: data.FoodUnit.kg,
  daysUntilExpiration: 30,
  deviceId: 'device-test',
  localTimestamp: DateTime.now(),
);

Member member({List<Allergy>? allergies}) => Member(
  memberId: 'm1',
  name: 'Ana',
  memberType: MemberType.adult,
  createdAt: DateTime(2026, 9, 21),
  allergies: allergies,
);

final withMilk = recipe('r-leche', 'Arroz con leche', [
  'Arroz',
  'Leche entera',
]);
final plain = recipe('r-arroz', 'Arroz solo', ['Arroz']);

Future<List<MealPlan>> pump(
  WidgetTester tester, {
  required List<Member> members,
  required List<ui.Recipe> catalog,
  Stream<SavedPlans>? plans,
}) async {
  tester.view.physicalSize = const Size(900, 9000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final saved = <MealPlan>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: MealPlanHarness(
          familyId: 'famA',
          pantry: Stream.value([item('Arroz'), item('Leche entera')]),
          members: Stream.value(members),
          catalog: Stream.value(catalog),
          family: Stream<Family?>.value(null),
          plans: plans,
          onSave: (plan) async => saved.add(plan),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return saved;
}

Future<void> tapSave(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Guardar este plan'));
  await tester.tap(find.text('Guardar este plan'));
  await tester.pumpAndSettle();
}

void main() {
  group('the suggested plan', () {
    testWidgets('has no recipe with an allergen of the household', (
      tester,
    ) async {
      await pump(
        tester,
        members: [
          member(allergies: [Allergy.dairy]),
        ],
        catalog: [withMilk, plain],
      );

      expect(find.text('Arroz con leche'), findsNothing);
      expect(find.text('Arroz solo'), findsWidgets);
    });

    testWidgets('keeps the recipe when nobody has that allergy', (
      tester,
    ) async {
      await pump(
        tester,
        members: [
          member(allergies: [Allergy.peanut]),
        ],
        catalog: [withMilk, plain],
      );

      expect(find.text('Arroz con leche'), findsWidgets);
    });

    testWidgets(
      '"Guardar este plan" does not store a recipe with an allergen',
      (tester) async {
        final saved = await pump(
          tester,
          members: [
            member(allergies: [Allergy.dairy]),
          ],
          catalog: [withMilk, plain],
        );

        await tapSave(tester);

        expect(saved, hasLength(1));
        expect(saved.single.meals, isNotEmpty);
        expect(
          saved.single.meals.map((meal) => meal.recipeId),
          everyElement('r-arroz'),
        );
      },
    );

    testWidgets('without that allergy the saved plan can use the recipe', (
      tester,
    ) async {
      final saved = await pump(
        tester,
        members: [member()],
        catalog: [withMilk, plain],
      );

      await tapSave(tester);

      expect(
        saved.single.meals.map((meal) => meal.recipeId),
        contains('r-leche'),
      );
    });

    testWidgets('if every recipe has an allergen there is no plan to save', (
      tester,
    ) async {
      final saved = await pump(
        tester,
        members: [
          member(allergies: [Allergy.dairy]),
        ],
        catalog: [withMilk],
      );

      expect(
        find.text('Ninguna receta es segura para tu familia'),
        findsOneWidget,
      );
      expect(find.text('Guardar este plan'), findsNothing);
      expect(find.text('Arroz con leche'), findsNothing);
      expect(saved, isEmpty);
    });
  });

  group('a plan the family already saved', () {
    SavedPlans savedWith(String recipeId) {
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day);
      return [
        (
          plan: MealPlan(
            id: 'p1',
            familyId: 'famA',
            dateRangeStart: start,
            dateRangeEnd: start.add(const Duration(days: 7)),
            meals: [MealPlanMeal(date: start, recipeId: recipeId, servings: 2)],
          ),
          pendingSync: false,
        ),
      ];
    }

    testWidgets('is shown as it was saved, with the allergy warning', (
      tester,
    ) async {
      await pump(
        tester,
        members: [
          member(allergies: [Allergy.dairy]),
        ],
        catalog: [withMilk, plain],
        plans: Stream.value(savedWith('r-leche')),
      );

      // No se cambia en silencio lo que la familia guardó: se ve con su aviso.
      expect(find.text('Arroz con leche'), findsOneWidget);
      expect(find.text('Guardar este plan'), findsNothing);
    });
  });
}
