import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:bank_storage_app/ui/widgets/app_header.dart';

/// Distancia del borde de arriba al título con [systemTop] de barra de estado.
Future<double> _titleRowTop(WidgetTester tester, double systemTop) async {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(top: systemTop);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
        body: Column(
          children: [AppHeader(title: 'Despensa', trailing: SizedBox())],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.getRect(find.byType(Row).first).top;
}

void main() {
  testWidgets('sin barra de estado (web): 56 como en el diseño', (
    tester,
  ) async {
    expect(await _titleRowTop(tester, 0), closeTo(56, 0.5));
  });

  testWidgets('barra de 24 (Android): completa hasta 56', (tester) async {
    expect(await _titleRowTop(tester, 24), closeTo(56, 0.5));
  });

  testWidgets('con Dynamic Island (62): justo debajo, sin tapar la barra', (
    tester,
  ) async {
    expect(await _titleRowTop(tester, 62), closeTo(62, 0.5));
  });
}
