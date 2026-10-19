import 'dart:async';

import 'package:bank_storage_app/data/models/app_user.dart';
import 'package:bank_storage_app/data/repositories/auth_repository.dart';
import 'package:bank_storage_app/domain/models/recipe.dart';
import 'package:bank_storage_app/ui/screens/nutritionist/nutritionist_home_screen.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _session = AuthSession(
  user: AppUser(
    userId: 'nutri1',
    name: 'Ana Nutrióloga',
    email: 'ana@bamx.test',
    role: AppUser.roleNutritionist,
    createdAt: DateTime(2026, 10, 16),
  ),
  family: null,
);

Recipe _recipe(String id, String name) => Recipe(
  id: id,
  name: name,
  ingredients: const [
    RecipeIngredient(productName: 'Lenteja', quantity: 0.25, unit: 'kg'),
  ],
  steps: const ['Enjuaga las lentejas.', 'Cuécelas.'],
  prepTimeMinutes: 40,
  caloriesPerServing: 230,
  status: RecipeStatus.pending,
);

class _Calls {
  final log = <String>[];
}

Future<void> _pump(
  WidgetTester tester, {
  required Stream<List<Recipe>> recipes,
  _Calls? calls,
  Future<void> Function(String id)? approve,
  Future<void> Function(String id, String note)? reject,
  Future<bool> Function(BuildContext)? confirm,
}) async {
  tester.view.physicalSize = const Size(900, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final log = calls ?? _Calls();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: NutritionistHomeScreen(
        session: _session,
        pendingRecipes: recipes,
        approveRecipe: approve ?? (id) async => log.log.add('approve $id'),
        rejectRecipe:
            reject ?? (id, note) async => log.log.add('reject $id: $note'),
        confirmIdentity:
            confirm ??
            (_) async {
              log.log.add('confirm');
              return true;
            },
      ),
    ),
  );
  await tester.pump();
}

Future<void> _tapButton(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label).first);
  await tester.tap(find.text(label).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists the pending recipes by name, with no family data', (
    tester,
  ) async {
    await _pump(
      tester,
      recipes: Stream.value([_recipe('r2', 'Sopa'), _recipe('r1', 'Arroz')]),
    );

    expect(find.text('Recetas por revisar'), findsOneWidget);
    expect(find.text('Aprobar receta'), findsNWidgets(2));
    expect(find.text('Rechazar con motivo'), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('Arroz')).dy,
      lessThan(tester.getTopLeft(find.text('Sopa')).dy),
    );
    expect(find.textContaining('Familia'), findsNothing);
  });

  testWidgets('says so when there is nothing to review', (tester) async {
    await _pump(tester, recipes: Stream.value(const []));

    expect(find.text('No hay recetas por revisar.'), findsOneWidget);
    expect(find.text('Aprobar receta'), findsNothing);
  });

  testWidgets('shows the ingredients and steps when expanded', (tester) async {
    await _pump(tester, recipes: Stream.value([_recipe('r1', 'Sopa')]));
    await _tapButton(tester, 'Ver ingredientes y pasos');

    expect(find.textContaining('Lenteja'), findsOneWidget);
    expect(find.text('1. Enjuaga las lentejas.'), findsOneWidget);
  });

  testWidgets('a short ingredient and step are aligned to the left', (
    tester,
  ) async {
    final short = Recipe(
      id: 'r1',
      name: 'Ensalada de naranja',
      ingredients: const [
        RecipeIngredient(productName: 'Naranja', quantity: 0.4, unit: 'kg'),
      ],
      steps: const ['Pela y sirve.'],
      prepTimeMinutes: 10,
      caloriesPerServing: 90,
      status: RecipeStatus.pending,
    );
    await _pump(tester, recipes: Stream.value([short]));
    await _tapButton(tester, 'Ver ingredientes y pasos');

    final left = tester.getTopLeft(find.text('Ensalada de naranja')).dx;
    expect(tester.getTopLeft(find.textContaining('Naranja')).dx, left);
    expect(tester.getTopLeft(find.text('1. Pela y sirve.')).dx, left);
  });

  testWidgets('shows an error when the recipes cannot be loaded', (
    tester,
  ) async {
    await _pump(
      tester,
      recipes: Stream<List<Recipe>>.error(StateError('permission-denied')),
    );

    expect(find.textContaining('No se pudieron cargar'), findsOneWidget);
  });

  testWidgets('the name, role and sign-out are in "Mi cuenta"', (tester) async {
    await _pump(tester, recipes: Stream.value([_recipe('r1', 'Sopa')]));
    expect(find.text('Ana Nutrióloga'), findsNothing);
    expect(find.text('Cerrar sesión'), findsNothing);

    await tester.tap(find.byTooltip('Cuenta'));
    await tester.pumpAndSettle();

    expect(find.text('Mi cuenta'), findsOneWidget);
    expect(find.text('Ana Nutrióloga'), findsOneWidget);
    expect(find.text('Nutriólogo'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsOneWidget);
  });

  group('approve', () {
    testWidgets('asks for the password first, then approves', (tester) async {
      final calls = _Calls();
      await _pump(
        tester,
        calls: calls,
        recipes: Stream.value([_recipe('r1', 'Sopa')]),
      );

      await _tapButton(tester, 'Aprobar receta');

      expect(calls.log, ['confirm', 'approve r1']);
      // Confirma con la palomita (#44, item 8).
      expect(find.text('Receta aprobada'), findsOneWidget);
      expect(find.textContaining('«Sopa» aprobada'), findsOneWidget);
    });

    testWidgets('writes nothing when the identity is not confirmed', (
      tester,
    ) async {
      final calls = _Calls();
      await _pump(
        tester,
        calls: calls,
        recipes: Stream.value([_recipe('r1', 'Sopa')]),
        confirm: (_) async => false,
      );

      await _tapButton(tester, 'Aprobar receta');

      expect(calls.log, isEmpty);
    });

    testWidgets('tells the user when it fails', (tester) async {
      await _pump(
        tester,
        recipes: Stream.value([_recipe('r1', 'Sopa')]),
        approve: (_) async => throw StateError('permission-denied'),
      );

      await _tapButton(tester, 'Aprobar receta');

      expect(find.textContaining('No se pudo aprobar «Sopa»'), findsOneWidget);
      expect(find.text('Receta aprobada'), findsNothing);
    });

    testWidgets('says it will sync when offline', (tester) async {
      await _pump(
        tester,
        recipes: Stream.value([_recipe('r1', 'Sopa')]),
        approve: (_) => Completer<void>().future,
      );

      await tester.ensureVisible(find.text('Aprobar receta'));
      await tester.tap(find.text('Aprobar receta'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 9));
      await tester.pump();

      expect(find.textContaining('cuando vuelva la conexión'), findsOneWidget);
    });
  });

  group('reject', () {
    testWidgets('needs a reason before the button works', (tester) async {
      final calls = _Calls();
      await _pump(
        tester,
        calls: calls,
        recipes: Stream.value([_recipe('r1', 'Sopa')]),
      );
      await _tapButton(tester, 'Rechazar con motivo');
      // El título y el botón del sheet.
      expect(find.text('Rechazar receta'), findsNWidgets(2));

      // Vacío o solo espacios: el botón no hace nada y el sheet sigue abierto.
      for (final text in ['', '   ']) {
        await tester.enterText(find.byType(TextField), text);
        await tester.pump();
        await tester.tap(find.text('Rechazar receta').last);
        await tester.pumpAndSettle();
        expect(find.text('Rechazar receta'), findsNWidgets(2));
      }
      expect(calls.log, isEmpty);
    });

    testWidgets('sends the trimmed reason after the password', (tester) async {
      final calls = _Calls();
      await _pump(
        tester,
        calls: calls,
        recipes: Stream.value([_recipe('r1', 'Sopa')]),
      );
      await _tapButton(tester, 'Rechazar con motivo');

      await tester.enterText(find.byType(TextField), '  Falta la sal  ');
      await tester.pump();
      await tester.tap(find.text('Rechazar receta').last);
      await tester.pumpAndSettle();

      expect(calls.log, ['confirm', 'reject r1: Falta la sal']);
      expect(find.textContaining('regresó a borrador'), findsOneWidget);
    });

    testWidgets('closing the sheet writes nothing', (tester) async {
      final calls = _Calls();
      await _pump(
        tester,
        calls: calls,
        recipes: Stream.value([_recipe('r1', 'Sopa')]),
      );
      await _tapButton(tester, 'Rechazar con motivo');

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(calls.log, isEmpty);
    });

    testWidgets('does not reject when the identity is not confirmed', (
      tester,
    ) async {
      final calls = _Calls();
      await _pump(
        tester,
        calls: calls,
        recipes: Stream.value([_recipe('r1', 'Sopa')]),
        confirm: (_) async => false,
      );
      await _tapButton(tester, 'Rechazar con motivo');
      await tester.enterText(find.byType(TextField), 'Falta sal');
      await tester.pump();
      await tester.tap(find.text('Rechazar receta').last);
      await tester.pumpAndSettle();

      expect(calls.log, isEmpty);
    });

    testWidgets('the reason has the same limit as the rules', (tester) async {
      await _pump(tester, recipes: Stream.value([_recipe('r1', 'Sopa')]));
      await _tapButton(tester, 'Rechazar con motivo');

      await tester.enterText(find.byType(TextField), 'a' * 400);
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text.length, Recipe.maxReviewNoteLength);
    });
  });
}
