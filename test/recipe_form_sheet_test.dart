import 'package:bank_storage_app/domain/models/recipe.dart';
import 'package:bank_storage_app/ui/screens/staff/recipe_form_sheet.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:bank_storage_app/ui/widgets/app_buttons.dart';
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
Future<void> open(
  WidgetTester tester,
  Recipe? recipe, {
  Size size = const Size(900, 4000),
}) async {
  tester.view.physicalSize = size;
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

/// "Guardar cambios" (o "Guardar receta") puede tocarse.
bool canSave(WidgetTester tester, {String label = 'Guardar cambios'}) {
  final button = tester.widget<PrimaryButton>(
    find.widgetWithText(PrimaryButton, label),
  );
  return button.onPressed != null;
}

/// Baja hasta el final del formulario, donde está el aviso.
Future<void> scrollToEnd(WidgetTester tester) async {
  await tester.drag(
    find.byType(SingleChildScrollView).first,
    const Offset(0, -5000),
  );
  await tester.pumpAndSettle();
}

const hint = 'Baja hasta el final: hay un aviso antes de guardar.';
// Una pantalla chica: el formulario no cabe y hay que bajar para ver el aviso.
const small = Size(400, 600);

void main() {
  group('"Guardar cambios" waits until Staff has seen the warning', () {
    testWidgets('an approved recipe with a change cannot be saved yet', (
      tester,
    ) async {
      await open(tester, recipe(RecipeStatus.approved), size: small);

      await tester.enterText(field('30'), '20');
      await tester.pump();

      expect(canSave(tester), isFalse);
      expect(find.text(hint), findsOneWidget);
    });

    testWidgets('after scrolling to the end it can be saved', (tester) async {
      await open(tester, recipe(RecipeStatus.approved), size: small);
      await tester.enterText(field('30'), '20');
      await tester.pump();

      await scrollToEnd(tester);

      expect(find.textContaining('deja de verse'), findsOneWidget);
      expect(canSave(tester), isTrue);
      expect(find.text(hint), findsNothing);
    });

    testWidgets('moving it to draft without changes waits too', (tester) async {
      await open(tester, recipe(RecipeStatus.approved), size: small);

      // El selector de estado está cerca del final: se baja hasta él.
      await tester.ensureVisible(find.text('Borrador'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Borrador'));
      await tester.pumpAndSettle();

      expect(canSave(tester), isFalse);
      expect(find.text(hint), findsOneWidget);

      await scrollToEnd(tester);
      expect(canSave(tester), isTrue);
    });

    testWidgets('undoing the change takes the hint away', (tester) async {
      await open(tester, recipe(RecipeStatus.approved), size: small);
      await tester.enterText(field('30'), '20');
      await tester.pump();
      await tester.enterText(field('20'), '30');
      await tester.pump();

      expect(find.text(hint), findsNothing);
      expect(
        find.text('Cambia la receta o su estado para guardar.'),
        findsOneWidget,
      );
    });

    testWidgets('when the form fits, the warning is already in view', (
      tester,
    ) async {
      await open(tester, recipe(RecipeStatus.approved));

      await tester.enterText(field('30'), '20');
      await tester.pump();

      expect(find.textContaining('deja de verse'), findsOneWidget);
      expect(canSave(tester), isTrue);
    });

    testWidgets('a draft recipe is not held back', (tester) async {
      await open(tester, recipe(RecipeStatus.draft), size: small);

      await tester.enterText(field('30'), '20');
      await tester.pump();

      expect(find.text(hint), findsNothing);
      expect(canSave(tester), isTrue);
    });
  });

  group('a pending recipe', () {
    testWidgets('opens as "Ver receta", not as a review by Staff', (
      tester,
    ) async {
      await open(tester, recipe(RecipeStatus.pending));

      expect(find.text('Ver receta'), findsOneWidget);
      expect(find.text('Revisar receta'), findsNothing);
      expect(find.text('Regresar a borrador'), findsOneWidget);
    });
  });

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
