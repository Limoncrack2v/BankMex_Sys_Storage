import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/family.dart';
import 'package:bank_storage_app/ui/screens/staff/families_sheet.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:bank_storage_app/ui/widgets/app_buttons.dart';
import 'package:bank_storage_app/ui/widgets/app_text_field.dart';
import 'package:bank_storage_app/ui/widgets/option_button.dart';

import 'helpers/large_text.dart';

final _family = Family(
  familyId: 'familia-1',
  name: 'Familia Ramírez',
  address: 'Calle 1',
  registrationDate: DateTime(2026, 9, 1),
  recoveryQuotaDefault: 250,
  authUid: 'familia-1',
  appliances: const [],
);

/// Lo que recibió el guardado falso.
typedef _Saved = ({String name, String address, double? quota});

Future<List<_Saved>> _pumpForm(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final saved = <_Saved>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: FamilyEditForm(
            family: _family,
            onDone: () {},
            save:
                (
                  family, {
                  required name,
                  required address,
                  required recoveryQuotaDefault,
                }) async {
                  saved.add((
                    name: name,
                    address: address,
                    quota: recoveryQuotaDefault,
                  ));
                },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return saved;
}

PrimaryButton _saveButton(WidgetTester tester) => tester.widget<PrimaryButton>(
  find.widgetWithText(PrimaryButton, 'Guardar cambios'),
);

void main() {
  testWidgets('trae los datos de la familia y no guarda sin cambios', (
    tester,
  ) async {
    await _pumpForm(tester);

    String text(String key) => tester
        .widget<TextField>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(TextField),
          ),
        )
        .controller!
        .text;
    expect(text('familyName'), 'Familia Ramírez');
    expect(text('familyAddress'), 'Calle 1');
    expect(text('familyQuota'), '250');
    expect(_saveButton(tester).onPressed, isNull);
  });

  testWidgets('rechaza un nombre vacío y una cuota que no es número antes '
      'de guardar', (tester) async {
    final saved = await _pumpForm(tester);

    await tester.enterText(find.byKey(const ValueKey('familyName')), '  ');
    await tester.pump();
    expect(find.text('Escribe el nombre de la familia.'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('familyName')),
      'Familia López',
    );
    await tester.enterText(find.byKey(const ValueKey('familyQuota')), '.');
    await tester.pump();
    expect(
      find.text('Escribe la cuota de recuperación o márcala como Exenta.'),
      findsOneWidget,
    );
    expect(_saveButton(tester).onPressed, isNull);

    await tester.tap(find.text('Guardar cambios'));
    await tester.pump();
    expect(saved, isEmpty);
  });

  testWidgets('guarda la dirección corregida y muestra la confirmación', (
    tester,
  ) async {
    final saved = await _pumpForm(tester);

    await tester.enterText(
      find.byKey(const ValueKey('familyAddress')),
      'Calle 2, Guadalajara',
    );
    await tester.pump();
    expect(_saveButton(tester).onPressed, isNotNull);

    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();

    expect(saved, [
      (name: 'Familia Ramírez', address: 'Calle 2, Guadalajara', quota: 250.0),
    ]);
    expect(find.text('Cambios guardados'), findsOneWidget);
    expect(
      find.text('Se guardaron los datos de Familia Ramírez.'),
      findsOneWidget,
    );
  });

  testWidgets('Exenta guarda la cuota en null', (tester) async {
    final saved = await _pumpForm(tester);

    await tester.tap(find.text('Exenta'));
    await tester.pump();
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();

    expect(saved.single.quota, isNull);
  });

  testWidgets('con la letra más grande "Exenta" no se parte', (tester) async {
    await loadAppFonts();
    // Antes: "Exen ta", con el botón de otro alto que el campo.
    await pumpWithTextScale(
      tester,
      SingleChildScrollView(
        child: FamilyEditForm(
          family: _family,
          onDone: () {},
          save: (
            family, {
            required name,
            required address,
            required recoveryQuotaDefault,
          }) async {},
        ),
      ),
      textScale: 2,
      height: 2000,
    );

    expectNoBrokenWords(tester);
    final field = find.byKey(const ValueKey('familyQuota'));
    final exempt = find.widgetWithText(OptionButton, 'Exenta');
    expect(tester.getSize(exempt).height, tester.getSize(field).height);
    expect(tester.widget(field), isA<AppTextField>());
  });
}
