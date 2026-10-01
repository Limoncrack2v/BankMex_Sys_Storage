import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:bank_storage_app/ui/widgets/next_delivery_banner.dart';

final _today = DateTime(2026, 10, 1, 9);

Future<void> _pumpBanner(WidgetTester tester, DateTime? date) =>
    tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: NextDeliveryBanner(date: date, today: _today),
        ),
      ),
    );

void main() {
  testWidgets('muestra la fecha y "Mañana" para una entrega al día siguiente', (
    tester,
  ) async {
    await _pumpBanner(tester, DateTime(2026, 10, 2));

    expect(find.text('Tu próxima entrega'), findsOneWidget);
    expect(find.text('02 oct 2026 · Mañana'), findsOneWidget);
  });

  testWidgets('dice "Hoy" para una entrega del mismo día', (tester) async {
    await _pumpBanner(tester, DateTime(2026, 10, 1));

    expect(find.text('01 oct 2026 · Hoy'), findsOneWidget);
  });

  testWidgets('cuenta los días para una entrega más adelante', (tester) async {
    await _pumpBanner(tester, DateTime(2026, 10, 6));

    expect(find.text('06 oct 2026 · En 5 días'), findsOneWidget);
  });

  testWidgets('sin entrega programada no muestra nada', (tester) async {
    await _pumpBanner(tester, null);

    expect(find.text('Tu próxima entrega'), findsNothing);
  });

  testWidgets('una fecha que ya pasó no se muestra', (tester) async {
    await _pumpBanner(tester, DateTime(2026, 9, 30));

    expect(find.text('Tu próxima entrega'), findsNothing);
  });
}
