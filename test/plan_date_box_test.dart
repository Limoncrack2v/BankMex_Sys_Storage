import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/ui/screens/meal_plan/plan_date_box.dart';

import 'helpers/large_text.dart';

/// Miércoles.
final date = DateTime(2026, 10, 14);

Future<void> pumpBox(WidgetTester tester, double textScale) =>
    pumpWithTextScale(
      tester,
      Align(alignment: Alignment.topLeft, child: PlanDateBox(date)),
      textScale: textScale,
    );

void main() {
  setUpAll(loadAppFonts);

  testWidgets('with normal text it measures 48 x 48', (tester) async {
    await pumpBox(tester, 1);

    expect(tester.getSize(find.byType(PlanDateBox)), const Size(48, 48));
    expect(find.text('MIÉ'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
  });

  testWidgets("at Android's largest text it grows and nothing is cut", (
    tester,
  ) async {
    await pumpBox(tester, 2);

    expect(tester.takeException(), isNull);
    final box = tester.getRect(find.byType(PlanDateBox));
    expect(box.height, greaterThan(48));
    for (final text in ['MIÉ', '14']) {
      final rect = tester.getRect(find.text(text));
      expect(box.contains(rect.topLeft), isTrue, reason: text);
      expect(box.contains(rect.bottomRight - const Offset(1, 1)), isTrue);
    }
  });
}
