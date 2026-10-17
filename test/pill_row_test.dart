import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/ui/widgets/option_button.dart';
import 'package:bank_storage_app/ui/widgets/pill.dart';

// Con la letra de prueba cada letra mide su tamaño, así que los anchos se
// calculan a mano: "Leche" a 10 px mide 50.

const _style = TextStyle(fontSize: 10, height: 1);

Future<void> _pump(WidgetTester tester, double width, Widget child) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

Widget _row(String text) => PillRow(
  leading: Text(text, style: _style),
  // 60 de ancho, 20 de alto.
  trailing: const SizedBox(key: Key('pill'), width: 60, height: 20),
);

void main() {
  group('PillRow', () {
    testWidgets('si la palabra más larga cabe, la píldora va a la derecha '
        'como en un Row con Expanded', (tester) async {
      // "Leche entera": palabra más larga 60; al lado quedan 200 - 8 - 60.
      await _pump(tester, 200, _row('Leche entera'));

      expect(
        tester.getTopLeft(find.byKey(const Key('pill'))),
        const Offset(140, 0),
      );
      expect(tester.getSize(find.text('Leche entera')).width, 132);
    });

    testWidgets('un texto largo de palabras cortas se acomoda al lado', (
      tester,
    ) async {
      // Palabras de 50 o menos en 132 de ancho: varios renglones, sin bajar.
      await _pump(tester, 200, _row('Leche light de vaca y cabra sin sal'));

      expect(tester.getTopLeft(find.byKey(const Key('pill'))).dy, 0);
    });

    testWidgets('si una palabra no cabe al lado, la píldora baja', (
      tester,
    ) async {
      // "semidescremada" mide 140 y al lado solo quedan 132.
      await _pump(tester, 200, _row('Leche semidescremada'));

      final text = tester.getRect(find.text('Leche semidescremada'));
      final pill = tester.getRect(find.byKey(const Key('pill')));
      expect(pill.left, 0);
      expect(pill.top, text.bottom + 8);
      expect(text.width, 200);
      expect(tester.takeException(), isNull);
    });

    testWidgets('en RTL la píldora va a la izquierda', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 200, child: _row('Leche entera')),
          ),
        ),
      );

      expect(tester.getTopLeft(find.byKey(const Key('pill'))).dx, 0);
    });
  });

  group('Pill', () {
    testWidgets('si es más angosta que la etiqueta, la etiqueta baja de '
        'renglón en vez de desbordarse', (tester) async {
      await _pump(
        tester,
        120,
        const Pill(
          label: 'Contiene alérgenos de tu familia',
          background: Colors.red,
          foreground: Colors.white,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(Pill)).width, lessThanOrEqualTo(120));
    });
  });

  group('OptionButtonRow', () {
    Widget options() => MaterialApp(
      home: Scaffold(
        body: OptionButtonRow(
          options: [
            OptionButton(label: 'Familia', selected: true, onTap: () {}),
            OptionButton(label: 'Staff', selected: false, onTap: () {}),
            OptionButton(label: 'Nutriólogo', selected: false, onTap: () {}),
          ],
        ),
      ),
    );

    Future<void> pumpAt(WidgetTester tester, double width, double scale) async {
      tester.view.physicalSize = Size(width, 400);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(options());
    }

    // "Nutriólogo" (10 letras a 15) mide 150; con 600 de ancho a cada botón
    // le tocan (600 - 16) / 3 = 194.7, menos 16 de padding = 178.7.
    testWidgets('si las etiquetas caben, van en un renglón', (tester) async {
      await pumpAt(tester, 600, 1);

      expect(
        tester.getTopLeft(find.text('Nutriólogo')).dy,
        tester.getTopLeft(find.text('Familia')).dy,
      );
    });

    testWidgets('si una no cabe sin partirse, van una debajo de otra', (
      tester,
    ) async {
      // A 1.3 "Nutriólogo" mide 195 y no cabe en 178.7.
      await pumpAt(tester, 600, 1.3);

      expect(
        tester.getTopLeft(find.text('Nutriólogo')).dy,
        greaterThan(tester.getBottomLeft(find.text('Familia')).dy),
      );
      expect(tester.getSize(find.byType(OptionButton).last).width, 600);
    });
  });
}
