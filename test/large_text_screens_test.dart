import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/pantry_item.dart';
import 'package:bank_storage_app/domain/models/meal_plan.dart';
import 'package:bank_storage_app/ui/models/recipe.dart';
import 'package:bank_storage_app/ui/sample_data.dart';
import 'package:bank_storage_app/ui/screens/meal_plan/leftover_ingredients_section.dart';
import 'package:bank_storage_app/ui/screens/meal_plan/meal_plan_screen.dart';
import 'package:bank_storage_app/ui/screens/meal_plan/saved_meal_plan_view.dart';
import 'package:bank_storage_app/ui/screens/staff/register_account_sheet.dart';

import 'helpers/large_text.dart';

final _today = DateTime(2026, 9, 21);

PantryItem _item(String name, double quantity, FoodUnit unit, int days) =>
    PantryItem(
      pantryItemId: 'item-$name',
      productId: name,
      deliveryId: 'entrega-001',
      type: FoodType.dairy,
      quantity: quantity,
      unit: unit,
      daysUntilExpiration: days,
      deviceId: 'device-test',
      localTimestamp: _today,
    );

void main() {
  setUpAll(loadAppFonts);

  group('Registrar cuenta: tipo de cuenta', () {
    testWidgets('a 360 con letra normal los tres van en un renglón', (
      tester,
    ) async {
      await pumpWithTextScale(
        tester,
        const RegisterAccountSheet(),
        textScale: 1,
      );

      final familia = tester.getTopLeft(find.text('Familia'));
      final nutriologo = tester.getTopLeft(find.text('Nutriólogo'));
      expect(nutriologo.dy, closeTo(familia.dy, 0.5));
      expect(nutriologo.dx, greaterThan(familia.dx));
      expectNoBrokenWords(tester);
    });

    testWidgets('a 360 con letra grande (1.3x) no parte «Nutriólogo»', (
      tester,
    ) async {
      await pumpWithTextScale(
        tester,
        const RegisterAccountSheet(),
        textScale: 1.3,
      );

      expectNoBrokenWords(tester);
      expect(tester.takeException(), isNull);
      // No caben en un renglón: van uno debajo de otro.
      expect(
        tester.getTopLeft(find.text('Nutriólogo')).dy,
        greaterThan(tester.getBottomLeft(find.text('Familia')).dy),
      );
    });
  });

  group('Lo que te sobra con letra grande (1.3x) a 360', () {
    testWidgets('un nombre largo no se parte y la píldora baja', (
      tester,
    ) async {
      final milk = _item(
        'Leche semidescremada deslactosada light',
        1,
        FoodUnit.l,
        10,
      );
      await pumpWithTextScale(
        tester,
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            LeftoverIngredientsSection(
              leftovers: [
                PlanLeftover(item: milk, used: 0.25, remaining: 0.75),
              ],
              today: _today,
            ),
          ],
        ),
        textScale: 1.3,
      );

      expectNoBrokenWords(tester);
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(find.text('Caduca en 10 días')).dy,
        greaterThan(
          tester
              .getBottomLeft(
                find.text('Leche semidescremada deslactosada light'),
              )
              .dy,
        ),
      );
    });

    testWidgets('un nombre corto deja la píldora a la derecha', (tester) async {
      await pumpWithTextScale(
        tester,
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            LeftoverIngredientsSection(
              leftovers: [
                PlanLeftover(
                  item: _item('Arroz', 2, FoodUnit.kg, 3),
                  used: 0.5,
                  remaining: 1.5,
                ),
              ],
              today: _today,
            ),
          ],
        ),
        textScale: 1.3,
      );

      expectNoBrokenWords(tester);
      final pill = tester.getTopLeft(find.text('Caduca en 3 días'));
      final name = tester.getTopLeft(find.text('Arroz'));
      expect(pill.dy, lessThan(tester.getBottomLeft(find.text('Arroz')).dy));
      expect(pill.dx, greaterThan(name.dx));
    });
  });

  group('Plan de comidas a 360', () {
    // A 1.3 "ultrapasteurizada" ya no cabe junto a la píldora "Urgente".
    final milk = _item('Leche entera ultrapasteurizada', 2, FoodUnit.l, 1);
    final reason = find.textContaining('Usa Leche entera ultrapasteurizada');
    final pill = find.text('Urgente');

    void expectPillBelowReason(WidgetTester tester) {
      expectNoBrokenWords(tester);
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(pill.first).dy,
        greaterThan(tester.getBottomLeft(reason.first).dy),
      );
    }

    Widget saved() => SavedPlanView(
      plan: MealPlan(
        id: 'plan1',
        familyId: 'famA',
        dateRangeStart: _today,
        dateRangeEnd: DateTime(2026, 9, 28),
        meals: [
          MealPlanMeal(date: _today, recipeId: 'rec_avena_fruta', servings: 2),
        ],
      ),
      pendingSync: false,
      recipes: SampleData.recipes,
      members: const [],
      pantry: [milk],
      today: _today,
      onOpenRecipe: (_) {},
      onSaveMeals: (_) async {},
      onDelete: () async {},
    );

    testWidgets('con letra grande (1.3x) el plan sugerido no parte el motivo', (
      tester,
    ) async {
      await pumpWithTextScale(
        tester,
        SuggestedPlanView(
          familyId: 'famA',
          recipes: SampleData.recipes,
          members: const [],
          pantry: [milk],
          nextDelivery: null,
          onOpenRecipe: (_) {},
          onSave: null,
          clock: () => _today,
        ),
        textScale: 1.3,
      );

      expectPillBelowReason(tester);
    });

    testWidgets('con letra grande (1.3x) el guardado tampoco y la acción va '
        'al final', (tester) async {
      await pumpWithTextScale(tester, saved(), textScale: 1.3);

      expectPillBelowReason(tester);
      expect(
        tester.getTopLeft(find.text('Cambiar')).dy,
        greaterThan(tester.getBottomLeft(pill).dy),
      );
    });

    testWidgets('con letra normal la píldora sigue a la derecha', (
      tester,
    ) async {
      await pumpWithTextScale(tester, saved(), textScale: 1);

      expectNoBrokenWords(tester);
      final topLeft = tester.getTopLeft(pill);
      expect(topLeft.dy, lessThan(tester.getBottomLeft(reason).dy));
      expect(topLeft.dx, greaterThan(tester.getTopRight(reason).dx));
    });
  });
}
