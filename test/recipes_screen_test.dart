import 'package:bank_storage_app/data/models/member.dart';
import 'package:bank_storage_app/data/models/pantry_item.dart';
import 'package:bank_storage_app/ui/models/recipe.dart';
import 'package:bank_storage_app/ui/screens/recipes/recipes_screen.dart';
import 'package:bank_storage_app/ui/theme/app_assets.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PantryItem _item(String productId, double quantity, FoodUnit unit) =>
    PantryItem(
      pantryItemId: 'item-$productId',
      productId: productId,
      deliveryId: 'entrega-001',
      type: FoodType.other,
      quantity: quantity,
      unit: unit,
      daysUntilExpiration: 30,
      deviceId: 'device-test',
      localTimestamp: DateTime.now(),
    );

Recipe _recipe(String name, String ingredient, double kg) => Recipe(
  name: name,
  image: AppImages.sopaDeLentejas,
  minutes: 40,
  servings: 4,
  kcalPerServing: 200,
  ingredients: [RecipeIngredient(ingredient, kg, FoodUnit.kg)],
  steps: const ['Cocer'],
);

Future<void> _pump(
  WidgetTester tester, {
  required Stream<List<PantryItem>> pantry,
  required List<Recipe> catalog,
  List<Member> members = const [],
}) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: RecipesScreen(
          familyId: 'famA',
          pantry: pantry,
          members: Stream.value(members),
          catalog: Stream.value(catalog),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  final catalog = [
    _recipe('Arroz solo', 'Arroz', 0.5),
    _recipe('Frijoles solos', 'Frijol', 1),
  ];

  testWidgets('"Con lo que tengo" shows the recipes the pantry covers', (
    tester,
  ) async {
    await _pump(
      tester,
      pantry: Stream.value([_item('Arroz', 1, FoodUnit.kg)]),
      catalog: catalog,
    );

    expect(find.text('Arroz solo'), findsOneWidget);
    expect(find.text('Frijoles solos'), findsNothing);
  });

  testWidgets('it uses the pantry it is given, not another family\'s', (
    tester,
  ) async {
    await _pump(
      tester,
      pantry: Stream.value([_item('Frijol', 2, FoodUnit.kg)]),
      catalog: catalog,
    );

    expect(find.text('Frijoles solos'), findsOneWidget);
    expect(find.text('Arroz solo'), findsNothing);
  });

  testWidgets('a pantry with too little of an ingredient does not cover it', (
    tester,
  ) async {
    await _pump(
      tester,
      pantry: Stream.value([_item('Arroz', 0.2, FoodUnit.kg)]),
      catalog: catalog,
    );

    expect(find.text('Arroz solo'), findsNothing);
  });

  testWidgets('"Todas" shows the whole catalog', (tester) async {
    await _pump(tester, pantry: Stream.value(const []), catalog: catalog);
    await tester.tap(find.text('Todas'));
    await tester.pump();

    expect(find.text('Arroz solo'), findsOneWidget);
    expect(find.text('Frijoles solos'), findsOneWidget);
  });

  testWidgets('an empty catalog shows an empty state, not sample recipes', (
    tester,
  ) async {
    await _pump(tester, pantry: Stream.value(const []), catalog: const []);

    expect(find.text('Aún no hay recetas'), findsOneWidget);
    expect(find.text('Arroz con atún'), findsNothing);
  });
}
