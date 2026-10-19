import 'dart:async';

import 'package:bank_storage_app/ui/models/recipe.dart';
import 'package:bank_storage_app/ui/sample_data.dart';
import 'package:bank_storage_app/ui/screens/recipes/request_recipe_screen.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pump(WidgetTester tester, Stream<List<Recipe>> stream) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ApprovedCatalogGate(
          stream: stream,
          builder: (_, recipes) => Text('${recipes.length} recetas'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('catálogo vacío: estado vacío, sin recetas de muestra', (
    tester,
  ) async {
    await pump(tester, Stream.value(const <Recipe>[]));
    await tester.pump();

    expect(find.text('Aún no hay recetas para sugerirte'), findsOneWidget);
    expect(find.textContaining('recetas'), findsWidgets);
    expect(find.text('${SampleData.recipes.length} recetas'), findsNothing);
    expect(find.text('0 recetas'), findsNothing);
  });

  testWidgets('mientras carga: indicador, sin recetas', (tester) async {
    final controller = StreamController<List<Recipe>>();
    addTearDown(controller.close);
    await pump(tester, controller.stream);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining(' recetas'), findsNothing);
  });

  testWidgets('si falla: aviso, sin recetas de muestra', (tester) async {
    await pump(tester, Stream.error(StateError('sin permiso')));
    await tester.pump();

    expect(find.textContaining('No pudimos leer las recetas'), findsOneWidget);
    expect(find.text('Aún no hay recetas para sugerirte'), findsNothing);
  });

  testWidgets('con recetas aprobadas las entrega', (tester) async {
    await pump(tester, Stream.value(SampleData.recipes));
    await tester.pump();

    expect(find.text('${SampleData.recipes.length} recetas'), findsOneWidget);
  });
}
