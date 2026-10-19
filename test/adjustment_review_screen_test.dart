import 'package:bank_storage_app/domain/models/recipe.dart';
import 'package:bank_storage_app/domain/recipe_adjustment.dart';
import 'package:bank_storage_app/ui/screens/nutritionist/adjustment_queue.dart';
import 'package:bank_storage_app/ui/screens/nutritionist/adjustment_review_screen.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/adjustment_fixtures.dart';
import 'helpers/large_text.dart';

final _avena = avenaConFruta;

/// La adaptación de la avena, con la receta como está publicada ahora
/// ([published]; null si ya no lo está).
AdjustmentQueueItem _item({
  Recipe? published,
  bool unpublished = false,
  List<RecipeIngredient> ingredients = adaptedIngredients,
  List<AdjustmentChange>? changes,
  int householdSize = 4,
  String householdKey = '4-dairy-gluten',
}) => AdjustmentQueueItem(
  pendingAdjustment(
    _avena,
    ingredients: ingredients,
    changes: changes ?? const [portionsChange, oatsChange, milkChange],
    householdSize: householdSize,
    householdKey: householdKey,
  ),
  unpublished ? null : published ?? _avena,
);

/// Una lista con un botón que abre la revisión de [item], como la tarjeta.
Future<void> _open(WidgetTester tester, AdjustmentQueueItem item) async {
  tester.view.physicalSize = const Size(500, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => openAdjustmentReview(context, item: item),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the recipe, the household and what changes and why', (
    tester,
  ) async {
    await _open(tester, _item());

    expect(find.text('Avena con fruta'), findsOneWidget);
    expect(
      find.text('10 min · 2 porciones · 180 kcal por porción'),
      findsOneWidget,
    );
    expect(
      find.text('Adaptación para un hogar de 4 integrantes'),
      findsOneWidget,
    );
    expect(find.text('Alergias: Lácteos, Gluten'), findsOneWidget);
    expect(
      find.text('Lo que verá la familia: $adaptationSummary'),
      findsOneWidget,
    );

    expect(find.text('Cambios'), findsOneWidget);
    expect(find.text('Porciones: 2 → 3'), findsOneWidget);
    expect(find.text('Para 4 integrantes'), findsOneWidget);
    expect(find.text('Avena → Amaranto'), findsOneWidget);
    expect(find.text('Por alergia a gluten'), findsOneWidget);
    expect(find.text('Leche entera → Bebida de arroz'), findsOneWidget);
    expect(find.text('Por alergia a lácteos'), findsOneWidget);
    expect(find.textContaining('Recházala'), findsNothing);
  });

  testWidgets('never shows the family, its id or the document id', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final item = _item();
    await _open(tester, item);

    expect(item.adjustment.id, contains('famA'));
    expect(find.textContaining('famA'), findsNothing);
    expect(find.textContaining('Familia'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('famA')), findsNothing);
    semantics.dispose();
  });

  testWidgets('lists the adapted ingredients with what each one replaces', (
    tester,
  ) async {
    await _open(tester, _item());

    expect(find.text('Ingredientes de la adaptación'), findsOneWidget);
    expect(find.text('Amaranto'), findsOneWidget);
    expect(find.text('0.15 kg'), findsOneWidget);
    expect(find.text('En lugar de Avena'), findsOneWidget);
    expect(find.text('Bebida de arroz'), findsOneWidget);
    expect(find.text('0.75 L'), findsOneWidget);
    expect(find.text('En lugar de Leche entera'), findsOneWidget);
    expect(find.text('Plátano'), findsOneWidget);
    expect(find.text('3 piezas'), findsOneWidget);
    expect(find.textContaining('En lugar de'), findsNWidgets(2));
  });

  testWidgets('two ingredients with the same substitute keep their own', (
    tester,
  ) async {
    await _open(
      tester,
      _item(
        householdKey: '4-dairy-egg',
        ingredients: const [
          RecipeIngredient(productName: 'Tofu', quantity: 0.2, unit: 'kg'),
          RecipeIngredient(productName: 'Tofu', quantity: 0.1, unit: 'kg'),
        ],
        changes: const [
          AdjustmentChange(
            kind: AdjustmentChange.kindSubstitution,
            reason: 'alergia a lácteos',
            from: 'Queso panela',
            to: 'Tofu',
          ),
          AdjustmentChange(
            kind: AdjustmentChange.kindSubstitution,
            reason: 'alergia a huevo',
            from: 'Huevo',
            to: 'Tofu',
          ),
        ],
      ),
    );

    expect(find.text('En lugar de Queso panela'), findsOneWidget);
    expect(find.text('En lugar de Huevo'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('En lugar de Queso panela')).dy,
      lessThan(tester.getTopLeft(find.text('En lugar de Huevo')).dy),
    );
  });

  testWidgets('shows the steps of the published recipe', (tester) async {
    await _open(tester, _item());

    expect(find.text('Preparación'), findsOneWidget);
    expect(find.text('Calienta la leche.'), findsOneWidget);
    expect(find.text('Agrega la avena.'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('says 1 integrante for a household of one', (tester) async {
    await _open(
      tester,
      _item(
        householdSize: 1,
        householdKey: '1',
        changes: const [portionsChange],
      ),
    );

    expect(
      find.text('Adaptación para un hogar de 1 integrante'),
      findsOneWidget,
    );
    expect(find.text('Sin alergias'), findsOneWidget);
    expect(find.text('Para 1 integrante'), findsOneWidget);
  });

  testWidgets('without the recipe there is no base data and it says why', (
    tester,
  ) async {
    await _open(tester, _item(unpublished: true));

    expect(find.text('Receta no disponible'), findsOneWidget);
    expect(find.textContaining('kcal por porción'), findsNothing);
    expect(find.text('Preparación'), findsNothing);
    expect(find.text('Porciones: 3'), findsOneWidget);
    expect(
      find.text(
        'La receta ya no está publicada, así que la familia no vería esta '
        'adaptación. Puedes rechazarla.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('warns when the recipe changed after the suggestion', (
    tester,
  ) async {
    await _open(
      tester,
      _item(published: approvedRecipe('r1', 'Avena con fruta', servings: 4)),
    );

    expect(
      find.text(
        'La receta cambió después de esta sugerencia y la familia ya no la '
        'vería. Recházala; se sugerirá otra cuando la familia vuelva a abrir '
        'la receta.',
      ),
      findsOneWidget,
    );
    expect(find.text('Porciones: 3'), findsOneWidget);
  });

  testWidgets('warns when an allergen of the household is still there', (
    tester,
  ) async {
    await _open(
      tester,
      _item(
        ingredients: const [
          RecipeIngredient(productName: 'Amaranto', quantity: 0.15, unit: 'kg'),
          RecipeIngredient(
            productName: 'Leche entera',
            quantity: 0.75,
            unit: 'l',
          ),
        ],
      ),
    );

    expect(
      find.text(
        'Esta adaptación todavía lleva un ingrediente con un alérgeno del '
        'hogar (Leche entera). Recházala.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('"Volver a la lista" goes back', (tester) async {
    await _open(tester, _item());

    await tester.tap(find.text('Volver a la lista'));
    await tester.pumpAndSettle();

    expect(find.text('Abrir'), findsOneWidget);
    expect(find.text('Cambios'), findsNothing);
  });

  group('with large text on a 360 wide screen', () {
    setUpAll(loadAppFonts);

    for (final scale in [1.3, 2.0]) {
      testWidgets('at ${scale}x no word breaks and nothing overflows', (
        tester,
      ) async {
        // Con aviso: la receta cambió después de la sugerencia.
        await pumpWithTextScale(
          tester,
          AdjustmentReviewScreen(
            item: _item(
              published: approvedRecipe('r1', 'Avena con fruta', servings: 4),
            ),
          ),
          textScale: scale,
          height: 5000,
        );

        expect(find.textContaining('Recházala'), findsOneWidget);
        expect(find.text('Agrega la avena.'), findsOneWidget);
        expectNoBrokenWords(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
