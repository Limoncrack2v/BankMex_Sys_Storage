import 'package:bank_storage_app/data/models/family.dart';
import 'package:bank_storage_app/data/models/member.dart';
import 'package:bank_storage_app/data/models/pantry_item.dart' as data;
import 'package:bank_storage_app/domain/allergen_filter.dart';
import 'package:bank_storage_app/domain/exclusion_list.dart';
import 'package:bank_storage_app/domain/meal_plan_generator.dart';
import 'package:bank_storage_app/domain/models/family_profile.dart';
import 'package:bank_storage_app/domain/models/pantry_item.dart';
import 'package:bank_storage_app/domain/models/recipe.dart' as domain;
import 'package:bank_storage_app/domain/recipe_on_demand.dart';
import 'package:bank_storage_app/domain/recipe_planner.dart';
import 'package:bank_storage_app/ui/models/recipe.dart' as ui;
import 'package:bank_storage_app/ui/screens/meal_plan/meal_plan_screen.dart';
import 'package:bank_storage_app/ui/screens/recipes/recipes_screen.dart';
import 'package:bank_storage_app/ui/theme/app_assets.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fixtures de los dos motores: las mismas recetas escritas para lib/domain y
// para lib/ui/models/recipe.dart.
// ---------------------------------------------------------------------------

domain.Recipe domainRecipe(String id, List<String> ingredients) =>
    domain.Recipe(
      id: id,
      name: id,
      ingredients: [
        for (final name in ingredients)
          domain.RecipeIngredient(productName: name, quantity: 100, unit: 'g'),
      ],
      steps: const ['x'],
      prepTimeMinutes: 1,
      caloriesPerServing: 1,
      status: domain.RecipeStatus.approved,
    );

ui.Recipe uiRecipe(String name, List<String> ingredients) => ui.Recipe(
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

PantryItem domainPantry(String name) => PantryItem(
  id: name,
  familyId: 'fam',
  productId: name,
  name: name,
  quantity: 1000,
  unit: 'g',
  expirationDate: DateTime(2026, 11, 20),
  category: 'test',
  originalQuantity: 1000,
  consumedQuantity: 0,
  status: PantryItemStatus.available,
);

data.PantryItem uiPantry(String productId) => data.PantryItem(
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

FamilyProfile profile(List<String> restrictions) => FamilyProfile(
  id: 'fam',
  authUid: 'fam',
  adults: 2,
  children: const [],
  dietaryRestrictions: restrictions,
);

Member member({List<Allergy>? allergies, List<ChronicCondition>? conditions}) =>
    Member(
      memberId: 'm1',
      name: 'Ana',
      memberType: MemberType.adult,
      createdAt: DateTime(2026, 9, 21),
      allergies: allergies,
      chronicConditions: conditions,
    );

void main() {
  final now = DateTime(2026, 10, 14);

  group('the allergen rule', () {
    test('matches whole words and plurals, not parts of a word', () {
      bool has(String name, Allergy allergy) => containsAllergen(name, allergy);

      expect(has('Leche entera', Allergy.dairy), isTrue);
      expect(has('Quesos', Allergy.dairy), isTrue);
      expect(has('Cacahuates', Allergy.peanut), isTrue);
      expect(has('Huevos', Allergy.egg), isTrue);
      expect(has('Pan de caja', Allergy.gluten), isTrue);
      expect(has('Camarones', Allergy.shellfish), isTrue);
      expect(has('Tofu', Allergy.soy), isTrue);
      expect(has('Lechuga', Allergy.dairy), isFalse);
      expect(has('Panela', Allergy.gluten), isFalse);
    });

    test('chronic conditions do not exclude unless the switch says so', () {
      expect(excludeRecipesForChronicConditions, isFalse);
    });
  });

  group('AllergenFilter', () {
    final recipes = [
      domainRecipe('con_queso', ['Queso']),
      domainRecipe('solo_arroz', ['Arroz']),
    ];

    test('drops the recipes with an allergen of the household', () {
      final safe = AllergenFilter.safeRecipes(
        recipes: recipes,
        family: profile(const ['dairy']),
      );
      expect(safe.map((r) => r.id), ['solo_arroz']);
    });

    test('keeps everything for a household without that allergy', () {
      final safe = AllergenFilter.safeRecipes(
        recipes: recipes,
        family: profile(const ['gluten']),
      );
      expect(safe.map((r) => r.id), ['con_queso', 'solo_arroz']);
    });

    test('a chronic condition only excludes when asked to', () {
      final sugary = [
        domainRecipe('postre', ['Azúcar']),
      ];
      final family = profile(const ['diabetes']);
      expect(
        AllergenFilter.safeRecipes(recipes: sugary, family: family),
        hasLength(1),
      );
      expect(
        AllergenFilter.safeRecipes(
          recipes: sugary,
          family: family,
          excludeConditions: true,
        ),
        isEmpty,
      );
    });
  });

  group('suggestions and plans of lib/domain', () {
    final items = [domainPantry('Queso'), domainPantry('Arroz')];
    final recipes = [
      domainRecipe('con_queso', ['Queso']),
      domainRecipe('solo_arroz', ['Arroz']),
    ];
    final dairy = profile(const ['dairy']);

    test('RecipeOnDemand never picks a recipe with the allergen', () {
      final picked = RecipeOnDemand.getSingleRecipeOnDemand(
        family: dairy,
        pantryItems: items,
        recipes: recipes,
        now: now,
      );
      expect(picked?.id, 'solo_arroz');
    });

    test('MealPlanGenerator leaves the recipe out of every day', () {
      final generated = MealPlanGenerator.generateMealPlan(
        family: dairy,
        pantryItems: items,
        recipes: recipes,
        days: 3,
        now: now,
      );
      expect(generated.plan.meals, isNotEmpty);
      expect(
        generated.plan.meals.map((meal) => meal.recipeId),
        everyElement('solo_arroz'),
      );
    });

    test('a household whose recipes all conflict gets an empty plan', () {
      final generated = MealPlanGenerator.generateMealPlan(
        family: dairy,
        pantryItems: [domainPantry('Queso')],
        recipes: [
          domainRecipe('con_queso', ['Queso']),
        ],
        days: 7,
        now: now,
      );
      expect(generated.plan.meals, isEmpty);
      expect(generated.filledDays, 0);
    });

    test(
      'RecipePlanner applies it to the suggestion and to the plan',
      () async {
        const planner = RuleBasedRecipePlanner();
        final suggested = await planner.suggestRecipe(
          family: dairy,
          pantryItems: items,
          recipes: recipes,
          now: now,
        );
        final plan = await planner.planDays(
          family: dairy,
          pantryItems: items,
          recipes: recipes,
          days: 2,
          now: now,
        );
        expect(suggested?.id, 'solo_arroz');
        expect(
          plan.plan.meals.map((meal) => meal.recipeId),
          isNot(contains('con_queso')),
        );
      },
    );

    test('the same household keeps the recipe when nobody is allergic', () {
      final picked = RecipeOnDemand.getSingleRecipeOnDemand(
        family: profile(const []),
        pantryItems: [domainPantry('Queso')],
        recipes: [
          domainRecipe('con_queso', ['Queso']),
        ],
        now: now,
      );
      expect(picked?.id, 'con_queso');
    });
  });

  group('both engines agree', () {
    // Nombres de ingredientes (con plurales, acentos y casi-coincidencias)
    // contra cada alergia: lib/domain y lib/ui deben decidir igual.
    const names = [
      'Leche entera',
      'Quesos',
      'Yogurt natural',
      'Lechuga',
      'Pan de caja',
      'Panela',
      'Pasta',
      'Avena',
      'Cacahuates',
      'Camarones',
      'Huevos',
      'Tofu',
      'Soya',
      'Arroz',
      'Frijol',
    ];

    test('for every ingredient and every allergy', () {
      for (final allergy in Allergy.values) {
        for (final name in names) {
          final inDomain = AllergenFilter.containsAllergenOf(
            domainRecipe('r', [name]),
            [allergy],
          );
          final inUi = ui.allergyConflicts(uiRecipe('r', [name]), [
            member(allergies: [allergy]),
          ]).isNotEmpty;
          expect(inDomain, inUi, reason: '$name con ${allergy.name}');
        }
      }
    });

    test('for the recipes they keep', () {
      final domainRecipes = [
        domainRecipe('Queso', ['Queso']),
        domainRecipe('Arroz', ['Arroz']),
        domainRecipe('Pan', ['Pan de caja', 'Huevos']),
      ];
      final uiRecipes = [
        uiRecipe('Queso', ['Queso']),
        uiRecipe('Arroz', ['Arroz']),
        uiRecipe('Pan', ['Pan de caja', 'Huevos']),
      ];
      for (final allergies in [
        <Allergy>[],
        [Allergy.dairy],
        [Allergy.egg],
        [Allergy.dairy, Allergy.gluten],
      ]) {
        final kept = AllergenFilter.safeRecipes(
          recipes: domainRecipes,
          family: profile([for (final a in allergies) a.name]),
        ).map((r) => r.id);
        final keptInUi = ui
            .recipesSafeForHousehold(uiRecipes, [member(allergies: allergies)])
            .map((r) => r.name);
        expect(kept, keptInUi, reason: allergies.map((a) => a.name).join(','));
      }
    });

    test('for chronic conditions when the switch is on', () {
      final kept = AllergenFilter.safeRecipes(
        recipes: [
          domainRecipe('Postre', ['Azúcar']),
          domainRecipe('Arroz', ['Arroz']),
        ],
        family: profile(const ['diabetes']),
        excludeConditions: true,
      ).map((r) => r.id);
      final keptInUi = ui
          .recipesSafeForHousehold(
            [
              uiRecipe('Postre', ['Azúcar']),
              uiRecipe('Arroz', ['Arroz']),
            ],
            [
              member(conditions: [ChronicCondition.diabetes]),
            ],
            excludeConditions: true,
          )
          .map((r) => r.name);
      expect(kept, keptInUi);
      expect(kept, ['Arroz']);
    });
  });

  group('MealPlanScreen', () {
    Future<void> pump(
      WidgetTester tester, {
      required Stream<List<Member>> members,
      required List<ui.Recipe> catalog,
      List<String> pantry = const ['Arroz', 'Leche entera'],
    }) async {
      tester.view.physicalSize = const Size(900, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: MealPlanScreen(
              familyId: 'famA',
              pantry: Stream.value([for (final p in pantry) uiPantry(p)]),
              members: members,
              catalog: Stream.value(catalog),
              family: Stream<Family?>.value(null),
              adjustments: Stream.value(const []),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    final catalog = [
      uiRecipe('Arroz con leche', ['Arroz', 'Leche entera']),
      uiRecipe('Arroz solo', ['Arroz']),
    ];

    test('the fixture is what the tests below rely on', () {
      expect(
        ui.allergyConflicts(catalog.first, [
          member(allergies: [Allergy.dairy]),
        ]),
        isNotEmpty,
      );
    });

    testWidgets(
      'no day of the plan has a recipe the household is allergic to',
      (tester) async {
        await pump(
          tester,
          members: Stream.value([
            member(allergies: [Allergy.dairy]),
          ]),
          catalog: catalog,
        );

        expect(find.text('Arroz con leche'), findsNothing);
        expect(find.text('Arroz solo'), findsWidgets);
      },
    );

    testWidgets('a household without that allergy keeps the recipe', (
      tester,
    ) async {
      await pump(
        tester,
        members: Stream.value([
          member(allergies: [Allergy.peanut]),
        ]),
        catalog: catalog,
      );

      expect(find.text('Arroz con leche'), findsWidgets);
    });

    testWidgets('all recipes in conflict give an empty plan, not sample data', (
      tester,
    ) async {
      await pump(
        tester,
        members: Stream.value([
          member(allergies: [Allergy.dairy]),
        ]),
        catalog: [catalog.first],
      );

      expect(
        find.text('Ninguna receta es segura para tu familia'),
        findsOneWidget,
      );
      expect(find.text('Arroz con leche'), findsNothing);
      expect(find.text('Arroz con atún'), findsNothing);
    });

    testWidgets('an empty catalog shows the empty state', (tester) async {
      await pump(tester, members: Stream.value(const []), catalog: const []);

      expect(
        find.text('Aún no hay recetas para armar tu plan'),
        findsOneWidget,
      );
    });

    testWidgets('without the members it does not build the plan', (
      tester,
    ) async {
      await pump(
        tester,
        members: Stream<List<Member>>.error(StateError('permission-denied')),
        catalog: catalog,
      );

      expect(
        find.textContaining('No pudimos revisar las alergias'),
        findsOneWidget,
      );
      expect(find.text('Arroz con leche'), findsNothing);
      expect(find.text('Arroz solo'), findsNothing);
    });
  });

  group('RecipesScreen', () {
    Future<void> pump(
      WidgetTester tester, {
      required Stream<List<Member>> members,
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
              pantry: Stream.value([
                uiPantry('Arroz'),
                uiPantry('Leche entera'),
              ]),
              members: members,
              catalog: Stream.value([
                uiRecipe('Arroz con leche', ['Arroz', 'Leche entera']),
                uiRecipe('Arroz solo', ['Arroz']),
              ]),
              adjustments: Stream.value(const []),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets(
      '"Con lo que tengo" does not suggest a recipe with the allergen',
      (tester) async {
        await pump(
          tester,
          members: Stream.value([
            member(allergies: [Allergy.dairy]),
          ]),
        );

        expect(find.text('Arroz solo'), findsOneWidget);
        expect(find.text('Arroz con leche'), findsNothing);
      },
    );

    testWidgets('the full catalog still shows it, with its warning', (
      tester,
    ) async {
      await pump(
        tester,
        members: Stream.value([
          member(allergies: [Allergy.dairy]),
        ]),
      );
      await tester.tap(find.text('Todas'));
      await tester.pump();

      expect(find.text('Arroz con leche'), findsOneWidget);
      expect(find.text('Arroz solo'), findsOneWidget);
    });

    testWidgets('without the members it suggests nothing', (tester) async {
      await pump(
        tester,
        members: Stream<List<Member>>.error(StateError('permission-denied')),
      );

      expect(
        find.textContaining('No pudimos revisar las alergias'),
        findsOneWidget,
      );
      expect(find.text('Arroz solo'), findsNothing);
      expect(find.text('Arroz con leche'), findsNothing);
    });
  });
}
