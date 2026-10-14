import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/repositories/auth_repository.dart';
import 'package:bank_storage_app/ui/screens/session/step_up_sheet.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:bank_storage_app/ui/widgets/app_bottom_sheet.dart';
import 'package:bank_storage_app/ui/widgets/app_buttons.dart';

const _title = 'Confirma tu identidad';

void _useSheetSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _pumpSheet(
  WidgetTester tester,
  Future<void> Function(String password) reauthenticate,
) async {
  _useSheetSize(tester);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: StepUpSheet(reauthenticate: reauthenticate)),
    ),
  );
  await tester.pumpAndSettle();
}

/// Abre el sheet desde un botón, como ensureRecentSignIn, y regresa el
/// resultado pendiente de showAppBottomSheet.
Future<Future<bool?>> _openSheet(
  WidgetTester tester,
  Future<void> Function(String password) reauthenticate,
) async {
  _useSheetSize(tester);
  late Future<bool?> result;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = showAppBottomSheet<bool>(
              context,
              enableDrag: false,
              builder: (_) => StepUpSheet(reauthenticate: reauthenticate),
            ),
            child: const Text('Abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
  return result;
}

Finder get _confirmFinder => find.widgetWithText(PrimaryButton, 'Confirmar');

PrimaryButton _confirmButton(WidgetTester tester) =>
    tester.widget<PrimaryButton>(_confirmFinder);

void main() {
  testWidgets('Confirmar se habilita al escribir la contraseña', (
    tester,
  ) async {
    await _pumpSheet(tester, (_) async {});
    expect(_confirmButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'bamx1234');
    await tester.pump();
    expect(_confirmButton(tester).onPressed, isNotNull);
  });

  testWidgets('con contraseña incorrecta muestra el error y sigue abierto', (
    tester,
  ) async {
    const message = 'Contraseña incorrecta. Intenta de nuevo.';
    await _pumpSheet(tester, (_) async => throw AuthException(message));

    await tester.enterText(find.byType(TextField), 'equivocada');
    await tester.pump();
    await tester.tap(_confirmFinder);
    await tester.pumpAndSettle();

    expect(find.text(message), findsOneWidget);
    expect(find.text(_title), findsOneWidget);
  });

  testWidgets('con la contraseña correcta cierra con true', (tester) async {
    final received = <String>[];
    final result = await _openSheet(tester, (p) async => received.add(p));

    await tester.enterText(find.byType(TextField), 'bamx1234');
    await tester.pump();
    await tester.tap(_confirmFinder);
    await tester.pumpAndSettle();

    expect(await result, isTrue);
    expect(received, ['bamx1234']);
    expect(find.text(_title), findsNothing);
  });

  testWidgets('cerrarlo con la X regresa null sin confirmar', (tester) async {
    final received = <String>[];
    final result = await _openSheet(tester, (p) async => received.add(p));

    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();

    expect(await result, isNull);
    expect(received, isEmpty);
  });
}
