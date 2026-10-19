import 'dart:async';

import 'package:bank_storage_app/domain/models/recipe.dart';
import 'package:bank_storage_app/domain/models/recipe_adjustment.dart';
import 'package:bank_storage_app/domain/recipe_adjustment.dart';
import 'package:bank_storage_app/ui/screens/nutritionist/adjustment_queue.dart';
import 'package:bank_storage_app/ui/screens/nutritionist/adjustment_review_screen.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:bank_storage_app/ui/widgets/app_bottom_sheet.dart';
import 'package:bank_storage_app/ui/widgets/app_buttons.dart';
import 'package:bank_storage_app/ui/widgets/danger_buttons.dart';
import 'package:bank_storage_app/ui/widgets/pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/adjustment_fixtures.dart';
import 'helpers/large_text.dart';

final _avena = avenaConFruta;

/// La adaptación de la avena, con la receta como está publicada ahora
/// ([published]; null si no se puede leer) o, si [inReview], en revisión.
AdjustmentQueueItem _item({
  Recipe? published,
  bool unpublished = false,
  bool inReview = false,
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
  inReview: inReview,
);

const _lateFailure =
    'No se guardó la decisión sobre «Avena con fruta». Vuelve a revisarla.';

class _Calls {
  final log = <String>[];
}

/// Una lista con un botón que abre la revisión de [item], como la tarjeta.
/// Por omisión la contraseña se confirma y las decisiones se guardan; todo
/// queda en [calls].
Future<void> _open(
  WidgetTester tester,
  AdjustmentQueueItem item, {
  _Calls? calls,
  Future<void> Function(String id)? approve,
  Future<void> Function(String id, String reason)? reject,
  Future<bool> Function(BuildContext context)? confirm,
}) async {
  final log = (calls ?? _Calls()).log;
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
              onPressed: () => openAdjustmentReview(
                context,
                item: item,
                reviewerUid: 'nutri1',
                approveAdjustment:
                    approve ?? (id) async => log.add('approve $id'),
                rejectAdjustment:
                    reject ??
                    (id, reason) async => log.add('reject $id: $reason'),
                confirmIdentity:
                    confirm ??
                    (_) async {
                      log.add('confirm');
                      return true;
                    },
              ),
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

/// Los botones de la revisión (no los del sheet).
final _approveButton = find.descendant(
  of: find.byType(AdjustmentReviewScreen),
  matching: find.byType(PrimaryButton),
);
final _rejectButton = find.descendant(
  of: find.byType(AdjustmentReviewScreen),
  matching: find.byType(DangerButton),
);

/// El botón de [type] del sheet abierto.
Finder _inSheet(Type type) =>
    find.descendant(of: find.byType(AppSheet), matching: find.byType(type));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Abre el sheet de aprobar y lo confirma.
Future<void> _approve(WidgetTester tester) async {
  await _tap(tester, _approveButton);
  await _tap(tester, _inSheet(PrimaryButton));
}

/// Abre el sheet del motivo, lo escribe y rechaza.
Future<void> _reject(WidgetTester tester, String reason) async {
  await _tap(tester, _rejectButton);
  await tester.enterText(find.byType(TextField), reason);
  await tester.pump();
  await _tap(tester, _inSheet(DangerButton));
}

VoidCallback? _onPressed(WidgetTester tester, Finder button) =>
    switch (tester.widget(button)) {
      PrimaryButton(:final onPressed) => onPressed,
      DangerButton(:final onPressed) => onPressed,
      _ => throw StateError('No es un botón de la revisión'),
    };

String get _id => _item().adjustment.id;

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
    expect(find.text('Porciones: de 2 a 3'), findsOneWidget);
    expect(find.text('Para 4 integrantes'), findsOneWidget);
    expect(find.text('Avena por amaranto'), findsOneWidget);
    expect(find.text('Por alergia a gluten'), findsOneWidget);
    expect(find.text('Leche entera por bebida de arroz'), findsOneWidget);
    expect(find.text('Por alergia a lácteos'), findsOneWidget);
    expect(find.textContaining('→'), findsNothing);
    expect(find.byType(InfoBanner), findsNothing);
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
    // Puede volver a publicarse igual: no invita a rechazarla.
    expect(
      find.text(
        'La receta no está publicada ahora: está en borrador o se borró. Si '
        'se vuelve a publicar sin cambios, podrás aprobar esta adaptación.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('waits when the recipe is back in review without changes', (
    tester,
  ) async {
    await _open(tester, _item(inReview: true));

    expect(find.text('Avena con fruta'), findsOneWidget);
    expect(find.text('Preparación'), findsOneWidget);
    expect(
      find.text(
        'La receta está en "Recetas por revisar". Si la apruebas sin cambios, '
        'después podrás aprobar esta adaptación.',
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
        'vería. Puedes rechazarla; cuando la familia vuelva a abrir la receta '
        'se sugerirá otra.',
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

  group('approve', () {
    testWidgets('confirms, asks for the password, approves and closes', (
      tester,
    ) async {
      final calls = _Calls();
      await _open(tester, _item(), calls: calls);

      await _tap(tester, _approveButton);
      // El título y el botón del sheet, y el botón de la revisión.
      expect(find.text('Aprobar adaptación'), findsNWidgets(3));
      expect(
        find.text(
          'La familia verá la versión adaptada de «Avena con fruta» en sus '
          'recetas y en su plan de comidas. No se puede deshacer.',
        ),
        findsOneWidget,
      );
      expect(calls.log, isEmpty);

      await _tap(tester, _inSheet(PrimaryButton));

      expect(calls.log, ['confirm', 'approve $_id']);
      // La revisión se cierra y la lista lo confirma con la palomita.
      expect(find.byType(AdjustmentReviewScreen), findsNothing);
      expect(find.text('Adaptaciones por revisar'), findsOneWidget);
      expect(find.text('Adaptación aprobada'), findsOneWidget);
      expect(
        find.text(
          'La familia ya verá la versión adaptada de «Avena con fruta».',
        ),
        findsOneWidget,
      );
    });

    testWidgets('closing the confirmation writes nothing', (tester) async {
      final calls = _Calls();
      await _open(tester, _item(), calls: calls);

      await _tap(tester, _approveButton);
      expect(find.text('Volver'), findsOneWidget);
      await _tap(tester, _inSheet(SecondaryButton));
      expect(find.byType(AppSheet), findsNothing);

      await _tap(tester, _approveButton);
      await _tap(tester, find.byTooltip('Cerrar'));
      expect(find.byType(AppSheet), findsNothing);

      expect(calls.log, isEmpty);
      expect(find.byType(AdjustmentReviewScreen), findsOneWidget);
    });

    testWidgets('writes nothing when the password is not confirmed', (
      tester,
    ) async {
      final calls = _Calls();
      await _open(tester, _item(), calls: calls, confirm: (_) async => false);

      await _approve(tester);

      expect(calls.log, isEmpty);
      expect(find.byType(AdjustmentReviewScreen), findsOneWidget);
      expect(find.text('Adaptación aprobada'), findsNothing);
    });

    testWidgets('while it saves, both buttons are off and say what happens', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final calls = _Calls();
      final saving = Completer<void>();
      await _open(
        tester,
        _item(),
        calls: calls,
        approve: (id) {
          calls.log.add('approve $id');
          return saving.future;
        },
      );

      await _tap(tester, _approveButton);
      await tester.tap(_inSheet(PrimaryButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(calls.log, ['confirm', 'approve $_id']);
      final approve = tester.widget<PrimaryButton>(_approveButton);
      expect(approve.loading, isTrue);
      expect(approve.onPressed, isNull);
      expect(_onPressed(tester, _rejectButton), isNull);
      expect(find.bySemanticsLabel('Aprobando la adaptación'), findsOneWidget);
      // Otro toque no hace nada.
      await tester.tap(_rejectButton);
      await tester.pump();
      expect(find.byType(AppSheet), findsNothing);
      // Tampoco se sale: la confirmación llega cuando termina.
      await tester.tap(find.text('Volver a la lista'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AdjustmentReviewScreen), findsOneWidget);

      saving.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AdjustmentReviewScreen), findsNothing);
      expect(find.text('Adaptación aprobada'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('says it will sync when offline, and warns if it fails later', (
      tester,
    ) async {
      final saving = Completer<void>();
      await _open(tester, _item(), approve: (_) => saving.future);

      await _tap(tester, _approveButton);
      await tester.tap(_inSheet(PrimaryButton));
      await tester.pump();
      // Espera al servidor 8 segundos y después la da por guardada en el
      // dispositivo.
      await tester.pump(const Duration(seconds: 7));
      expect(find.text('Adaptación aprobada'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('Adaptación aprobada'), findsOneWidget);
      await tester.pumpAndSettle();

      expect(find.byType(AdjustmentReviewScreen), findsNothing);
      expect(find.text('Adaptación aprobada'), findsOneWidget);
      expect(
        find.text(
          'La aprobación de «Avena con fruta» se enviará cuando vuelva la '
          'conexión. Si tarda más de unos minutos, tendrás que revisarla otra '
          'vez.',
        ),
        findsOneWidget,
      );

      // Al sincronizar, el servidor la rechaza (p. ej. la sesión ya es vieja)
      // con la palomita abierta: el aviso espera a que se cierre, porque
      // debajo de ella no se vería.
      saving.completeError(StateError('permission-denied'));
      await tester.pumpAndSettle();
      expect(find.text(_lateFailure), findsNothing);
      await _tap(tester, find.text('Listo'));
      expect(find.text(_lateFailure).hitTestable(), findsOneWidget);
    });

    testWidgets('a failure after the check mark closed shows when it comes', (
      tester,
    ) async {
      final saving = Completer<void>();
      await _open(tester, _item(), approve: (_) => saving.future);

      await _tap(tester, _approveButton);
      await tester.tap(_inSheet(PrimaryButton));
      await tester.pump();
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Listo'));
      expect(find.text(_lateFailure), findsNothing);

      saving.completeError(StateError('permission-denied'));
      await tester.pumpAndSettle();
      expect(find.text(_lateFailure).hitTestable(), findsOneWidget);
    });

    testWidgets('a queued write that syncs fine shows nothing more', (
      tester,
    ) async {
      final saving = Completer<void>();
      await _open(tester, _item(), approve: (_) => saving.future);

      await _tap(tester, _approveButton);
      await tester.tap(_inSheet(PrimaryButton));
      await tester.pump();
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Listo'));

      saving.complete();
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('stays on the page and says so when it fails', (tester) async {
      await _open(
        tester,
        _item(),
        approve: (_) async => throw StateError('permission-denied'),
      );

      await _approve(tester);

      expect(
        find.text(
          'No se pudo aprobar la adaptación de «Avena con fruta». Intenta de '
          'nuevo.',
        ),
        findsOneWidget,
      );
      expect(find.byType(AdjustmentReviewScreen), findsOneWidget);
      expect(find.text('Adaptación aprobada'), findsNothing);
      // Se puede intentar otra vez.
      expect(_onPressed(tester, _approveButton), isNotNull);
      expect(_onPressed(tester, _rejectButton), isNotNull);
    });

    testWidgets('an error before the write is a failure too', (tester) async {
      await _open(tester, _item(), approve: (_) => throw ArgumentError('id'));

      await _approve(tester);

      expect(
        find.textContaining('No se pudo aprobar la adaptación'),
        findsOneWidget,
      );
      expect(find.byType(AdjustmentReviewScreen), findsOneWidget);
    });

    for (final (name, item) in [
      (
        'the recipe changed',
        _item(published: approvedRecipe('r1', 'Avena con fruta', servings: 4)),
      ),
      ('the recipe is not published', _item(unpublished: true)),
      ('the recipe is in review', _item(inReview: true)),
      (
        'an allergen is left',
        _item(
          ingredients: const [
            RecipeIngredient(
              productName: 'Leche entera',
              quantity: 0.75,
              unit: 'l',
            ),
          ],
        ),
      ),
    ]) {
      testWidgets('is off when the family would never see it: $name', (
        tester,
      ) async {
        final calls = _Calls();
        await _open(tester, item, calls: calls);

        expect(_onPressed(tester, _approveButton), isNull);
        expect(_onPressed(tester, _rejectButton), isNotNull);
        await _tap(tester, _approveButton);
        expect(find.byType(AppSheet), findsNothing);
        expect(calls.log, isEmpty);
      });
    }

    testWidgets('a second tap while it is deciding does nothing', (
      tester,
    ) async {
      final calls = _Calls();
      final password = Completer<bool>();
      await _open(
        tester,
        _item(),
        calls: calls,
        confirm: (_) {
          calls.log.add('confirm');
          return password.future;
        },
      );

      await _tap(tester, _approveButton);
      await _tap(tester, _inSheet(PrimaryButton));
      // Mientras se confirma la contraseña, otro toque no abre otro sheet.
      await _tap(tester, _approveButton);
      expect(find.byType(AppSheet), findsNothing);
      await _tap(tester, _rejectButton);
      expect(find.byType(AppSheet), findsNothing);

      password.complete(true);
      await tester.pumpAndSettle();
      expect(calls.log, ['confirm', 'approve $_id']);
    });
  });

  group('reject', () {
    testWidgets('needs a reason before the button works', (tester) async {
      final calls = _Calls();
      await _open(tester, _item(), calls: calls);

      await _tap(tester, _rejectButton);
      // El título y el botón del sheet.
      expect(find.text('Rechazar adaptación'), findsNWidgets(2));
      expect(
        find.text(
          'La familia seguirá viendo la receta original de «Avena con '
          'fruta». Escribe el motivo; se guarda con la adaptación y la app no '
          'se lo muestra a la familia.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Ej. La sustitución no va con esta receta.'),
        findsOneWidget,
      );

      for (final text in ['', '   ']) {
        await tester.enterText(find.byType(TextField), text);
        await tester.pump();
        expect(_onPressed(tester, _inSheet(DangerButton)), isNull);
        await _tap(tester, _inSheet(DangerButton));
        expect(find.byType(AppSheet), findsOneWidget);
      }
      expect(calls.log, isEmpty);
    });

    testWidgets('sends the trimmed reason after the password, then closes', (
      tester,
    ) async {
      final calls = _Calls();
      await _open(tester, _item(), calls: calls);

      await _reject(tester, '  La sustitución no va con esta receta.  ');

      expect(calls.log, [
        'confirm',
        'reject $_id: La sustitución no va con esta receta.',
      ]);
      expect(find.byType(AdjustmentReviewScreen), findsNothing);
      expect(find.text('Adaptación rechazada'), findsOneWidget);
      expect(
        find.text(
          'La familia seguirá viendo la receta original de «Avena con '
          'fruta».',
        ),
        findsOneWidget,
      );
    });

    for (final (name, item, reason) in [
      (
        'the recipe changed',
        _item(published: approvedRecipe('r1', 'Avena con fruta', servings: 4)),
        'La receta cambió y esta adaptación ya no aplica.',
      ),
      (
        'an allergen is left',
        _item(
          ingredients: const [
            RecipeIngredient(
              productName: 'Leche entera',
              quantity: 0.75,
              unit: 'l',
            ),
          ],
        ),
        'La adaptación todavía lleva un alérgeno del hogar.',
      ),
    ]) {
      testWidgets('starts with the reason when $name', (tester) async {
        final calls = _Calls();
        await _open(tester, item, calls: calls);

        await _tap(tester, _rejectButton);
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller!.text, reason);

        await _tap(tester, _inSheet(DangerButton));
        expect(calls.log.last, 'reject $_id: $reason');
      });
    }

    // Una receta en revisión o en borrador puede volver a publicarse igual:
    // un motivo ya escrito empujaría a rechazar una adaptación que serviría.
    for (final (name, item) in [
      ('the family would see it', _item()),
      ('the recipe is not published', _item(unpublished: true)),
      ('the recipe is in review', _item(inReview: true)),
    ]) {
      testWidgets('starts empty when $name', (tester) async {
        await _open(tester, item);

        await _tap(tester, _rejectButton);

        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller!.text, isEmpty);
      });
    }

    testWidgets('says "esta receta" when the recipe is not published', (
      tester,
    ) async {
      await _open(tester, _item(unpublished: true));

      await _tap(tester, _rejectButton);
      expect(
        find.textContaining(
          'La familia seguirá viendo la receta original de esta receta. ',
        ),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'Ya no está publicada.');
      await tester.pump();
      await _tap(tester, _inSheet(DangerButton));

      expect(
        find.text(
          'La familia seguirá viendo la receta original de esta receta.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the reason has the same limit as the rules', (tester) async {
      await _open(tester, _item());
      await _tap(tester, _rejectButton);

      await tester.enterText(find.byType(TextField), 'a' * 400);
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text.length, RecipeAdjustment.maxReasonLength);
      expect(_onPressed(tester, _inSheet(DangerButton)), isNotNull);
    });

    testWidgets('closing the sheet writes nothing', (tester) async {
      final calls = _Calls();
      await _open(tester, _item(), calls: calls);
      await _tap(tester, _rejectButton);
      await tester.enterText(find.byType(TextField), 'No va');
      await tester.pump();

      await _tap(tester, find.byTooltip('Cerrar'));

      expect(find.byType(AppSheet), findsNothing);
      expect(calls.log, isEmpty);
    });

    testWidgets('writes nothing when the password is not confirmed', (
      tester,
    ) async {
      final calls = _Calls();
      await _open(tester, _item(), calls: calls, confirm: (_) async => false);

      await _reject(tester, 'No va');

      expect(calls.log, isEmpty);
      expect(find.byType(AdjustmentReviewScreen), findsOneWidget);
    });

    testWidgets('says it will sync when offline, and warns if it fails later', (
      tester,
    ) async {
      final saving = Completer<void>();
      await _open(tester, _item(), reject: (_, _) => saving.future);

      await _tap(tester, _rejectButton);
      await tester.enterText(find.byType(TextField), 'No va');
      await tester.pump();
      await tester.tap(_inSheet(DangerButton));
      await tester.pump();
      await tester.pump(const Duration(seconds: 7));
      expect(find.text('Adaptación rechazada'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('Adaptación rechazada'), findsOneWidget);
      await tester.pumpAndSettle();

      expect(find.byType(AdjustmentReviewScreen), findsNothing);
      expect(
        find.text(
          'El rechazo de «Avena con fruta» se enviará cuando vuelva la '
          'conexión. Si tarda más de unos minutos, tendrás que revisarla otra '
          'vez.',
        ),
        findsOneWidget,
      );

      saving.completeError(StateError('permission-denied'));
      await tester.pumpAndSettle();
      expect(find.text(_lateFailure), findsNothing);
      await _tap(tester, find.text('Listo'));
      expect(find.text(_lateFailure).hitTestable(), findsOneWidget);
    });

    testWidgets('while it saves, the spinner says what happens', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final saving = Completer<void>();
      await _open(tester, _item(), reject: (_, _) => saving.future);

      await _tap(tester, _rejectButton);
      await tester.enterText(find.byType(TextField), 'No va');
      await tester.pump();
      await tester.tap(_inSheet(DangerButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.widget<DangerButton>(_rejectButton).loading, isTrue);
      expect(find.bySemanticsLabel('Rechazando la adaptación'), findsOneWidget);
      expect(_onPressed(tester, _approveButton), isNull);

      saving.complete();
      await tester.pumpAndSettle();
      expect(find.text('Adaptación rechazada'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('stays on the page and says so when it fails', (tester) async {
      await _open(
        tester,
        _item(),
        reject: (_, _) async => throw StateError('permission-denied'),
      );

      await _reject(tester, 'No va');

      expect(
        find.text(
          'No se pudo rechazar la adaptación de «Avena con fruta». Intenta de '
          'nuevo.',
        ),
        findsOneWidget,
      );
      expect(find.byType(AdjustmentReviewScreen), findsOneWidget);
      expect(find.text('Adaptación rechazada'), findsNothing);
    });
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
            reviewerUid: 'nutri1',
          ),
          textScale: scale,
          height: 5000,
        );

        expect(find.textContaining('Puedes rechazarla'), findsOneWidget);
        expect(find.text('Agrega la avena.'), findsOneWidget);
        expect(find.text('Rechazar con motivo'), findsOneWidget);
        expectNoBrokenWords(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('at ${scale}x the two sheets fit', (tester) async {
        await pumpWithTextScale(
          tester,
          AdjustmentReviewScreen(item: _item(), reviewerUid: 'nutri1'),
          textScale: scale,
        );

        // Los botones quedan abajo de la pantalla: la lista aún no los arma.
        final page = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(_approveButton, 300, scrollable: page);
        await _tap(tester, _approveButton);
        expect(find.text('Volver'), findsOneWidget);
        expectNoBrokenWords(tester);
        expect(tester.takeException(), isNull);
        await _tap(tester, _inSheet(SecondaryButton));

        await tester.scrollUntilVisible(_rejectButton, 300, scrollable: page);
        await _tap(tester, _rejectButton);
        expect(find.byType(TextField), findsOneWidget);
        expectNoBrokenWords(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
