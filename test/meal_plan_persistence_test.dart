import 'dart:async';

import 'package:bank_storage_app/data/models/family.dart';
import 'package:bank_storage_app/data/models/member.dart';
import 'package:bank_storage_app/data/models/pantry_item.dart' as data;
import 'package:bank_storage_app/domain/models/meal_plan.dart';
import 'package:bank_storage_app/ui/models/meal_plan_record.dart';
import 'package:bank_storage_app/ui/models/recipe.dart' as ui;
import 'package:bank_storage_app/ui/screens/meal_plan/meal_plan_screen.dart';
import 'package:bank_storage_app/ui/theme/app_assets.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ui.Recipe recipe(String id, String name, List<String> ingredients) => ui.Recipe(
  id: id,
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

data.PantryItem pantryItem(String productId, {int days = 30}) =>
    data.PantryItem(
      pantryItemId: 'item-$productId',
      productId: productId,
      deliveryId: 'entrega-001',
      type: data.FoodType.other,
      quantity: 5,
      unit: data.FoodUnit.kg,
      daysUntilExpiration: days,
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

Family family({DateTime? nextDelivery}) => Family(
  familyId: 'famA',
  address: 'Calle 1',
  registrationDate: DateTime(2026, 9, 1),
  authUid: 'famA',
  appliances: const [],
  nextDeliveryDate: nextDelivery,
);

final catalog = [
  recipe('r-arroz', 'Arroz solo', ['Arroz']),
  recipe('r-frijol', 'Frijoles solos', ['Frijol']),
];

/// Lo que guarda y lo que lee la pantalla, para comprobarlo.
class Store {
  Store({this.stored, this.failLoad = false, this.failSave = false});

  MealPlan? stored;
  final bool failLoad;
  final bool failSave;
  final saved = <MealPlan>[];

  Future<MealPlan?> load(String familyId) async {
    if (failLoad) throw StateError('offline');
    return stored;
  }

  /// Como el repositorio: sin id crea un documento (le pone uno), con id lo
  /// reemplaza.
  Future<MealPlan> save(MealPlan plan) async {
    if (failSave) throw StateError('permission-denied');
    saved.add(plan);
    final written = MealPlan(
      id: plan.id.isEmpty ? 'plan-${saved.length}' : plan.id,
      familyId: plan.familyId,
      dateRangeStart: plan.dateRangeStart,
      dateRangeEnd: plan.dateRangeEnd,
      meals: plan.meals,
    );
    stored = written;
    return written;
  }
}

Future<void> pump(
  WidgetTester tester,
  Store store, {
  Stream<List<data.PantryItem>>? pantry,
  List<ui.Recipe>? recipes,
  List<Member> members = const [],
  DateTime? nextDelivery,
}) async {
  tester.view.physicalSize = const Size(900, 9000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: MealPlanScreen(
          key: UniqueKey(),
          familyId: 'famA',
          pantry: pantry ?? Stream.value([pantryItem('Arroz')]),
          members: Stream.value(members),
          catalog: Stream.value(recipes ?? catalog),
          family: Stream.value(family(nextDelivery: nextDelivery)),
          loadPlan: store.load,
          savePlan: store.save,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  group('the plan is stored in mealPlans', () {
    testWidgets('saves the plan of the family when there is none', (
      tester,
    ) async {
      final store = Store();
      await pump(tester, store);

      expect(store.saved, hasLength(1));
      final plan = store.saved.single;
      // Sin plan guardado se crea el documento (sin id; Firestore le pone uno).
      expect(plan.id, isEmpty);
      expect(plan.familyId, 'famA');
      expect(plan.meals, hasLength(7));
      expect(
        plan.meals.map((meal) => meal.recipeId),
        everyElement(isIn(['r-arroz', 'r-frijol'])),
      );
      expect(plan.meals.every((meal) => meal.servings > 0), isTrue);
    });

    testWidgets('the stored plan has what the rules of mealPlans ask for', (
      tester,
    ) async {
      final store = Store();
      await pump(
        tester,
        store,
        nextDelivery: DateTime.now().add(const Duration(days: 12)),
      );

      final plan = store.saved.single;
      // 14 días: el máximo de comidas de un plan (validMeals en las reglas).
      expect(plan.meals, hasLength(14));
      expect(plan.dateRangeEnd.isAfter(plan.dateRangeStart), isTrue);
      for (final meal in plan.meals) {
        expect(meal.date.isBefore(plan.dateRangeStart), isFalse);
        expect(meal.date.isAfter(plan.dateRangeEnd), isFalse);
        expect(meal.recipeId.length, inInclusiveRange(1, 128));
        expect(meal.servings, inInclusiveRange(0.0001, 100));
      }
      // Un día cada vez, sin repetir fechas.
      expect({for (final meal in plan.meals) meal.date}, hasLength(14));
    });

    testWidgets('prioritizes what expires first', (tester) async {
      final store = Store();
      await pump(
        tester,
        store,
        pantry: Stream.value([
          pantryItem('Arroz', days: 60),
          pantryItem('Frijol', days: 2),
        ]),
      );

      expect(store.saved.single.meals.first.recipeId, 'r-frijol');
    });

    testWidgets('replaces the stored plan instead of creating another', (
      tester,
    ) async {
      final first = Store();
      await pump(
        tester,
        first,
        pantry: Stream.value([pantryItem('Arroz', days: 60)]),
      );
      final store = Store(stored: first.stored);
      await pump(
        tester,
        store,
        pantry: Stream.value([
          pantryItem('Arroz', days: 60),
          pantryItem('Frijol', days: 1),
        ]),
      );

      expect(store.saved.single.id, first.stored!.id);
      expect(store.saved.single.id, isNotEmpty);
    });

    testWidgets('does not save again when the stored plan is the same', (
      tester,
    ) async {
      final first = Store();
      await pump(tester, first);
      final store = Store(stored: first.saved.single);
      await pump(tester, store);

      expect(store.saved, isEmpty);
    });

    testWidgets('a pantry that changes the plan saves the new one', (
      tester,
    ) async {
      final first = Store();
      await pump(
        tester,
        first,
        pantry: Stream.value([pantryItem('Arroz', days: 60)]),
      );
      final store = Store(stored: first.saved.single);
      await pump(
        tester,
        store,
        pantry: Stream.value([
          pantryItem('Arroz', days: 60),
          pantryItem('Frijol', days: 1),
        ]),
      );

      expect(store.saved, hasLength(1));
      expect(store.saved.single.meals.first.recipeId, 'r-frijol');
    });

    testWidgets('the same pantry emitted twice saves once', (tester) async {
      final store = Store();
      final controller = StreamController<List<data.PantryItem>>();
      addTearDown(controller.close);
      await pump(tester, store, pantry: controller.stream);
      controller.add([pantryItem('Arroz')]);
      await tester.pump();
      await tester.pump();
      controller.add([pantryItem('Arroz')]);
      await tester.pump();
      await tester.pump();

      expect(store.saved, hasLength(1));
    });

    testWidgets('a household with another portion saves the new servings', (
      tester,
    ) async {
      final first = Store();
      await pump(tester, first, members: [member()]);
      final store = Store(stored: first.saved.single);
      await pump(tester, store, members: [member(), member()]);

      expect(store.saved, hasLength(1));
      expect(
        store.saved.single.meals.first.servings,
        greaterThan(first.saved.single.meals.first.servings),
      );
    });

    testWidgets('"Actualizar plan" saves it on request', (tester) async {
      final store = Store();
      await pump(tester, store);
      expect(store.saved, hasLength(1));

      await tester.ensureVisible(find.text('Actualizar plan'));
      await tester.tap(find.text('Actualizar plan'));
      await tester.pump();
      await tester.pump();

      expect(store.saved, hasLength(2));
      expect(find.text('Plan actualizado.'), findsOneWidget);
    });
  });

  group('when something fails', () {
    testWidgets('a plan that cannot be saved is still shown', (tester) async {
      final store = Store(failSave: true);
      await pump(tester, store);

      expect(find.text('Arroz solo'), findsWidgets);
      expect(
        find.text('No se pudo guardar tu plan de comidas.'),
        findsOneWidget,
      );
    });

    testWidgets('a stored plan that cannot be read does not block the plan', (
      tester,
    ) async {
      final store = Store(failLoad: true);
      await pump(tester, store);

      expect(find.text('Arroz solo'), findsWidgets);
      expect(store.saved, hasLength(1));
    });
  });

  group('without a plan', () {
    testWidgets('an empty catalog saves nothing and shows the empty state', (
      tester,
    ) async {
      final store = Store();
      await pump(tester, store, recipes: const []);

      expect(store.saved, isEmpty);
      expect(
        find.text('Aún no hay recetas para armar tu plan'),
        findsOneWidget,
      );
    });

    testWidgets('recipes that are not from the catalog are not stored', (
      tester,
    ) async {
      final store = Store();
      await pump(
        tester,
        store,
        recipes: [
          recipe('', 'De muestra', ['Arroz']),
        ],
      );

      expect(store.saved, isEmpty);
    });

    testWidgets('a stored plan is cleared when no recipe is safe anymore', (
      tester,
    ) async {
      final first = Store();
      await pump(
        tester,
        first,
        recipes: [
          recipe('r-leche', 'Arroz con leche', ['Arroz', 'Leche']),
        ],
      );
      expect(first.saved.single.meals, isNotEmpty);

      final store = Store(stored: first.saved.single);
      await pump(
        tester,
        store,
        recipes: [
          recipe('r-leche', 'Arroz con leche', ['Arroz', 'Leche']),
        ],
        members: [
          member(allergies: [Allergy.dairy]),
        ],
      );

      expect(store.saved, hasLength(1));
      expect(store.saved.single.meals, isEmpty);
    });
  });

  group('mealPlanRecord and sameMealPlan', () {
    final today = DateTime(2026, 10, 14, 15, 30);

    List<ui.MealPlanEntry> entries(List<String> ids) => [
      for (final (i, id) in ids.indexed)
        ui
            .buildMealPlan(
              [
                recipe(id, id, ['Arroz']),
              ],
              const [],
              today: DateTime(today.year, today.month, today.day + i),
              days: 1,
            )
            .single,
    ];

    test('builds one meal per day with the recipe id', () {
      final plan = mealPlanRecord(
        familyId: 'famA',
        entries: entries(['a', 'b', 'c']),
        start: today,
        days: 3,
        servings: 2.5,
      )!;

      expect(plan.id, isEmpty);
      expect(plan.familyId, 'famA');
      expect(plan.dateRangeStart, DateTime(2026, 10, 14));
      expect(plan.dateRangeEnd, DateTime(2026, 10, 17));
      expect(plan.meals.map((m) => m.recipeId), ['a', 'b', 'c']);
      expect(plan.meals.map((m) => m.date.day), [14, 15, 16]);
      expect(plan.meals.every((m) => m.servings == 2.5), isTrue);
    });

    test('is null when a recipe has no id', () {
      expect(
        mealPlanRecord(
          familyId: 'famA',
          entries: entries(['a', '']),
          start: today,
          days: 2,
          servings: 1,
        ),
        isNull,
      );
    });

    test('sameMealPlan tells a different recipe, day or portion', () {
      MealPlan plan(List<String> ids, {double servings = 2}) => mealPlanRecord(
        familyId: 'famA',
        entries: entries(ids),
        start: today,
        days: ids.length,
        servings: servings,
      )!;

      expect(sameMealPlan(plan(['a', 'b']), plan(['a', 'b'])), isTrue);
      expect(sameMealPlan(plan(['a', 'b']), plan(['a', 'c'])), isFalse);
      expect(sameMealPlan(plan(['a', 'b']), plan(['a'])), isFalse);
      expect(
        sameMealPlan(plan(['a', 'b']), plan(['a', 'b'], servings: 3)),
        isFalse,
      );
    });
  });
}
