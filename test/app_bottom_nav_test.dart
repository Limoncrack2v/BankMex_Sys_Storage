import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:bank_storage_app/ui/widgets/app_bottom_nav.dart';
import 'package:bank_storage_app/ui/widgets/app_icon.dart';

/// Ancho lógico de un iPhone 17 en vertical.
const _iphone = Size(402, 874);

Future<void> _pumpNav(WidgetTester tester, List<AppNavItem> items) async {
  tester.view.physicalSize = _iphone;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        bottomNavigationBar: AppBottomNav(
          items: items,
          currentIndex: 0,
          onTap: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<double> _iconCenters(WidgetTester tester) => [
  for (final icon in find.byType(AppIcon).evaluate())
    tester.getCenter(find.byWidget(icon.widget)).dx,
];

void main() {
  for (final (name, items) in [
    ('del staff', AppBottomNav.staffItems),
    ('de la familia', AppBottomNav.familyItems),
  ]) {
    testWidgets('los íconos $name quedan centrados y a la misma distancia', (
      tester,
    ) async {
      await _pumpNav(tester, items);

      final centers = _iconCenters(tester);
      expect(centers, hasLength(items.length));

      // Simétricos respecto al centro de la pantalla.
      final middle = _iphone.width / 2;
      for (var i = 0; i < centers.length; i++) {
        final mirrored = centers[centers.length - 1 - i];
        expect(
          centers[i] - (middle - (mirrored - middle)),
          closeTo(0, 0.5),
          reason: 'el ícono $i no es simétrico con su opuesto',
        );
      }

      // Separados por la misma distancia entre ellos.
      final gaps = [
        for (var i = 1; i < centers.length; i++) centers[i] - centers[i - 1],
      ];
      for (final gap in gaps) {
        expect(gap, closeTo(gaps.first, 0.5), reason: 'separación despareja');
      }

      // Los márgenes a la orilla son iguales y del tamaño de una separación
      // entre íconos: el grupo ocupa el ancho completo.
      final leftMargin = centers.first;
      final rightMargin = _iphone.width - centers.last;
      expect(leftMargin, closeTo(rightMargin, 0.5));
      expect(leftMargin, closeTo(gaps.first / 2, 1));
    });

    testWidgets('cada opción $name ocupa el mismo ancho', (tester) async {
      await _pumpNav(tester, items);

      final widths = [
        for (final item in items)
          tester.getSize(find.widgetWithText(InkWell, item.label)).width,
      ];
      for (final width in widths) {
        expect(width, closeTo(widths.first, 0.5));
      }
    });
  }
}
