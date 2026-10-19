import 'dart:async';

import 'package:bank_storage_app/data/models/app_user.dart';
import 'package:bank_storage_app/data/models/member.dart';
import 'package:bank_storage_app/data/repositories/auth_repository.dart';
import 'package:bank_storage_app/domain/models/recipe.dart';
import 'package:bank_storage_app/domain/models/recipe_adjustment.dart';
import 'package:bank_storage_app/ui/screens/nutritionist/adjustment_queue.dart';
import 'package:bank_storage_app/ui/screens/nutritionist/nutritionist_home_screen.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:bank_storage_app/ui/widgets/app_bottom_sheet.dart';
import 'package:bank_storage_app/ui/widgets/app_buttons.dart';
import 'package:bank_storage_app/ui/widgets/pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/adjustment_fixtures.dart';
import 'helpers/large_text.dart';

final _avena = avenaConFruta;

Future<void> _pumpQueue(
  WidgetTester tester, {
  required Stream<List<RecipeAdjustment>> adjustments,
  required Stream<List<Recipe>> recipes,
}) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            AdjustmentQueue(
              adjustments: adjustments,
              approvedRecipes: recipes,
              reviewerUid: 'nutri1',
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}

double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

void main() {
  group('adjustmentQueue', () {
    test('joins each adaptation with its published recipe and household', () {
      final item = adjustmentQueue(
        [pendingAdjustment(_avena)],
        [_avena],
      ).single;

      expect(item.recipe, same(_avena));
      expect(item.allergies, [Allergy.dairy, Allergy.gluten]);
      expect(item.staleness, isNull);
      expect(item.title, 'Avena con fruta');
      expect(item.quotedName, '«Avena con fruta»');
      expect(
        item.changesLine,
        'Porciones: 2 → 3 · Avena → Amaranto · Leche entera → Bebida de arroz',
      );
    });

    test('puts the oldest first, then the ones without a date, by id', () {
      final items = adjustmentQueue(
        [
          pendingAdjustment(_avena, id: 'c', createdAt: DateTime(2026, 10, 10)),
          pendingAdjustment(_avena, id: 'e'),
          pendingAdjustment(_avena, id: 'b', createdAt: DateTime(2026, 10, 8)),
          pendingAdjustment(_avena, id: 'd'),
          pendingAdjustment(_avena, id: 'a', createdAt: DateTime(2026, 10, 10)),
        ],
        [_avena],
      );

      expect(items.map((item) => item.adjustment.id), [
        'b',
        'a',
        'c',
        'd',
        'e',
      ]);
    });

    test('a recipe that is no longer published is unavailable', () {
      final item = adjustmentQueue([
        pendingAdjustment(_avena),
      ], const []).single;

      expect(item.recipe, isNull);
      expect(item.staleness, AdjustmentStaleness.unavailable);
      expect(item.title, 'Receta no disponible');
      expect(item.quotedName, 'esta receta');
      // Sin la receta no se sabe cuántas porciones daba.
      expect(item.portionsLabel, 'Porciones: 3');
    });

    test('a recipe edited after the suggestion has changed', () {
      final edited = approvedRecipe('r1', 'Avena con fruta', servings: 4);
      final item = adjustmentQueue(
        [pendingAdjustment(_avena)],
        [edited],
      ).single;

      expect(item.staleness, AdjustmentStaleness.changed);
      // Las porciones de ahora no son las de la receta que se adaptó.
      expect(item.portionsLabel, 'Porciones: 3');
    });

    test('an allergen of the household left in the adaptation is unsafe', () {
      final item = adjustmentQueue(
        [
          pendingAdjustment(
            _avena,
            ingredients: const [
              RecipeIngredient(
                productName: 'Amaranto',
                quantity: 0.15,
                unit: 'kg',
              ),
              RecipeIngredient(
                productName: 'Leche entera',
                quantity: 0.75,
                unit: 'l',
              ),
            ],
          ),
        ],
        [_avena],
      ).single;

      expect(item.staleness, AdjustmentStaleness.unsafe);
      expect(item.allergenIngredient, 'Leche entera');
    });

    test('a missing or edited recipe wins over an allergen', () {
      final unsafe = pendingAdjustment(
        _avena,
        ingredients: const [
          RecipeIngredient(
            productName: 'Leche entera',
            quantity: 0.75,
            unit: 'l',
          ),
        ],
      );
      final edited = approvedRecipe('r1', 'Avena con fruta', servings: 4);

      expect(
        adjustmentQueue([unsafe], const []).single.staleness,
        AdjustmentStaleness.unavailable,
      );
      expect(
        adjustmentQueue([unsafe], [edited]).single.staleness,
        AdjustmentStaleness.changed,
      );
    });
  });

  group('AdjustmentQueue', () {
    testWidgets('lists them oldest first, the ones without a date last', (
      tester,
    ) async {
      final sopa = approvedRecipe('r2', 'Sopa de lentejas');
      final arroz = approvedRecipe('r3', 'Arroz con atún');
      await _pumpQueue(
        tester,
        adjustments: Stream.value([
          pendingAdjustment(arroz),
          pendingAdjustment(sopa, createdAt: DateTime(2026, 10, 10)),
          pendingAdjustment(_avena, createdAt: DateTime(2026, 10, 8)),
        ]),
        recipes: Stream.value([_avena, sopa, arroz]),
      );

      expect(
        _top(tester, 'Avena con fruta'),
        lessThan(_top(tester, 'Sopa de lentejas')),
      );
      expect(
        _top(tester, 'Sopa de lentejas'),
        lessThan(_top(tester, 'Arroz con atún')),
      );
    });

    testWidgets('shows the recipe, the household and what changes', (
      tester,
    ) async {
      await _pumpQueue(
        tester,
        adjustments: Stream.value([pendingAdjustment(_avena)]),
        recipes: Stream.value([_avena]),
      );

      expect(find.text('Adaptaciones por revisar'), findsOneWidget);
      expect(find.text('Avena con fruta'), findsOneWidget);
      expect(
        find.text('Hogar de 4 integrantes · Alergias: Lácteos, Gluten'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Porciones: 2 → 3 · Avena → Amaranto · Leche entera → Bebida de '
          'arroz',
        ),
        findsOneWidget,
      );
      expect(find.text('Revisar'), findsOneWidget);
      // El resumen es para la familia ("tu hogar"): la tarjeta no lo usa.
      expect(find.textContaining('tu hogar'), findsNothing);
      expect(find.byType(Pill), findsNothing);
    });

    testWidgets('says 1 integrante and Sin alergias for one person', (
      tester,
    ) async {
      await _pumpQueue(
        tester,
        adjustments: Stream.value([
          pendingAdjustment(
            _avena,
            householdSize: 1,
            householdKey: '1',
            servings: 1,
            changes: const [portionsChange],
          ),
        ]),
        recipes: Stream.value([_avena]),
      );

      expect(find.text('Hogar de 1 integrante · Sin alergias'), findsOneWidget);
      expect(find.text('Porciones: 2 → 1'), findsOneWidget);
    });

    testWidgets('never shows the family, its id or the document id', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final adjustment = pendingAdjustment(_avena);
      await _pumpQueue(
        tester,
        adjustments: Stream.value([adjustment]),
        recipes: Stream.value([_avena]),
      );

      expect(adjustment.id, contains('famA'));
      expect(find.textContaining('famA'), findsNothing);
      expect(find.textContaining('Familia'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('famA')), findsNothing);
      semantics.dispose();
    });

    testWidgets('each card is a button named after the recipe and household', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpQueue(
        tester,
        adjustments: Stream.value([pendingAdjustment(_avena)]),
        recipes: Stream.value([_avena]),
      );

      expect(
        tester.getSemantics(
          find.bySemanticsLabel(
            RegExp(
              '^Revisar la adaptación de Avena con fruta para un hogar de 4 '
              'integrantes',
            ),
          ),
        ),
        isSemantics(isButton: true, hasTapAction: true),
      );
      semantics.dispose();
    });

    testWidgets('tapping a card opens its review', (tester) async {
      await _pumpQueue(
        tester,
        adjustments: Stream.value([pendingAdjustment(_avena)]),
        recipes: Stream.value([_avena]),
      );

      await tester.tap(find.text('Avena con fruta'));
      await tester.pumpAndSettle();

      expect(find.text('Volver a la lista'), findsOneWidget);
      expect(
        find.text('Adaptación para un hogar de 4 integrantes'),
        findsOneWidget,
      );
    });

    testWidgets('says so when there is nothing to review', (tester) async {
      await _pumpQueue(
        tester,
        adjustments: Stream.value(const []),
        recipes: Stream.value([_avena]),
      );

      expect(find.text('No hay adaptaciones por revisar.'), findsOneWidget);
    });

    testWidgets('an empty queue does not wait for the recipes', (tester) async {
      final recipes = StreamController<List<Recipe>>();
      addTearDown(recipes.close);
      await _pumpQueue(
        tester,
        adjustments: Stream.value(const []),
        recipes: recipes.stream,
      );

      expect(find.text('No hay adaptaciones por revisar.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Sin adaptaciones, un error de las recetas no importa.
      recipes.addError(StateError('permission-denied'));
      await tester.pump();
      expect(find.text('No hay adaptaciones por revisar.'), findsOneWidget);
      expect(
        find.textContaining('No se pudieron cargar las adaptaciones'),
        findsNothing,
      );
    });

    testWidgets('shows a labeled spinner while the adaptations load', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final adjustments = StreamController<List<RecipeAdjustment>>();
      addTearDown(adjustments.close);
      await _pumpQueue(
        tester,
        adjustments: adjustments.stream,
        recipes: Stream.value([_avena]),
      );

      final spinner = find.bySemanticsLabel(RegExp('Cargando adaptaciones'));
      expect(spinner, findsOneWidget);

      adjustments.add([pendingAdjustment(_avena)]);
      await tester.pump();
      expect(spinner, findsNothing);
      expect(find.text('Avena con fruta'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('shows a labeled spinner while the recipes load', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final recipes = StreamController<List<Recipe>>();
      addTearDown(recipes.close);
      await _pumpQueue(
        tester,
        adjustments: Stream.value([pendingAdjustment(_avena)]),
        recipes: recipes.stream,
      );

      final spinner = find.bySemanticsLabel(RegExp('Cargando adaptaciones'));
      expect(spinner, findsOneWidget);
      expect(find.text('Avena con fruta'), findsNothing);

      recipes.add([_avena]);
      await tester.pump();
      expect(spinner, findsNothing);
      expect(find.text('Avena con fruta'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('shows an error when the adaptations cannot be loaded', (
      tester,
    ) async {
      await _pumpQueue(
        tester,
        adjustments: Stream.error(StateError('permission-denied')),
        recipes: Stream.value([_avena]),
      );

      expect(
        find.text(
          'No se pudieron cargar las adaptaciones. Revisa tu conexión e '
          'intenta de nuevo.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows the same error when the recipes cannot be loaded', (
      tester,
    ) async {
      await _pumpQueue(
        tester,
        adjustments: Stream.value([pendingAdjustment(_avena)]),
        recipes: Stream.error(StateError('permission-denied')),
      );

      expect(
        find.textContaining('No se pudieron cargar las adaptaciones'),
        findsOneWidget,
      );
      // No las marca como "no disponible" por no poder leer las recetas.
      expect(find.text('Receta no disponible'), findsNothing);
    });

    testWidgets('marks the ones the family would never see', (tester) async {
      final sopa = approvedRecipe('r2', 'Sopa de lentejas');
      final arroz = approvedRecipe('r3', 'Arroz con atún');
      final frijoles = approvedRecipe('r4', 'Frijoles de la olla');
      await _pumpQueue(
        tester,
        adjustments: Stream.value([
          pendingAdjustment(sopa, createdAt: DateTime(2026, 10, 1)),
          pendingAdjustment(arroz, createdAt: DateTime(2026, 10, 2)),
          pendingAdjustment(
            frijoles,
            createdAt: DateTime(2026, 10, 3),
            ingredients: const [
              RecipeIngredient(
                productName: 'Queso panela',
                quantity: 0.2,
                unit: 'kg',
              ),
            ],
          ),
          pendingAdjustment(_avena, createdAt: DateTime(2026, 10, 4)),
        ]),
        recipes: Stream.value([
          // La sopa se editó después de la sugerencia; el arroz ya no está
          // publicado.
          approvedRecipe('r2', 'Sopa de lentejas', servings: 5),
          frijoles,
          _avena,
        ]),
      );

      expect(find.text('La receta cambió'), findsOneWidget);
      // El título de la que ya no está publicada y su aviso.
      expect(find.text('Receta no disponible'), findsNWidgets(2));
      expect(find.text('Lleva un alérgeno'), findsOneWidget);
      expect(find.byType(Pill), findsNWidgets(3));
      // La de la avena se puede aprobar: no lleva aviso.
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Avena con fruta'),
            matching: find.byType(InkWell),
          ),
          matching: find.byType(Pill),
        ),
        findsNothing,
      );
    });

    testWidgets('without the recipe the portions say only the new number', (
      tester,
    ) async {
      await _pumpQueue(
        tester,
        adjustments: Stream.value([pendingAdjustment(_avena)]),
        recipes: Stream.value(const []),
      );

      expect(
        find.text(
          'Porciones: 3 · Avena → Amaranto · Leche entera → Bebida de arroz',
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('the home shows the queue 32 px after the recipes to review', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: NutritionistHomeScreen(
          session: AuthSession(
            user: AppUser(
              userId: 'nutri1',
              name: 'Ana Nutrióloga',
              email: 'ana@bamx.test',
              role: AppUser.roleNutritionist,
              createdAt: DateTime(2026, 10, 16),
            ),
          ),
          pendingRecipes: Stream.value(const []),
          pendingAdjustments: Stream.value([pendingAdjustment(_avena)]),
          approvedRecipes: Stream.value([_avena]),
        ),
      ),
    );
    await tester.pump();

    final recipesEnd = tester
        .getBottomLeft(find.text('No hay recetas por revisar.'))
        .dy;
    expect(_top(tester, 'Adaptaciones por revisar') - recipesEnd, 32);
    expect(find.text('Avena con fruta'), findsOneWidget);
  });

  testWidgets('approving from the home confirms there once the card is gone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pending = StreamController<List<RecipeAdjustment>>();
    addTearDown(pending.close);
    final adjustment = pendingAdjustment(_avena);
    final log = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: NutritionistHomeScreen(
          session: AuthSession(
            user: AppUser(
              userId: 'nutri1',
              name: 'Ana Nutrióloga',
              email: 'ana@bamx.test',
              role: AppUser.roleNutritionist,
              createdAt: DateTime(2026, 10, 16),
            ),
          ),
          pendingRecipes: Stream.value(const []),
          pendingAdjustments: pending.stream,
          approvedRecipes: Stream.value([_avena]),
          approveAdjustment: (id) async {
            log.add('approve $id');
            // Como en Firestore: la decidida sale de la lista enseguida.
            pending.add(const []);
          },
          confirmIdentity: (_) async {
            log.add('confirm');
            return true;
          },
        ),
      ),
    );
    pending.add([adjustment]);
    await tester.pump();

    await tester.tap(find.text('Avena con fruta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aprobar adaptación'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AppSheet),
        matching: find.byType(PrimaryButton),
      ),
    );
    await tester.pumpAndSettle();

    expect(log, ['confirm', 'approve ${adjustment.id}']);
    expect(find.text('No hay adaptaciones por revisar.'), findsOneWidget);
    expect(find.text('Adaptación aprobada'), findsOneWidget);
    expect(
      find.text('La familia ya verá la versión adaptada de «Avena con fruta».'),
      findsOneWidget,
    );
  });

  group('with large text on a 360 wide screen', () {
    setUpAll(loadAppFonts);

    for (final scale in [1.3, 2.0]) {
      testWidgets('at ${scale}x no word breaks and nothing overflows', (
        tester,
      ) async {
        final sandwich = approvedRecipe('r2', 'Sándwich de jamón y queso');
        await pumpWithTextScale(
          tester,
          ListView(
            padding: const EdgeInsets.all(24),
            children: [
              AdjustmentQueue(
                adjustments: Stream.value([
                  pendingAdjustment(_avena, createdAt: DateTime(2026, 10, 1)),
                  pendingAdjustment(sandwich, createdAt: DateTime(2026, 10, 2)),
                  pendingAdjustment(
                    approvedRecipe('r3', 'Sopa de pasta con verduras'),
                    createdAt: DateTime(2026, 10, 3),
                    householdKey: '4-dairy-egg-gluten-peanut',
                  ),
                ]),
                approvedRecipes: Stream.value([
                  _avena,
                  approvedRecipe(
                    'r2',
                    'Sándwich de jamón y queso',
                    servings: 4,
                  ),
                ]),
                reviewerUid: 'nutri1',
              ),
            ],
          ),
          textScale: scale,
          height: 3200,
        );

        expect(find.text('La receta cambió'), findsOneWidget);
        expect(find.text('Receta no disponible'), findsNWidgets(2));
        expectNoBrokenWords(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
