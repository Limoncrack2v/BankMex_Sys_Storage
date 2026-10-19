import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/member.dart';
import 'package:bank_storage_app/data/models/pantry_item.dart';
import 'package:bank_storage_app/domain/models/meal_plan.dart';
import 'package:bank_storage_app/ui/models/recipe.dart';
import 'package:bank_storage_app/ui/sample_data.dart';
import 'package:bank_storage_app/ui/screens/meal_plan/meal_plan_saving.dart';
import 'package:bank_storage_app/ui/screens/meal_plan/meal_plan_screen.dart';
import 'package:bank_storage_app/ui/screens/meal_plan/saved_meal_plan_view.dart';
import 'package:bank_storage_app/ui/screens/profile/appliances_section.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:bank_storage_app/ui/widgets/app_buttons.dart';

import 'helpers/large_text.dart';

/// Miércoles a media mañana.
final today = DateTime(2026, 10, 14, 9, 30);

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
      localTimestamp: DateTime(2026, 10, 14),
    );

final pantry = [
  item('Leche entera', 1, FoodUnit.l, 1),
  item('Arroz', 2, FoodUnit.kg, 200),
  item('Lenteja', 1, FoodUnit.kg, 10),
];

final members = [
  for (final name in ['Ana', 'Luis'])
    Member(
      memberId: name,
      name: name,
      memberType: MemberType.adult,
      createdAt: DateTime(2026, 9, 1),
    ),
];

Future<void> pumpView(WidgetTester tester, Widget view) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: view),
  ),
);

Future<List<MealPlan>> pumpSuggested(
  WidgetTester tester, {
  List<Recipe> recipes = SampleData.recipes,
  FutureOr<void> Function(MealPlan plan)? save,
  bool canSave = true,
  List<String> warnings = const [],
  List<Member>? household,
  List<PantryItem>? items,
}) async {
  final saved = <MealPlan>[];
  await pumpView(
    tester,
    SuggestedPlanView(
      familyId: 'famA',
      recipes: recipes,
      members: household ?? members,
      pantry: items ?? pantry,
      nextDelivery: null,
      warnings: warnings,
      clock: () => today,
      onOpenRecipe: (_) {},
      onSave: canSave
          ? (plan) async {
              saved.add(plan);
              await save?.call(plan);
            }
          : null,
    ),
  );
  return saved;
}

Future<void> tapSave(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.text('Guardar este plan'), 300);
  await tester.tap(find.text('Guardar este plan'));
  await tester.pump();
}

MealPlanMeal meal(int day, String recipeId) => MealPlanMeal(
  date: DateTime(2026, 10, day),
  recipeId: recipeId,
  servings: 2,
);

/// De lunes 12 a domingo 18 de octubre. Hoy es miércoles 14.
MealPlan savedPlan({List<MealPlanMeal>? meals}) => MealPlan(
  id: 'plan1',
  familyId: 'famA',
  dateRangeStart: DateTime(2026, 10, 12),
  dateRangeEnd: DateTime(2026, 10, 19),
  meals:
      meals ??
      [
        meal(12, 'rec_frijoles'),
        meal(13, 'rec_arroz_atun'),
        meal(14, 'rec_avena_fruta'),
        meal(15, 'rec_sopa_lentejas'),
        meal(17, 'rec_borrada'),
        meal(18, 'rec_sandwich'),
      ],
);

Future<List<Recipe>> pumpSaved(
  WidgetTester tester, {
  MealPlan? plan,
  bool pendingSync = false,
  DateTime? now,
  bool catalogFailed = false,
  List<PantryItem>? items,
}) async {
  final opened = <Recipe>[];
  await pumpView(
    tester,
    SavedPlanView(
      plan: plan ?? savedPlan(),
      pendingSync: pendingSync,
      recipes: SampleData.recipes,
      members: members,
      pantry: items ?? pantry,
      today: now ?? today,
      catalogFailed: catalogFailed,
      onOpenRecipe: opened.add,
      onSaveMeals: (_) async {},
      onDelete: () async {},
    ),
  );
  return opened;
}

void main() {
  group('SuggestedPlanView', () {
    testWidgets('shows the plan of the pantry and offers to save it', (
      tester,
    ) async {
      await pumpSuggested(tester);

      expect(
        find.text('Tu plan usa primero lo que caduca antes'),
        findsOneWidget,
      );
      expect(find.text('MIÉ'), findsOneWidget);
      expect(find.textContaining('Usa Leche entera'), findsWidgets);
      expect(
        find.text(
          'Al guardarlo, las recetas de cada día ya no cambian y puedes '
          'cambiarlas tú.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the save button goes below the banner, before the days', (
      tester,
    ) async {
      await pumpSuggested(tester);

      final button = tester.getRect(find.text('Guardar este plan'));
      expect(
        button.top,
        greaterThan(
          tester
              .getRect(find.text('Tu plan usa primero lo que caduca antes'))
              .bottom,
        ),
      );
      expect(button.bottom, lessThan(tester.getRect(find.text('MIÉ')).top));
    });

    testWidgets('saves the days that are shown, from today at midnight', (
      tester,
    ) async {
      final saved = await pumpSuggested(tester);
      final shown = buildMealPlan(
        [
          for (final recipe in SampleData.recipes)
            scaledForHousehold(recipe, members),
        ],
        pantry,
        today: today,
      );

      await tapSave(tester);
      await tester.pump();

      final plan = saved.single;
      expect(plan.familyId, 'famA');
      expect(plan.dateRangeStart, DateTime(2026, 10, 14));
      expect(plan.dateRangeEnd, DateTime(2026, 10, 21));
      expect(plan.meals.map((m) => m.date), [for (final e in shown) e.date]);
      expect(plan.meals.map((m) => m.recipeId), [
        for (final e in shown) e.recipe.id,
      ]);
      expect(plan.meals.map((m) => m.servings), everyElement(2));
      // Confirma con la palomita, no con un snackbar.
      await tester.pumpAndSettle();
      expect(find.text('Plan guardado'), findsOneWidget);
      expect(
        find.text(
          'Las recetas de cada día ya no cambian. Puedes cambiar un día o '
          'dejarlo libre.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('saves the portions the household eats, not its size', (
      tester,
    ) async {
      // Una niña de 5 años come menos que un adulto: 2.5 porciones, no 3.
      final household = [
        ...members,
        Member(
          memberId: 'Sofía',
          name: 'Sofía',
          memberType: MemberType.child,
          createdAt: DateTime(2026, 9, 1),
          age: 5,
          weightKg: 19,
        ),
      ];
      final saved = await pumpSuggested(tester, household: household);

      await tapSave(tester);

      final servings = planServings(household, SampleData.avenaConFruta);
      expect(servings, isNot(household.length));
      expect(saved.single.meals.map((m) => m.servings), everyElement(servings));
    });

    testWidgets('a recipe without a catalog id cannot be saved', (
      tester,
    ) async {
      const noId = Recipe(
        name: 'Receta sin id',
        image: '',
        minutes: 10,
        servings: 2,
        kcalPerServing: 100,
        ingredients: [RecipeIngredient('Arroz', 0.2, FoodUnit.kg)],
        steps: ['Cocinar.'],
      );
      await pumpSuggested(tester, recipes: const [noId]);

      await tester.scrollUntilVisible(
        find.text(
          'Para guardar tu plan hacen falta recetas del catálogo de BAMX.',
        ),
        300,
      );
      expect(find.text('Guardar este plan'), findsNothing);
    });

    testWidgets('without saving it says why: its warnings or the catalog', (
      tester,
    ) async {
      await pumpSuggested(tester, canSave: false, warnings: ['Sin conexión.']);
      expect(find.text('Sin conexión.'), findsOneWidget);
      expect(find.textContaining('Para guardar tu plan'), findsNothing);
      expect(find.text('Guardar este plan'), findsNothing);

      await pumpSuggested(tester, canSave: false);
      expect(
        find.text(
          'Para guardar tu plan hacen falta recetas del catálogo de BAMX.',
        ),
        findsOneWidget,
      );
      expect(find.text('Guardar este plan'), findsNothing);
    });

    testWidgets('offline it waits 4 seconds and says it will sync', (
      tester,
    ) async {
      final server = Completer<void>();
      final saved = await pumpSuggested(tester, save: (_) => server.future);

      await tapSave(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(find.textContaining('Plan guardado'), findsNothing);
      // Mientras espera, el botón no guarda otra vez.
      await tester.tap(find.byType(PrimaryButton));

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Plan guardado'), findsOneWidget);
      expect(
        find.text(
          'Las recetas de cada día ya no cambian. Puedes cambiar un día o '
          'dejarlo libre. Se sincronizará cuando haya conexión.',
        ),
        findsOneWidget,
      );
      expect(saved, hasLength(1));
    });

    testWidgets('a save the server rejects after the wait says so', (
      tester,
    ) async {
      final server = Completer<void>();
      await pumpSuggested(tester, save: (_) => server.future);

      await tapSave(tester);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Se sincronizará cuando haya conexión.'),
        findsOneWidget,
      );

      server.completeError(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'No se pudo guardar tu plan. Revisa tu conexión e intenta de nuevo.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a rejected save says so and can be tried again', (
      tester,
    ) async {
      final saved = await pumpSuggested(
        tester,
        save: (_) => throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        ),
      );

      await tapSave(tester);
      await tester.pump();

      expect(
        find.text('No se pudo guardar tu plan. Intenta de nuevo.'),
        findsOneWidget,
      );
      expect(saved, hasLength(1));
      // El botón deja de cargar para volver a intentarlo.
      expect(find.text('Guardar este plan'), findsOneWidget);
    });
  });

  group('SavedPlanView', () {
    testWidgets('one card per day from today to the last day of the plan', (
      tester,
    ) async {
      await pumpSaved(tester);

      expect(
        find.text('Tu plan guardado: del 12 al 18 de octubre'),
        findsOneWidget,
      );
      // Lunes 12 y martes 13 ya pasaron.
      expect(find.text('LUN'), findsNothing);
      expect(find.text('MAR'), findsNothing);
      expect(find.text('MIÉ'), findsOneWidget);
      expect(find.text('Avena con fruta'), findsOneWidget);
      expect(find.text('Sopa de lentejas'), findsOneWidget);
      expect(find.text('Frijoles de la olla'), findsNothing);
      await tester.scrollUntilVisible(find.text('DOM'), 300);
      expect(find.text('Sándwich de jamón y queso'), findsOneWidget);
    });

    testWidgets('a day without a meal is free and a missing recipe is not '
        'available', (tester) async {
      await pumpSaved(tester);

      expect(find.text('VIE'), findsOneWidget);
      expect(find.text('Día libre'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Receta no disponible'), 300);
      expect(
        find.text('La receta que guardaste ya no está en el catálogo de BAMX.'),
        findsOneWidget,
      );
    });

    testWidgets('without the catalog a missing recipe is not called gone', (
      tester,
    ) async {
      await pumpSaved(tester, catalogFailed: true);

      await tester.scrollUntilVisible(find.text('SÁB'), 300);
      expect(find.text('Receta sin cargar'), findsOneWidget);
      expect(find.text('No pudimos cargar esta receta.'), findsOneWidget);
      expect(find.text('Receta no disponible'), findsNothing);
      expect(find.textContaining('ya no está en el catálogo'), findsNothing);
    });

    testWidgets('a card counts what expires on its date, like the suggestion', (
      tester,
    ) async {
      // La leche caduca el jueves. Hoy es miércoles, así que la tarjeta del
      // jueves dice "caduca ese día", no "hoy" ni "mañana".
      await pumpSaved(
        tester,
        plan: savedPlan(meals: [meal(15, 'rec_avena_fruta')]),
      );

      expect(find.text('JUE'), findsOneWidget);
      expect(
        find.textContaining('Usa Leche entera (caduca ese día)'),
        findsOneWidget,
      );
      expect(find.textContaining('caduca hoy'), findsNothing);
      expect(find.textContaining('caduca mañana'), findsNothing);
    });

    testWidgets('a card counts what the days before it use, like the '
        'suggestion', (tester) async {
      // Lenteja para dos sopas. El jueves libre y la receta borrada del
      // viernes no usan nada.
      await pumpSaved(
        tester,
        items: [
          item('Lenteja', 0.25, FoodUnit.kg, 5),
          item('Arroz', 2, FoodUnit.kg, 200),
        ],
        plan: savedPlan(
          meals: [
            meal(14, 'rec_sopa_lentejas'),
            meal(16, 'rec_borrada'),
            meal(17, 'rec_sopa_lentejas'),
            meal(18, 'rec_sopa_lentejas'),
          ],
        ),
      );

      expect(
        find.text('Usa Lenteja (caduca en 5 días)\nTe faltan 3 ingredientes'),
        findsOneWidget,
      );
      final saturday = find.text(
        'Usa Lenteja (caduca el lun 19)\nTe faltan 3 ingredientes',
      );
      await tester.scrollUntilVisible(saturday, 300);
      expect(saturday, findsOneWidget);
      // El sábado se acaba la lenteja que quedaba.
      final sunday = find.text('Te faltan 4 ingredientes');
      await tester.scrollUntilVisible(sunday, 300);
      expect(sunday, findsOneWidget);
      final usedUp = find.text('El plan usa por completo: Lenteja.');
      await tester.scrollUntilVisible(usedUp, 300);
      expect(usedUp, findsOneWidget);
    });

    testWidgets('a plan saved right away shows the cards of the suggestion', (
      tester,
    ) async {
      // Alto para que se construyan todas las tarjetas.
      tester.view.physicalSize = const Size(800, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // El jitomate se acaba a media semana.
      final items = [
        item('Leche entera', 1, FoodUnit.l, 3),
        item('Plátano', 4, FoodUnit.piece, 4),
        item('Lenteja', 0.25, FoodUnit.kg, 6),
        item('Jitomate', 0.3, FoodUnit.kg, 5),
        item('Arroz', 2, FoodUnit.kg, 200),
        item('Frijol', 0.2, FoodUnit.kg, 90),
      ];
      final reason = RegExp('^(Usa |Te falta|Con productos)');
      List<String> reasons() => [
        for (final text in tester.widgetList<Text>(find.byType(Text)))
          if (reason.hasMatch(text.data ?? '')) text.data!,
      ];

      final saved = await pumpSuggested(tester, items: items);
      final suggested = reasons();
      await tapSave(tester);
      await pumpSaved(tester, plan: saved.single, items: items);

      expect(suggested, hasLength(7));
      expect(reasons(), suggested);
    });

    testWidgets('tapping a day opens the original recipe', (tester) async {
      final opened = await pumpSaved(tester);

      await tester.tap(find.text('Avena con fruta'));
      await tester.tap(find.text('Día libre'));

      expect(opened, [same(SampleData.avenaConFruta)]);
    });

    testWidgets('says when the plan still has to sync', (tester) async {
      await pumpSaved(tester, pendingSync: true);
      expect(find.text(pendingSyncLabel), findsOneWidget);

      await pumpSaved(tester);
      expect(find.text(pendingSyncLabel), findsNothing);
    });

    testWidgets('names both months when the plan crosses into the next one', (
      tester,
    ) async {
      await pumpSaved(
        tester,
        now: DateTime(2026, 10, 2),
        plan: MealPlan(
          id: 'plan2',
          familyId: 'famA',
          dateRangeStart: DateTime(2026, 9, 28),
          dateRangeEnd: DateTime(2026, 10, 12),
          meals: const [],
        ),
      );

      expect(
        find.text('Tu plan guardado: del 28 de septiembre al 11 de octubre'),
        findsOneWidget,
      );
      expect(find.text('VIE'), findsOneWidget);
    });

    testWidgets('what is left counts only the recipes from today on', (
      tester,
    ) async {
      await pumpSaved(
        tester,
        plan: savedPlan(meals: [meal(12, 'rec_sopa_lentejas')]),
      );
      // La sopa fue el lunes: hoy en adelante el plan está libre.
      expect(find.text('Lo que te sobra'), findsNothing);

      await pumpSaved(
        tester,
        plan: savedPlan(meals: [meal(14, 'rec_sopa_lentejas')]),
      );
      await tester.scrollUntilVisible(find.text('Lo que te sobra'), 300);
      expect(find.text('Lenteja'), findsOneWidget);
    });
  });

  group("at Android's largest text (2x) on a 360 wide screen", () {
    setUpAll(loadAppFonts);

    void useLargestText(WidgetTester tester) {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    testWidgets('the date box of a suggested day grows with the text', (
      tester,
    ) async {
      useLargestText(tester);
      await pumpSuggested(tester);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('MIÉ'), findsOneWidget);
    });

    testWidgets('the date box of a saved day grows with the text', (
      tester,
    ) async {
      useLargestText(tester);
      await pumpSaved(tester);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('MIÉ'), findsOneWidget);
    });
  });
}
