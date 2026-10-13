import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/ui/screens/profile/appliances_section.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:bank_storage_app/ui/widgets/option_button.dart';

typedef _Save = ({List<String> ids, Set<String> keep});

Future<List<_Save>> _pumpSection(
  WidgetTester tester, {
  List<String> applianceIds = const [],
  bool pendingSync = false,
  Object? error,
}) async {
  final saves = <_Save>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: AppliancesSection(
          applianceIds: applianceIds,
          pendingSync: pendingSync,
          onSave: (ids, {keep = const {}}) async {
            saves.add((ids: ids, keep: keep));
            if (error != null) throw error;
          },
        ),
      ),
    ),
  );
  return saves;
}

bool _isSelected(WidgetTester tester, String label) => tester
    .widget<OptionButton>(find.widgetWithText(OptionButton, label))
    .selected;

void main() {
  testWidgets('shows every appliance and marks the saved ones', (tester) async {
    await _pumpSection(tester, applianceIds: const ['estufa', 'licuadora']);

    expect(find.byType(OptionButton), findsNWidgets(6));
    expect(_isSelected(tester, 'Estufa'), isTrue);
    expect(_isSelected(tester, 'Licuadora'), isTrue);
    expect(_isSelected(tester, 'Horno'), isFalse);
    expect(find.byTooltip(pendingSyncLabel), findsNothing);
  });

  testWidgets('switching one on saves the whole list in enum order', (
    tester,
  ) async {
    final saves = await _pumpSection(tester, applianceIds: const ['licuadora']);

    await tester.tap(find.text('Estufa'));
    await tester.pump();

    expect(saves.single.ids, ['estufa', 'licuadora']);
  });

  testWidgets('switching one off removes only that appliance', (tester) async {
    final saves = await _pumpSection(
      tester,
      applianceIds: const ['estufa', 'horno'],
    );

    await tester.tap(find.text('Estufa'));
    await tester.pump();

    expect(saves.single.ids, ['horno']);
  });

  testWidgets('keeps saved ids this version does not know', (tester) async {
    final saves = await _pumpSection(
      tester,
      applianceIds: const ['freidora', 'estufa'],
    );

    await tester.tap(find.text('Horno'));
    await tester.pump();

    expect(saves.single.ids, ['estufa', 'horno', 'freidora']);
    expect(saves.single.keep, {'freidora'});
  });

  testWidgets('shows the pending-sync icon while offline', (tester) async {
    await _pumpSection(
      tester,
      applianceIds: const ['estufa'],
      pendingSync: true,
    );

    expect(find.byTooltip(pendingSyncLabel), findsOneWidget);
  });

  testWidgets('shows an error when the rules reject the change', (
    tester,
  ) async {
    await _pumpSection(
      tester,
      error: FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      ),
    );

    await tester.tap(find.text('Horno'));
    await tester.pump();

    expect(
      find.text('No tienes permiso para cambiar los electrodomésticos.'),
      findsOneWidget,
    );
  });

  testWidgets('shows a connection error for any other failure', (tester) async {
    await _pumpSection(tester, error: StateError('offline'));

    await tester.tap(find.text('Horno'));
    await tester.pump();

    expect(
      find.textContaining('No se pudieron guardar los electrodomésticos'),
      findsOneWidget,
    );
  });
}
