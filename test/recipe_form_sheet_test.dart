import 'package:bank_storage_app/domain/models/recipe.dart';
import 'package:bank_storage_app/ui/screens/staff/recipe_form_sheet.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Recipe recipe(RecipeStatus status) => Recipe(
  id: 'r1',
  name: 'Sopa de lentejas',
  ingredients: const [
    RecipeIngredient(productName: 'Lenteja', quantity: 0.25, unit: 'kg'),
  ],
  steps: const ['Cocer las lentejas.'],
  prepTimeMinutes: 30,
  caloriesPerServing: 200,
  status: status,
  servings: 4,
);

const warning = 'la receta deja de verse para las familias';

/// Abre el formulario de Staff (con la receta, o vacío si es null).
Future<void> open(WidgetTester tester, Recipe? recipe) async {
  tester.view.physicalSize = const Size(900, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showRecipeFormSheet(context, recipe: recipe),
            child: const Text('Abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

/// El campo de texto que ahora dice [text] (los del formulario no tienen
/// etiqueta que se pueda buscar).
Finder field(String text) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.controller?.text == text,
);

void main() {
  group('editing an approved recipe', () {
    testWidgets('nothing changed: no warning, and "Aprobada" is the state', (
      tester,
    ) async {
      await open(tester, recipe(RecipeStatus.approved));

      expect(find.textContaining(warning), findsNothing);
      expect(find.text('Aprobada'), findsOneWidget);
      expect(
        tester
            .widget<Opacity>(
              find
                  .ancestor(
                    of: find.text('Aprobada'),
                    matching: find.byType(Opacity),
                  )
                  .first,
            )
            .opacity,
        1,
      );
    });

    testWidgets('changing one field warns before saving', (tester) async {
      await open(tester, recipe(RecipeStatus.approved));

      await tester.enterText(field('30'), '20');
      await tester.pump();

      expect(find.textContaining(warning), findsOneWidget);
      expect(
        find.textContaining('vuelve a revisión del nutriólogo'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Solo él puede aprobarla de nuevo'),
        findsOneWidget,
      );
    });

    testWidgets('"Aprobada" looks disabled once something changed', (
      tester,
    ) async {
      await open(tester, recipe(RecipeStatus.approved));
      await tester.enterText(field('30'), '20');
      await tester.pump();

      final opacity = tester.widget<Opacity>(
        find
            .ancestor(of: find.text('Aprobada'), matching: find.byType(Opacity))
            .first,
      );
      expect(opacity.opacity, lessThan(1));
    });

    testWidgets('moving it to draft without changes warns too', (tester) async {
      await open(tester, recipe(RecipeStatus.approved));

      await tester.tap(find.text('Borrador'));
      await tester.pump();

      expect(find.textContaining(warning), findsOneWidget);
      expect(find.textContaining('queda en borrador'), findsOneWidget);
    });

    testWidgets('undoing the change takes the warning away', (tester) async {
      await open(tester, recipe(RecipeStatus.approved));

      await tester.enterText(field('30'), '20');
      await tester.pump();
      await tester.enterText(field('20'), '30');
      await tester.pump();

      expect(find.textContaining(warning), findsNothing);
    });
  });

  group('the warning is only for approved recipes', () {
    testWidgets('a draft recipe has no warning when edited', (tester) async {
      await open(tester, recipe(RecipeStatus.draft));

      await tester.enterText(field('30'), '20');
      await tester.pump();

      expect(find.textContaining(warning), findsNothing);
      expect(find.text('Aprobada'), findsNothing);
    });

    testWidgets('a new recipe has no warning', (tester) async {
      await open(tester, null);

      expect(find.textContaining(warning), findsNothing);
      expect(find.text('Aprobada'), findsNothing);
    });
  });
}
