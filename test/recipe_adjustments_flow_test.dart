import 'package:bank_storage_app/application/bank_storage_facade.dart';
import 'package:bank_storage_app/data/models/family.dart';
import 'package:bank_storage_app/data/models/member.dart';
import 'package:bank_storage_app/data/models/pantry_item.dart' as data;
import 'package:bank_storage_app/data/repositories/adjustment_repository.dart';
import 'package:bank_storage_app/data/repositories/family_repository.dart';
import 'package:bank_storage_app/data/repositories/meal_plan_repository.dart';
import 'package:bank_storage_app/data/repositories/member_repository.dart';
import 'package:bank_storage_app/data/repositories/pantry_repository.dart';
import 'package:bank_storage_app/data/repositories/recipe_repository.dart';
import 'package:bank_storage_app/domain/models/recipe.dart' as domain;
import 'package:bank_storage_app/domain/models/recipe_adjustment.dart';
import 'package:bank_storage_app/domain/recipe_adjustment.dart';
import 'package:bank_storage_app/domain/recipe_planner.dart';
import 'package:bank_storage_app/domain/models/family_profile.dart';
import 'package:bank_storage_app/domain/models/pantry_item.dart'
    as domain_pantry;
import 'package:bank_storage_app/domain/meal_plan_generator.dart';
import 'package:bank_storage_app/ui/models/recipe.dart' as ui;
import 'package:bank_storage_app/ui/models/recipe_adjustments.dart';
import 'package:bank_storage_app/ui/screens/meal_plan/meal_plan_screen.dart';
import 'package:bank_storage_app/ui/screens/recipes/recipes_screen.dart';
import 'package:bank_storage_app/ui/theme/app_assets.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

Member member(String name, {List<Allergy>? allergies}) => Member(
  memberId: name,
  name: name,
  memberType: MemberType.adult,
  createdAt: DateTime(2026, 9, 21),
  allergies: allergies,
);

final dairyHousehold = [
  member('Ana', allergies: [Allergy.dairy]),
  member('Beto'),
  member('Carla'),
  member('Dario'),
];

domain.Recipe domainRecipe({
  String id = 'r1',
  domain.RecipeStatus status = domain.RecipeStatus.approved,
  double rice = 0.4,
}) => domain.Recipe(
  id: id,
  name: 'Arroz con leche',
  ingredients: [
    domain.RecipeIngredient(productName: 'Arroz', quantity: rice, unit: 'kg'),
    const domain.RecipeIngredient(
      productName: 'Leche entera',
      quantity: 1,
      unit: 'l',
    ),
  ],
  steps: const ['Cocer'],
  prepTimeMinutes: 30,
  caloriesPerServing: 200,
  status: status,
  servings: 4,
);

/// La misma receta como la ve la UI (con su huella).
ui.Recipe uiRecipe({String id = 'r1', double rice = 0.4}) => ui.Recipe(
  id: id,
  signature: recipeSignature(domainRecipe(id: id, rice: rice)),
  name: 'Arroz con leche',
  image: AppImages.sopaDeLentejas,
  minutes: 30,
  servings: 4,
  kcalPerServing: 200,
  ingredients: [
    ui.RecipeIngredient('Arroz', rice, data.FoodUnit.kg),
    ui.RecipeIngredient('Leche entera', 1, data.FoodUnit.l),
  ],
  steps: const ['Cocer'],
);

RecipeAdjustment adjustment({
  AdjustmentStatus status = AdjustmentStatus.approved,
  String recipeId = 'r1',
  String? signature,
  int householdSize = 4,
  String? householdKey,
  List<String> ingredientNames = const ['Arroz', 'Bebida de avena'],
}) => RecipeAdjustment(
  id: 'a1',
  familyId: 'famA',
  recipeId: recipeId,
  baseSignature: signature ?? uiRecipe().signature,
  householdSize: householdSize,
  // dairyHousehold: 4 integrantes, uno con alergia a los lácteos.
  householdKey: householdKey ?? '$householdSize-dairy',
  servings: 4,
  ingredients: [
    for (final name in ingredientNames)
      domain.RecipeIngredient(
        productName: name,
        quantity: name == 'Arroz' ? 0.4 : 1,
        unit: name == 'Arroz' ? 'kg' : 'l',
      ),
  ],
  changes: const [
    AdjustmentChange(
      kind: AdjustmentChange.kindSubstitution,
      reason: 'alergia a lácteos',
      from: 'Leche entera',
      to: 'Bebida de avena',
    ),
  ],
  summary:
      'se sustituye leche entera por bebida de avena por alergia a lácteos',
  status: status,
);

// ---------------------------------------------------------------------------
// applyAdjustments
// ---------------------------------------------------------------------------

void main() {
  group('applyAdjustments', () {
    List<ui.Recipe> apply(
      List<RecipeAdjustment> adjustments, {
      List<Member>? members,
    }) => applyAdjustments(
      [uiRecipe()],
      adjustments,
      members: members ?? dairyHousehold,
    );

    test('an approved adaptation replaces the ingredients and says why', () {
      final recipe = apply([adjustment()]).single;

      expect(recipe.ingredients.map((i) => i.name), [
        'Arroz',
        'Bebida de avena',
      ]);
      expect(recipe.ingredients.last.unit, data.FoodUnit.l);
      expect(recipe.adaptation, contains('bebida de avena'));
      expect(recipe.id, 'r1');
      expect(recipe.name, 'Arroz con leche');
    });

    test('a pending or rejected one leaves the base recipe', () {
      for (final status in [
        AdjustmentStatus.pending,
        AdjustmentStatus.rejected,
      ]) {
        final recipe = apply([adjustment(status: status)]).single;
        expect(recipe.adaptation, isNull);
        expect(recipe.ingredients.last.name, 'Leche entera');
      }
    });

    test('one for another recipe does not apply', () {
      expect(apply([adjustment(recipeId: 'otra')]).single.adaptation, isNull);
    });

    test('one made for an earlier version of the recipe does not apply', () {
      final edited = applyAdjustments(
        [uiRecipe(rice: 0.5)],
        [adjustment()],
        members: dairyHousehold,
      ).single;
      expect(edited.adaptation, isNull);
      expect(edited.ingredients.last.name, 'Leche entera');
    });

    test('one made for another household size does not apply', () {
      expect(
        apply(
          [adjustment()],
          members: [...dairyHousehold, member('Eva')],
        ).single.adaptation,
        isNull,
      );
    });

    test('one made for other allergies does not apply, same size or not', () {
      final moreAllergies = [
        member('Ana', allergies: [Allergy.dairy, Allergy.gluten]),
        member('Beto'),
        member('Carla'),
        member('Dario'),
      ];
      final noAllergies = [
        for (final name in ['Ana', 'Beto', 'Carla', 'Dario']) member(name),
      ];

      expect(
        apply([adjustment()], members: moreAllergies).single.adaptation,
        isNull,
      );
      expect(
        apply([adjustment()], members: noAllergies).single.adaptation,
        isNull,
      );
      // La misma que ahora sí aplica.
      expect(apply([adjustment()]).single.adaptation, isNotNull);
    });

    test('an approved adaptation with an allergen of the household is never applied', () {
      // Aunque esté aprobada y la clave coincida: lleva leche y hay alergia.
      final unsafe = adjustment(ingredientNames: ['Arroz', 'Leche entera']);
      final recipe = apply([unsafe]).single;

      expect(recipe.adaptation, isNull);
      expect(recipe.ingredients.last.name, 'Leche entera');
      // Con otro alérgeno del hogar pasa lo mismo.
      final cheese = adjustment(
        householdKey: '4-dairy-gluten',
        ingredientNames: ['Arroz', 'Pan de caja'],
      );
      final gluten = [
        member('Ana', allergies: [Allergy.dairy, Allergy.gluten]),
        member('Beto'),
        member('Carla'),
        member('Dario'),
      ];
      expect(apply([cheese], members: gluten).single.adaptation, isNull);
    });

    test('a recipe without an id or fingerprint is left alone', () {
      const sample = ui.Recipe(
        name: 'De muestra',
        image: '',
        minutes: 1,
        servings: 1,
        kcalPerServing: 1,
        ingredients: [],
        steps: [],
      );
      final result = applyAdjustments(
        [sample],
        [adjustment()],
        members: dairyHousehold,
      );
      expect(result.single, same(sample));
    });

    test('the key of a household is its size and its allergies in order', () {
      expect(householdKeyForMembers(dairyHousehold), '4-dairy');
      expect(householdKeyForMembers(const []), '1');
      expect(
        householdKeyForMembers([
          member('Ana', allergies: [Allergy.soy, Allergy.dairy]),
          member('Beto', allergies: [Allergy.dairy, Allergy.egg]),
        ]),
        '2-dairy-egg-soy',
      );
    });
  });

  // -------------------------------------------------------------------------
  // BankStorageFacade
  // -------------------------------------------------------------------------

  group('the engine can be replaced', () {
    test(
      'another RecipePlanner decides, with no change in the facade',
      () async {
        final planner = _OtherEngine();
        final fake = _Fakes(members: dairyHousehold, planner: planner);

        final created = await fake.facade.suggestAdjustment(
          familyId: 'famA',
          recipeId: 'r1',
        );

        // Lo que se guarda es lo que sugirió el otro motor.
        expect(created, isNotNull);
        final stored = fake.adjustments.created.single;
        expect(stored.summary, 'Sugerido por otro motor');
        expect(stored.ingredients.single.productName, 'Bebida de coco');
        expect(stored.status, AdjustmentStatus.pending);
      },
    );

    test(
      'the other engine gets the household without names, ages or weights',
      () async {
        final planner = _OtherEngine();
        await _Fakes(
          members: dairyHousehold,
          planner: planner,
        ).facade.suggestAdjustment(familyId: 'famA', recipeId: 'r1');

        final household = planner.received!;
        expect(household.householdSize, 4);
        expect(household.allergies, [Allergy.dairy]);
        expect(household.portions, 4);
        // El contexto solo tiene esos tres datos.
        final text = household.toString();
        expect(text, isNot(contains('Ana')));
      },
    );

    test(
      'an engine with nothing to suggest leaves the family as it is',
      () async {
        final fake = _Fakes(
          members: dairyHousehold,
          planner: _OtherEngine(none: true),
        );

        expect(
          await fake.facade.suggestAdjustment(familyId: 'famA', recipeId: 'r1'),
          isNull,
        );
        expect(fake.adjustments.created, isEmpty);
      },
    );
  });

  group('AdjustmentContext', () {
    test('has the size, the portions and the allergies of the household', () {
      final context = AdjustmentContext.forHousehold(
        const FamilyProfile(
          id: 'famA',
          authUid: 'famA',
          adults: 2,
          children: [],
          dietaryRestrictions: ['dairy', 'diabetes'],
        ),
      );

      expect(context.householdSize, 2);
      expect(context.portions, 2);
      // Una enfermedad no es una alergia.
      expect(context.allergies, [Allergy.dairy]);
    });
  });

  group('BankStorageFacade adjustments', () {
    test(
      'suggests a pending adaptation for a household with an allergy',
      () async {
        final fake = _Fakes(members: dairyHousehold);
        final created = await fake.facade.suggestAdjustment(
          familyId: 'famA',
          recipeId: 'r1',
        );

        expect(created, isNotNull);
        expect(fake.adjustments.created, hasLength(1));
        final stored = fake.adjustments.created.single;
        expect(stored.status, AdjustmentStatus.pending);
        expect(stored.familyId, 'famA');
        expect(stored.recipeId, 'r1');
        expect(stored.householdSize, 4);
        expect(stored.ingredients.last.productName, 'Bebida de avena');
        expect(stored.changes.single.reason, 'alergia a lácteos');
      },
    );

    test('carries the household size and reasons, not names', () async {
      final fake = _Fakes(members: dairyHousehold);
      await fake.facade.suggestAdjustment(familyId: 'famA', recipeId: 'r1');

      final text = fake.adjustments.created.single.toMap().toString();
      for (final name in ['Ana', 'Beto', 'Carla', 'Dario']) {
        expect(text, isNot(contains(name)));
      }
    });

    test('does not suggest the same thing twice', () async {
      final fake = _Fakes(members: dairyHousehold);
      await fake.facade.suggestAdjustment(familyId: 'famA', recipeId: 'r1');
      final again = await fake.facade.suggestAdjustment(
        familyId: 'famA',
        recipeId: 'r1',
      );

      expect(again, isNull);
      expect(fake.adjustments.created, hasLength(1));
    });

    test('does not suggest again after the nutritionist rejected it', () async {
      final fake = _Fakes(members: dairyHousehold);
      await fake.facade.suggestAdjustment(familyId: 'famA', recipeId: 'r1');
      fake.adjustments.setStatus(AdjustmentStatus.rejected);
      final again = await fake.facade.suggestAdjustment(
        familyId: 'famA',
        recipeId: 'r1',
      );

      expect(again, isNull);
      expect(fake.adjustments.created, hasLength(1));
    });

    test(
      'a pending suggestion that went stale is withdrawn and replaced',
      () async {
        final fake = _Fakes(members: dairyHousehold);
        await fake.facade.suggestAdjustment(familyId: 'famA', recipeId: 'r1');
        final firstId = fake.adjustments.created.single.id;

        // La receta se editó: la sugerencia pendiente ya no es de esta versión.
        fake.recipes.stored = domainRecipe(rice: 0.5);
        final replaced = await fake.facade.suggestAdjustment(
          familyId: 'famA',
          recipeId: 'r1',
        );

        expect(replaced, isNotNull);
        expect(fake.adjustments.deleted, [firstId]);
        expect(fake.adjustments.created, hasLength(2));
      },
    );

    test(
      'the id is one per family, recipe, version and household size',
      () async {
        final fake = _Fakes(members: dairyHousehold);
        await fake.facade.suggestAdjustment(familyId: 'famA', recipeId: 'r1');

        final signature = recipeSignature(domainRecipe());
        expect(
          fake.adjustments.created.single.id,
          'famA_r1_${signature}_4-dairy',
        );
      },
    );

    test('after a rejection, a bigger household suggests again', () async {
      final fake = _Fakes(members: dairyHousehold);
      await fake.facade.suggestAdjustment(familyId: 'famA', recipeId: 'r1');
      fake.adjustments.setStatus(AdjustmentStatus.rejected);

      fake.household.members = [...dairyHousehold, member('Eva')];
      final again = await fake.facade.suggestAdjustment(
        familyId: 'famA',
        recipeId: 'r1',
      );

      expect(again, isNotNull);
      expect(fake.adjustments.created.map((a) => a.householdSize), [4, 5]);
      expect(fake.adjustments.created.last.id, endsWith('_5-dairy'));
    });

    test('after a rejection, an edited recipe suggests again', () async {
      final fake = _Fakes(members: dairyHousehold);
      await fake.facade.suggestAdjustment(familyId: 'famA', recipeId: 'r1');
      fake.adjustments.setStatus(AdjustmentStatus.rejected);

      fake.recipes.stored = domainRecipe(rice: 0.5);
      final again = await fake.facade.suggestAdjustment(
        familyId: 'famA',
        recipeId: 'r1',
      );

      expect(again, isNotNull);
      expect(fake.adjustments.created, hasLength(2));
      expect(
        fake.adjustments.created.map((a) => a.baseSignature).toSet(),
        hasLength(2),
      );
    });

    test('changing only the allergies makes a new document', () async {
      final fake = _Fakes(members: dairyHousehold);
      await fake.facade.suggestAdjustment(familyId: 'famA', recipeId: 'r1');
      fake.adjustments.setStatus(AdjustmentStatus.approved);

      fake.household.members = [
        member('Ana', allergies: [Allergy.dairy, Allergy.gluten]),
        member('Beto'),
        member('Carla'),
        member('Dario'),
      ];
      final again = await fake.facade.suggestAdjustment(
        familyId: 'famA',
        recipeId: 'r1',
      );

      // El mismo tamaño, la misma receta y otras alergias: otro documento. El
      // aprobado viejo se queda (la familia no lo borra) y ya no se aplica.
      expect(again, isNotNull);
      expect(fake.adjustments.created.map((a) => a.householdKey), [
        '4-dairy',
        '4-dairy-gluten',
      ]);
      expect(fake.adjustments.created.first.status, AdjustmentStatus.approved);
      expect(fake.adjustments.deleted, isEmpty);
      expect(fake.adjustments.created.last.id, endsWith('_4-dairy-gluten'));
    });

    test('a pending suggestion for the old allergies is withdrawn', () async {
      final fake = _Fakes(members: dairyHousehold);
      await fake.facade.suggestAdjustment(familyId: 'famA', recipeId: 'r1');
      final oldId = fake.adjustments.created.single.id;

      fake.household.members = [
        member('Ana', allergies: [Allergy.dairy, Allergy.egg]),
        member('Beto'),
        member('Carla'),
        member('Dario'),
      ];
      await fake.facade.suggestAdjustment(familyId: 'famA', recipeId: 'r1');

      expect(fake.adjustments.deleted, [oldId]);
      expect(fake.adjustments.created.last.householdKey, '4-dairy-egg');
    });

    test('the same household asking again does not create another', () async {
      final fake = _Fakes(members: dairyHousehold);
      for (var i = 0; i < 3; i++) {
        await fake.facade.suggestAdjustment(familyId: 'famA', recipeId: 'r1');
      }
      expect(fake.adjustments.created, hasLength(1));
    });

    test('nothing to change means no suggestion', () async {
      final fake = _Fakes(
        members: [
          member('Ana'),
          member('Beto'),
          member('Carla'),
          member('Dario'),
        ],
      );
      expect(
        await fake.facade.suggestAdjustment(familyId: 'famA', recipeId: 'r1'),
        isNull,
      );
      expect(fake.adjustments.created, isEmpty);
    });

    test('only approved recipes get a suggestion', () async {
      final fake = _Fakes(
        members: dairyHousehold,
        recipe: domainRecipe(status: domain.RecipeStatus.pending),
      );
      expect(
        await fake.facade.suggestAdjustment(familyId: 'famA', recipeId: 'r1'),
        isNull,
      );
      expect(
        await _Fakes(members: dairyHousehold).facade
            .suggestAdjustment(familyId: 'famA', recipeId: 'no-existe'),
        isNull,
      );
      expect(fake.adjustments.created, isEmpty);
    });

    test('the nutritionist approves and rejects through the facade', () async {
      final fake = _Fakes(members: dairyHousehold);
      await fake.facade.approveAdjustment('a1', reviewerUid: 'nutri1');
      await fake.facade.rejectAdjustment(
        'a2',
        reviewerUid: 'nutri1',
        reason: '  No es seguro  ',
      );

      expect(fake.adjustments.calls, [
        'approve a1 by nutri1',
        'reject a2 by nutri1: No es seguro',
      ]);
    });

    test('rejecting needs a reason', () async {
      final fake = _Fakes(members: dairyHousehold);
      for (final reason in ['', '   ', 'a' * 301]) {
        expect(
          () => fake.facade.rejectAdjustment(
            'a1',
            reviewerUid: 'nutri1',
            reason: reason,
          ),
          throwsArgumentError,
        );
      }
      expect(fake.adjustments.calls, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Pantallas de la familia
  // -------------------------------------------------------------------------

  group('RecipesScreen', () {
    Future<void> pump(
      WidgetTester tester,
      List<RecipeAdjustment> adjustments,
    ) async {
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
                _pantry('Arroz', data.FoodUnit.kg),
                _pantry('Leche entera', data.FoodUnit.l),
                _pantry('Bebida de avena', data.FoodUnit.l),
              ]),
              members: Stream.value(dairyHousehold),
              catalog: Stream.value([uiRecipe()]),
              adjustments: Stream.value(adjustments),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
    }

    testWidgets('while the suggestion is pending the recipe is not suggested', (
      tester,
    ) async {
      await pump(tester, [adjustment(status: AdjustmentStatus.pending)]);

      // La receta base lleva leche y la familia es alérgica: sigue fuera.
      expect(find.text('Arroz con leche'), findsNothing);
    });

    testWidgets('once approved, the adapted recipe is suggested', (
      tester,
    ) async {
      await pump(tester, [adjustment()]);

      expect(find.text('Arroz con leche'), findsOneWidget);
    });

    testWidgets('an approved adaptation with an allergen is not suggested', (
      tester,
    ) async {
      await pump(tester, [
        adjustment(ingredientNames: ['Arroz', 'Leche entera']),
      ]);

      expect(find.text('Arroz con leche'), findsNothing);
    });

    testWidgets('an approval for other allergies is not suggested', (
      tester,
    ) async {
      await pump(tester, [adjustment(householdKey: '4-dairy-gluten')]);

      expect(find.text('Arroz con leche'), findsNothing);
    });

    testWidgets('a rejected one changes nothing', (tester) async {
      await pump(tester, [adjustment(status: AdjustmentStatus.rejected)]);

      expect(find.text('Arroz con leche'), findsNothing);
    });

    testWidgets('the full catalog shows the base recipe while it is pending', (
      tester,
    ) async {
      await pump(tester, [adjustment(status: AdjustmentStatus.pending)]);
      await tester.tap(find.text('Todas'));
      await tester.pump();

      expect(find.text('Arroz con leche'), findsOneWidget);
    });
  });

  group('MealPlanScreen', () {
    Future<void> pump(
      WidgetTester tester,
      List<RecipeAdjustment> adjustments,
    ) async {
      tester.view.physicalSize = const Size(900, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: MealPlanScreen(
              familyId: 'famA',
              pantry: Stream.value([
                _pantry('Arroz', data.FoodUnit.kg),
                _pantry('Bebida de avena', data.FoodUnit.l),
              ]),
              members: Stream.value(dairyHousehold),
              catalog: Stream.value([uiRecipe()]),
              family: Stream<Family?>.value(null),
              adjustments: Stream.value(adjustments),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a pending suggestion keeps the recipe out of the plan', (
      tester,
    ) async {
      await pump(tester, [adjustment(status: AdjustmentStatus.pending)]);

      expect(find.text('Arroz con leche'), findsNothing);
      expect(
        find.text('Ninguna receta es segura para tu familia'),
        findsOneWidget,
      );
    });

    testWidgets('an approved adaptation puts the recipe in the plan', (
      tester,
    ) async {
      await pump(tester, [adjustment()]);

      expect(find.text('Arroz con leche'), findsWidgets);
    });

    testWidgets('an approval for another household size does not apply', (
      tester,
    ) async {
      await pump(tester, [adjustment(householdSize: 3)]);

      expect(find.text('Arroz con leche'), findsNothing);
    });

    testWidgets('an approval for other allergies does not apply', (
      tester,
    ) async {
      await pump(tester, [adjustment(householdKey: '4-dairy-gluten')]);

      expect(find.text('Arroz con leche'), findsNothing);
    });

    testWidgets(
      'an approved adaptation with an allergen never enters the plan',
      (tester) async {
        await pump(tester, [
          adjustment(ingredientNames: ['Arroz', 'Leche entera']),
        ]);

        expect(find.text('Arroz con leche'), findsNothing);
      },
    );
  });
}

data.PantryItem _pantry(String productId, data.FoodUnit unit) =>
    data.PantryItem(
      pantryItemId: 'item-$productId',
      productId: productId,
      deliveryId: 'entrega-001',
      type: data.FoodType.other,
      quantity: 20,
      unit: unit,
      daysUntilExpiration: 30,
      deviceId: 'device-test',
      localTimestamp: DateTime.now(),
    );

// ---------------------------------------------------------------------------
// Repos de mentira
// ---------------------------------------------------------------------------

class _FakeFamilies extends Fake implements FamilyRepository {
  @override
  Future<Family?> getFamily(String familyId) async => Family(
    familyId: familyId,
    address: 'Calle 1',
    registrationDate: DateTime(2026, 9, 1),
    authUid: familyId,
    appliances: const [],
  );
}

class _FakeMembers extends Fake implements MemberRepository {
  _FakeMembers(this.members);

  List<Member> members;

  @override
  Stream<List<Member>> watchAllMembers(String familyId) =>
      Stream.value(members);
}

class _FakePantry extends Fake implements PantryRepository {}

class _FakeMealPlans extends Fake implements MealPlanRepository {}

class _FakeFirestore extends Fake implements FirebaseFirestore {}

class _FakeRecipes extends Fake implements RecipeRepository {
  domain.Recipe? stored;

  @override
  Future<domain.Recipe?> getById(String recipeId) async =>
      stored?.id == recipeId ? stored : null;
}

class _FakeAdjustments extends Fake implements AdjustmentRepository {
  final created = <RecipeAdjustment>[];
  final deleted = <String>[];
  final calls = <String>[];

  void setStatus(AdjustmentStatus status) {
    for (var i = 0; i < created.length; i++) {
      final a = created[i];
      created[i] = RecipeAdjustment(
        id: a.id,
        familyId: a.familyId,
        recipeId: a.recipeId,
        baseSignature: a.baseSignature,
        householdSize: a.householdSize,
        householdKey: a.householdKey,
        servings: a.servings,
        ingredients: a.ingredients,
        changes: a.changes,
        summary: a.summary,
        status: status,
      );
    }
  }

  @override
  Future<RecipeAdjustment> create(RecipeAdjustment adjustment) async {
    final saved = RecipeAdjustment(
      id: adjustment.documentKey,
      familyId: adjustment.familyId,
      recipeId: adjustment.recipeId,
      baseSignature: adjustment.baseSignature,
      householdSize: adjustment.householdSize,
      householdKey: adjustment.householdKey,
      servings: adjustment.servings,
      ingredients: adjustment.ingredients,
      changes: adjustment.changes,
      summary: adjustment.summary,
      status: adjustment.status,
    );
    created.add(saved);
    return saved;
  }

  @override
  Future<List<RecipeAdjustment>> listForRecipe(
    String familyId,
    String recipeId,
  ) async => [
    for (final a in created)
      if (a.familyId == familyId &&
          a.recipeId == recipeId &&
          !deleted.contains(a.id))
        a,
  ];

  @override
  Future<void> delete(String adjustmentId) async => deleted.add(adjustmentId);

  @override
  Future<void> approve(
    String adjustmentId, {
    required String reviewerUid,
  }) async => calls.add('approve $adjustmentId by $reviewerUid');

  @override
  Future<void> reject(
    String adjustmentId, {
    required String reviewerUid,
    required String reason,
  }) async => calls.add('reject $adjustmentId by $reviewerUid: $reason');
}

class _Fakes {
  _Fakes({
    required List<Member> members,
    domain.Recipe? recipe,
    RecipePlanner? planner,
  }) : recipes = _FakeRecipes()..stored = recipe ?? domainRecipe(),
       household = _FakeMembers(members),
       adjustments = _FakeAdjustments() {
    facade = BankStorageFacade(
      planner: planner,
      families: _FakeFamilies(),
      pantry: _FakePantry(),
      members: household,
      recipes: recipes,
      mealPlans: _FakeMealPlans(),
      adjustments: adjustments,
      firestore: _FakeFirestore(),
    );
  }

  final _FakeRecipes recipes;
  final _FakeMembers household;
  final _FakeAdjustments adjustments;
  late final BankStorageFacade facade;
}

/// Un motor distinto del de reglas: la fachada y las pantallas no cambian.
class _OtherEngine implements RecipePlanner {
  _OtherEngine({this.none = false});

  final bool none;
  AdjustmentContext? received;

  @override
  Future<RecipeAdjustmentSuggestion?> suggestAdjustment({
    required AdjustmentContext household,
    required domain.Recipe recipe,
  }) async {
    received = household;
    if (none) return null;
    return RecipeAdjustmentSuggestion(
      recipeId: recipe.id,
      baseSignature: recipeSignature(recipe),
      householdSize: household.householdSize,
      householdKey: household.householdKey,
      servings: 4,
      ingredients: const [
        domain.RecipeIngredient(
          productName: 'Bebida de coco',
          quantity: 1,
          unit: 'l',
        ),
      ],
      changes: const [
        AdjustmentChange(
          kind: AdjustmentChange.kindSubstitution,
          reason: 'alergia a lácteos',
          from: 'Leche entera',
          to: 'Bebida de coco',
        ),
      ],
      summary: 'Sugerido por otro motor',
    );
  }

  @override
  Future<domain.Recipe?> suggestRecipe({
    required FamilyProfile family,
    required List<domain_pantry.PantryItem> pantryItems,
    required List<domain.Recipe> recipes,
    DateTime? now,
  }) async => null;

  @override
  Future<MealPlanGeneration> planDays({
    required FamilyProfile family,
    required List<domain_pantry.PantryItem> pantryItems,
    required List<domain.Recipe> recipes,
    required int days,
    DateTime? startDate,
    DateTime? now,
  }) => throw UnimplementedError();
}
