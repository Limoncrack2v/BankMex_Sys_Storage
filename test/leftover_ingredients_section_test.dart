import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/pantry_item.dart';
import 'package:bank_storage_app/ui/models/recipe.dart';
import 'package:bank_storage_app/ui/screens/meal_plan/leftover_ingredients_section.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';

/// Lunes.
final today = DateTime(2026, 9, 21);

PantryItem item(
  String productId,
  double quantity,
  FoodUnit unit, {
  int days = 30,
}) => PantryItem(
  pantryItemId: 'item-$productId',
  productId: productId,
  deliveryId: 'entrega-001',
  type: FoodType.other,
  quantity: quantity,
  unit: unit,
  daysUntilExpiration: days,
  deviceId: 'device-test',
  localTimestamp: today,
);

PlanLeftover leftover(PantryItem item, {double used = 0}) =>
    PlanLeftover(item: item, used: used, remaining: item.quantity - used);

Future<void> pumpSection(WidgetTester tester, List<PlanLeftover> leftovers) =>
    tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: LeftoverIngredientsSection(
              leftovers: leftovers,
              today: today,
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('shows what is left of each item and when it expires', (
    tester,
  ) async {
    final milk = item('Leche entera', 2, FoodUnit.l, days: 1);
    final rice = item('Arroz', 2, FoodUnit.kg, days: 200);

    await pumpSection(tester, [leftover(milk, used: 0.5), leftover(rice)]);

    expect(find.text('Lo que te sobra'), findsOneWidget);
    expect(find.text('Leche entera'), findsOneWidget);
    expect(find.text('Quedan 1.5 L'), findsOneWidget);
    expect(find.text('Caduca mañana'), findsOneWidget);
    expect(find.text('Arroz'), findsOneWidget);
    expect(find.text('Quedan 2 kg'), findsOneWidget);
    expect(find.text('Caduca en 200 días'), findsOneWidget);
  });

  testWidgets('says whether the plan touches an item and how much', (
    tester,
  ) async {
    final milk = item('Leche entera', 2, FoodUnit.l);
    final rice = item('Arroz', 2, FoodUnit.kg);

    await pumpSection(tester, [leftover(milk, used: 0.5), leftover(rice)]);

    expect(find.text('Tu plan usa 0.5 L de 2 L'), findsOneWidget);
    expect(find.text('Tu plan no lo usa'), findsOneWidget);
  });

  testWidgets('says "Queda" for exactly one unit', (tester) async {
    await pumpSection(tester, [
      leftover(item('Arroz', 3, FoodUnit.kg), used: 2),
    ]);

    expect(find.text('Queda 1 kg'), findsOneWidget);
  });

  testWidgets('lists the items the plan uses up in one line, not as cards', (
    tester,
  ) async {
    final rice = item('Arroz', 1, FoodUnit.kg);
    final beans = item('Frijol', 1, FoodUnit.kg);
    final lentils = item('Lenteja', 1, FoodUnit.kg);
    final oats = item('Avena', 1, FoodUnit.kg);

    await pumpSection(tester, [
      leftover(rice, used: 1),
      leftover(beans, used: 1),
      leftover(lentils, used: 1),
      leftover(oats),
    ]);

    expect(
      find.text('El plan usa por completo: Arroz, Frijol y Lenteja.'),
      findsOneWidget,
    );
    expect(find.text('Quedan 1 kg'), findsNothing);
    expect(find.text('Queda 1 kg'), findsOneWidget);
    expect(find.text('Avena'), findsOneWidget);
    expect(find.text('Arroz'), findsNothing);
  });

  testWidgets('when the plan uses everything it says so and lists nothing', (
    tester,
  ) async {
    await pumpSection(tester, [
      leftover(item('Arroz', 1, FoodUnit.kg), used: 1),
      leftover(item('Frijol', 1, FoodUnit.kg), used: 1),
    ]);

    expect(
      find.text('Tu plan usa todo lo que hay en tu despensa.'),
      findsOneWidget,
    );
    expect(find.textContaining('Queda'), findsNothing);
    expect(find.textContaining('El plan usa por completo'), findsNothing);
  });

  testWidgets('when the plan uses nothing it says so and lists everything', (
    tester,
  ) async {
    await pumpSection(tester, [
      leftover(item('Arroz', 1, FoodUnit.kg)),
      leftover(item('Frijol', 2, FoodUnit.kg)),
    ]);

    expect(
      find.text('Tu plan no usa ningún producto de tu despensa.'),
      findsOneWidget,
    );
    expect(find.text('Tu plan no lo usa'), findsNWidgets(2));
  });

  testWidgets('does not say the plan uses nothing when it uses something', (
    tester,
  ) async {
    await pumpSection(tester, [
      leftover(item('Arroz', 2, FoodUnit.kg), used: 1),
      leftover(item('Frijol', 2, FoodUnit.kg)),
    ]);

    expect(find.textContaining('no usa ningún producto'), findsNothing);
  });

  testWidgets('shows nothing for an empty pantry', (tester) async {
    await pumpSection(tester, const []);

    expect(find.byType(Text), findsNothing);
  });
}
