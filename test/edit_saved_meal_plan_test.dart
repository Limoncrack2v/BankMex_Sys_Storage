import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/member.dart';
import 'package:bank_storage_app/data/models/pantry_item.dart';
import 'package:bank_storage_app/domain/meal_plan_edits.dart';
import 'package:bank_storage_app/domain/models/meal_plan.dart';
import 'package:bank_storage_app/ui/models/recipe.dart' show allergyConflicts;
import 'package:bank_storage_app/ui/sample_data.dart';
import 'package:bank_storage_app/ui/screens/meal_plan/delete_meal_plan_sheet.dart';
import 'package:bank_storage_app/ui/screens/meal_plan/edit_plan_day_sheet.dart';
import 'package:bank_storage_app/ui/widgets/app_buttons.dart';
import 'package:bank_storage_app/ui/screens/meal_plan/meal_plan_saving.dart';
import 'package:bank_storage_app/ui/screens/meal_plan/saved_meal_plan_view.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';

/// Miércoles a media mañana.
final today = DateTime(2026, 10, 14, 9, 30);

final pantry = pantryOf([
  ('Leche entera', 1.0, FoodUnit.l, 1),
  ('Arroz', 2.0, FoodUnit.kg, 200),
  ('Lenteja', 1.0, FoodUnit.kg, 10),
]);

List<PantryItem> pantryOf(List<(String, double, FoodUnit, int)> items) => [
  for (final (name, quantity, unit, days) in items)
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
    ),
];

final members = [
  Member(
    memberId: 'ana',
    name: 'Ana',
    memberType: MemberType.adult,
    createdAt: DateTime(2026, 9, 1),
  ),
  Member(
    memberId: 'luis',
    name: 'Luis',
    memberType: MemberType.adult,
    createdAt: DateTime(2026, 9, 1),
    allergies: const [Allergy.dairy],
  ),
];

MealPlanMeal meal(int day, String recipeId) => MealPlanMeal(
  date: DateTime(2026, 10, day),
  recipeId: recipeId,
  servings: 2,
);

/// De lunes 12 a domingo 18 de octubre. El viernes 16 está libre y la receta
/// del sábado 17 ya no está en el catálogo.
final plan = MealPlan(
  id: 'plan1',
  familyId: 'famA',
  dateRangeStart: DateTime(2026, 10, 12),
  dateRangeEnd: DateTime(2026, 10, 19),
  meals: [
    meal(12, 'rec_frijoles'),
    meal(13, 'rec_arroz_atun'),
    meal(14, 'rec_avena_fruta'),
    meal(15, 'rec_sopa_lentejas'),
    meal(17, 'rec_borrada'),
    meal(18, 'rec_sandwich'),
  ],
);

/// Lo que la vista pidió escribir.
class Writes {
  final saved = <MealPlan>[];
  var deletes = 0;
}

/// [write] hace las veces del servidor: lo que regresa (o lanza) es lo que
/// regresaría Firestore.
Future<Writes> pumpSaved(
  WidgetTester tester, {
  FutureOr<void> Function()? write,
  bool canEdit = true,
  List<String> appliances = const [],
  List<Member>? household,
  List<PantryItem>? items,
}) async {
  final writes = Writes();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SavedPlanView(
          plan: plan,
          pendingSync: false,
          recipes: SampleData.recipes,
          members: household ?? members,
          pantry: items ?? pantry,
          today: today,
          appliances: appliances,
          onOpenRecipe: (_) {},
          onSaveMeals: !canEdit
              ? null
              : (changed) async {
                  writes.saved.add(changed);
                  await write?.call();
                },
          onDelete: () async {
            writes.deletes++;
            await write?.call();
          },
        ),
      ),
    ),
  );
  return writes;
}

Finder inSheet(Finder finder) =>
    find.descendant(of: find.byType(EditPlanDaySheet), matching: finder);

Future<void> openDay(WidgetTester tester, String action) async {
  await tester.scrollUntilVisible(find.text(action).first, 200);
  await tester.pumpAndSettle();
  await tester.tap(find.text(action).first);
  await tester.pumpAndSettle();
}

/// Abre el día cuya acción TalkBack lee como [label].
Future<void> openDayNamed(WidgetTester tester, String label) async {
  final action = find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
  );
  await tester.scrollUntilVisible(action, 200);
  await tester.pumpAndSettle();
  await tester.tap(action);
  await tester.pumpAndSettle();
}

/// Toca [recipe] y, si el sheet pide confirmar, confirma.
Future<void> pick(WidgetTester tester, String recipe) async {
  await tester.ensureVisible(inSheet(find.text(recipe)));
  await tester.pumpAndSettle();
  await tester.tap(inSheet(find.text(recipe)));
  await tester.pumpAndSettle();
  final confirm = inSheet(find.byType(PrimaryButton));
  if (confirm.evaluate().isEmpty) return;
  await tester.tap(confirm);
  await tester.pump();
}

Future<void> openDelete(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.text('Eliminar plan'), 300);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Eliminar plan'));
  await tester.pumpAndSettle();
}

/// Que TalkBack lea [finder] en cuanto aparece.
void expectLiveRegion(Finder finder) => expect(
  find.ancestor(
    of: finder,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && (widget.properties.liveRegion ?? false),
    ),
  ),
  findsOneWidget,
);

/// Nunito y Baloo 2 de verdad: sin esto las pruebas miden los textos con una
/// letra de cuadritos.
Future<void> loadFonts() async {
  final nunito = FontLoader('Nunito')
    ..addFont(rootBundle.load('assets/fonts/Nunito-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Nunito-Bold.ttf'));
  final baloo = FontLoader('Baloo2')
    ..addFont(rootBundle.load('assets/fonts/Baloo2-SemiBold.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Baloo2-Bold.ttf'));
  await Future.wait([nunito.load(), baloo.load()]);
}

void main() {
  group('changing a day', () {
    testWidgets('lists the recipes for that day and marks the current one', (
      tester,
    ) async {
      await pumpSaved(tester);

      await openDayNamed(tester, 'Cambiar la receta del jueves 15');

      expect(find.text('Jueves 15 de octubre'), findsOneWidget);
      // Luis es alérgico a los lácteos.
      for (final recipe in SampleData.recipes) {
        expect(
          inSheet(find.text(recipe.name)),
          allergyConflicts(recipe, members).isEmpty
              ? findsOneWidget
              : findsNothing,
          reason: recipe.name,
        );
      }
      expect(inSheet(find.text('Actual')), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Actual'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && (widget.properties.selected ?? false),
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Dejar este día libre'), findsOneWidget);
    });

    testWidgets('picking another recipe saves only that day', (tester) async {
      final writes = await pumpSaved(tester);

      await openDay(tester, 'Cambiar');
      await pick(tester, 'Arroz con atún');
      await tester.pumpAndSettle();

      final saved = writes.saved.single;
      expect(saved.id, 'plan1');
      expect(
        MealPlanEdits.mealOn(saved, DateTime(2026, 10, 14))?.recipeId,
        'rec_arroz_atun',
      );
      expect(MealPlanEdits.mealOn(saved, DateTime(2026, 10, 14))?.servings, 2);
      expect(saved.meals.map((m) => m.recipeId), [
        'rec_frijoles',
        'rec_arroz_atun',
        'rec_arroz_atun',
        'rec_sopa_lentejas',
        'rec_borrada',
        'rec_sandwich',
      ]);
      // Confirma en el mismo sheet, con la palomita, y "Listo" lo cierra.
      expect(find.text('Plan actualizado'), findsOneWidget);
      expect(
        find.text('Cambiaste la receta del miércoles 14.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Listo'));
      await tester.pumpAndSettle();
      expect(find.byType(EditPlanDaySheet), findsNothing);
    });

    testWidgets('a tapped recipe only saves after confirming', (tester) async {
      final writes = await pumpSaved(tester);

      await openDay(tester, 'Cambiar');
      await tester.tap(inSheet(find.text('Arroz con atún')));
      await tester.pumpAndSettle();

      // Un toque por error no cambia el plan: primero pregunta.
      expect(find.text('¿Cambiar la receta del miércoles 14?'), findsOneWidget);
      expect(writes.saved, isEmpty);
      await tester.tap(find.text('Volver'));
      await tester.pumpAndSettle();
      expect(inSheet(find.text('Arroz con atún')), findsOneWidget);
      expect(writes.saved, isEmpty);

      await tester.tap(inSheet(find.text('Arroz con atún')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cambiar receta'));
      await tester.pumpAndSettle();
      expect(writes.saved, hasLength(1));
      expect(find.text('Plan actualizado'), findsOneWidget);
    });

    testWidgets('a picked recipe saves the portions the household eats', (
      tester,
    ) async {
      // Una niña de 5 años come menos que un adulto: 2.5 porciones, no 3.
      final household = [
        ...members,
        Member(
          memberId: 'sofia',
          name: 'Sofía',
          memberType: MemberType.child,
          createdAt: DateTime(2026, 9, 1),
          age: 5,
          weightKg: 19,
        ),
      ];
      final writes = await pumpSaved(tester, household: household);

      await openDay(tester, 'Cambiar');
      await pick(tester, 'Arroz con atún');
      await tester.pumpAndSettle();

      final servings = MealPlanEdits.mealOn(
        writes.saved.single,
        DateTime(2026, 10, 14),
      )!.servings;
      expect(servings, planServings(household, SampleData.arrozConAtun));
      expect(servings, isNot(household.length));
    });

    testWidgets('the current recipe cannot be picked again', (tester) async {
      final writes = await pumpSaved(tester);

      await openDayNamed(tester, 'Cambiar la receta del jueves 15');
      expect(inSheet(find.text('Actual')), findsOneWidget);
      await pick(tester, 'Sopa de lentejas');

      expect(writes.saved, isEmpty);
      expect(find.byType(EditPlanDaySheet), findsOneWidget);
    });

    testWidgets('a day can be left free', (tester) async {
      final writes = await pumpSaved(tester);

      await openDay(tester, 'Cambiar');
      await tester.tap(find.text('Dejar este día libre'));
      await tester.pumpAndSettle();
      expect(find.text('¿Dejar libre el miércoles 14?'), findsOneWidget);
      expect(writes.saved, isEmpty);
      await tester.tap(find.text('Dejar día libre'));
      await tester.pumpAndSettle();

      final saved = writes.saved.single;
      expect(MealPlanEdits.mealOn(saved, DateTime(2026, 10, 14)), isNull);
      expect(saved.meals, hasLength(5));
      expect(find.text('El miércoles 14 quedó libre.'), findsOneWidget);
    });

    testWidgets('a free day can get a recipe', (tester) async {
      final writes = await pumpSaved(tester);

      await openDay(tester, 'Elegir receta');
      expect(find.text('Viernes 16 de octubre'), findsOneWidget);
      expect(inSheet(find.text('Actual')), findsNothing);
      expect(find.text('Dejar este día libre'), findsNothing);

      await pick(tester, 'Frijoles de la olla');
      await tester.pumpAndSettle();

      expect(
        MealPlanEdits.mealOn(
          writes.saved.single,
          DateTime(2026, 10, 16),
        )?.recipeId,
        'rec_frijoles',
      );
      expect(find.text('Elegiste la receta del viernes 16.'), findsOneWidget);
    });

    testWidgets('the options count what expires on that day, like the plan', (
      tester,
    ) async {
      // Sin alergias, para que salga la avena.
      await pumpSaved(tester, household: [members.first]);

      // La leche caduca el jueves: el viernes ya no sale.
      await openDayNamed(tester, 'Cambiar la receta del jueves 15');
      expect(find.text('Jueves 15 de octubre'), findsOneWidget);
      expect(
        inSheet(find.textContaining('Usa Leche entera (caduca ese día)')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();

      await openDay(tester, 'Elegir receta');
      expect(find.text('Viernes 16 de octubre'), findsOneWidget);
      expect(inSheet(find.textContaining('Leche entera')), findsNothing);
    });

    testWidgets('the options see what the days before use, like the plan', (
      tester,
    ) async {
      // Justo la lenteja de una sopa, que el plan tiene el jueves.
      await pumpSaved(
        tester,
        items: pantryOf([
          ('Lenteja', 0.125, FoodUnit.kg, 5),
          ('Arroz', 2.0, FoodUnit.kg, 200),
        ]),
      );

      await openDayNamed(tester, 'Cambiar la receta del jueves 15');
      expect(find.text('Jueves 15 de octubre'), findsOneWidget);
      expect(
        inSheet(find.textContaining('Usa Lenteja (caduca el lun 19)')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();

      // Todavía no caduca, pero la sopa del jueves ya se la acabó.
      await openDay(tester, 'Elegir receta');
      expect(find.text('Viernes 16 de octubre'), findsOneWidget);
      expect(inSheet(find.textContaining('Usa Lenteja')), findsNothing);
    });

    testWidgets('recipes with family allergens are not offered and a '
        'missing appliance goes last', (tester) async {
      await pumpSaved(tester, appliances: const ['estufa']);

      // El miércoles tiene Avena con fruta, que lleva leche.
      await openDay(tester, 'Cambiar');

      double top(String name) => tester.getRect(inSheet(find.text(name))).top;
      expect(
        [
          'Sopa de lentejas',
          'Arroz con atún',
          'Frijoles de la olla',
        ].map(top).reduce(math.max),
        lessThan(top('Sopa de pasta con verduras')),
      );
      expect(inSheet(find.text('Necesita licuadora')), findsOneWidget);
      expect(
        inSheet(
          find.text(
            'Elige qué cocinar este día. Primero van las que puedes preparar '
            'con tu despensa, y entre ellas las que usan lo que caduca antes. '
            'Al final, las que piden algo que no tienes.',
          ),
        ),
        findsOneWidget,
      );
      expect(inSheet(find.text('Avena con fruta')), findsNothing);
      expect(inSheet(find.text('Sándwich de jamón y queso')), findsNothing);
      expect(inSheet(find.text('Actual')), findsNothing);
      expect(
        inSheet(find.text('Contiene alérgenos de tu familia')),
        findsNothing,
      );
    });

    testWidgets('a recipe that is gone can be replaced or freed', (
      tester,
    ) async {
      await pumpSaved(tester);

      await openDay(tester, 'Elegir otra');

      expect(find.text('Sábado 17 de octubre'), findsOneWidget);
      expect(inSheet(find.text('Actual')), findsNothing);
      expect(find.text('Dejar este día libre'), findsOneWidget);
    });

    testWidgets('when it cannot be changed the days have no actions', (
      tester,
    ) async {
      await pumpSaved(tester, canEdit: false);

      await tester.scrollUntilVisible(find.text('Eliminar plan'), 300);
      expect(find.text('Cambiar'), findsNothing);
      expect(find.text('Elegir receta'), findsNothing);
      expect(find.text('Elegir otra'), findsNothing);
    });

    testWidgets('a rejected change keeps the sheet open and says why', (
      tester,
    ) async {
      await pumpSaved(
        tester,
        write: () => throw ArgumentError(
          'Comida 3: Las porciones deben ser mayores a 0 y de hasta 100',
        ),
      );

      await openDay(tester, 'Cambiar');
      await pick(tester, 'Arroz con atún');
      await tester.pump();

      expect(find.byType(EditPlanDaySheet), findsOneWidget);
      expect(
        find.text(
          'Comida 3: Las porciones deben ser mayores a 0 y de hasta 100.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a failed change asks to try again', (tester) async {
      await pumpSaved(
        tester,
        write: () => throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
        ),
      );

      await openDay(tester, 'Cambiar');
      await pick(tester, 'Arroz con atún');
      await tester.pump();

      expect(
        find.text('No se pudo cambiar tu plan. Intenta de nuevo.'),
        findsOneWidget,
      );
      expectLiveRegion(
        find.text('No se pudo cambiar tu plan. Intenta de nuevo.'),
      );
    });

    testWidgets('offline it confirms after 4 seconds and says it will sync', (
      tester,
    ) async {
      final server = Completer<void>();
      final writes = await pumpSaved(tester, write: () => server.future);

      await openDay(tester, 'Cambiar');
      await pick(tester, 'Arroz con atún');
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(EditPlanDaySheet), findsOneWidget);
      // Mientras espera, confirmar otra vez no escribe dos veces.
      await tester.tap(inSheet(find.byType(PrimaryButton)));

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(writes.saved, hasLength(1));
      expect(find.text('Plan actualizado'), findsOneWidget);
      expect(
        find.text(
          'Cambiaste la receta del miércoles 14. Se sincronizará cuando haya '
          'conexión.',
        ),
        findsOneWidget,
      );
    });
  });

  group('a write the server rejects after the wait', () {
    final rejected = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );

    testWidgets('a change says it was not saved', (tester) async {
      final server = Completer<void>();
      await pumpSaved(tester, write: () => server.future);

      await openDay(tester, 'Cambiar');
      await pick(tester, 'Arroz con atún');
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      server.completeError(rejected);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'No se pudo guardar el cambio en tu plan. Revisa tu conexión e '
          'intenta de nuevo.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a deletion says it was not deleted', (tester) async {
      final server = Completer<void>();
      await pumpSaved(tester, write: () => server.future);

      await openDelete(tester);
      await tester.tap(find.text('Eliminar'));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      server.completeError(rejected);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'No se pudo eliminar tu plan. Revisa tu conexión e intenta de nuevo.',
        ),
        findsOneWidget,
      );
    });
  });

  group('deleting the plan', () {
    testWidgets('asks first and cancelling keeps the plan', (tester) async {
      final writes = await pumpSaved(tester);

      await openDelete(tester);

      expect(
        find.text(
          '¿Eliminar tu plan del 12 al 18 de octubre? Volverás a ver el plan '
          'sugerido con lo que hay en tu despensa. Esta acción no se puede '
          'deshacer.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.byType(DeleteMealPlanSheet), findsNothing);
      expect(writes.deletes, 0);
    });

    testWidgets('Eliminar deletes it once and confirms', (tester) async {
      final writes = await pumpSaved(tester);

      await openDelete(tester);
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();

      expect(writes.deletes, 1);
      expect(find.text('Plan eliminado'), findsOneWidget);
      expect(
        find.text(
          'Ahora verás el plan sugerido con lo que hay en tu despensa.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Listo'));
      await tester.pumpAndSettle();
      expect(find.byType(DeleteMealPlanSheet), findsNothing);
    });

    testWidgets('offline it says the deletion will sync', (tester) async {
      final server = Completer<void>();
      await pumpSaved(tester, write: () => server.future);

      await openDelete(tester);
      await tester.tap(find.text('Eliminar'));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Ahora verás el plan sugerido con lo que hay en tu despensa. Se '
          'sincronizará cuando haya conexión.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a failed deletion says so and keeps the sheet', (
      tester,
    ) async {
      await pumpSaved(
        tester,
        write: () => throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        ),
      );

      await openDelete(tester);
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();

      expect(
        find.text('No se pudo eliminar tu plan. Intenta de nuevo.'),
        findsOneWidget,
      );
      expectLiveRegion(
        find.text('No se pudo eliminar tu plan. Intenta de nuevo.'),
      );
      expect(find.text('Plan eliminado'), findsNothing);
    });
  });

  group('with TalkBack', () {
    /// Un botón de al menos 48 dp de alto que TalkBack lee como [label].
    Future<void> expectButton(
      WidgetTester tester,
      String label, {
      bool scroll = true,
    }) async {
      final button = find.bySemanticsLabel(label);
      if (scroll) await tester.scrollUntilVisible(button, 200);
      expect(
        tester.getSemantics(button),
        isSemantics(isButton: true, hasTapAction: true),
        reason: label,
      );
      expect(
        tester.getSize(button).height,
        greaterThanOrEqualTo(48),
        reason: label,
      );
    }

    testWidgets('each action of a day is a button that names the day', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpSaved(tester);

      await expectButton(tester, 'Cambiar la receta del miércoles 14');
      await expectButton(tester, 'Elegir receta para el viernes 16');
      await expectButton(tester, 'Elegir otra receta para el sábado 17');
      await expectButton(tester, 'Eliminar plan del 12 al 18 de octubre');
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      semantics.dispose();
    });

    testWidgets('leaving the day free names the day', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpSaved(tester);

      await openDay(tester, 'Cambiar');

      // El pie del sheet no se desplaza.
      await expectButton(
        tester,
        'Dejar este día libre: miércoles 14',
        scroll: false,
      );
      semantics.dispose();
    });
  });

  group('with large text (1.3x) on a 360 wide screen', () {
    setUpAll(loadFonts);

    void useLargeText(WidgetTester tester) {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    testWidgets('the saved days and their actions fit', (tester) async {
      useLargeText(tester);
      await pumpSaved(tester);

      // La acción va debajo del texto, no junto a la píldora.
      expect(
        tester.getTopLeft(find.text('Cambiar').first).dy,
        greaterThan(
          tester
              .getBottomLeft(
                find.text('Contiene alérgenos de tu familia').first,
              )
              .dy,
        ),
      );
      expect(
        tester.getTopRight(find.text('Urgente').first).dx,
        lessThanOrEqualTo(360 - 16 - 16),
      );
      await tester.scrollUntilVisible(find.text('Eliminar plan'), 300);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the sheets fit', (tester) async {
      useLargeText(tester);
      await pumpSaved(tester);

      await openDay(tester, 'Cambiar');
      await tester.ensureVisible(
        inSheet(find.text('Sopa de pasta con verduras')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();

      await openDay(tester, 'Elegir otra');
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();

      await openDelete(tester);
      expect(find.text('Eliminar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
