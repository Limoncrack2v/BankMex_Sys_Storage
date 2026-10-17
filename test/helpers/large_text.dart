import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/ui/theme/app_theme.dart';

/// Carga Nunito y Baloo 2 para que los textos midan lo mismo que en el
/// teléfono (sin esto las pruebas usan una letra de cuadritos).
Future<void> loadAppFonts() async {
  final nunito = FontLoader('Nunito')
    ..addFont(rootBundle.load('assets/fonts/Nunito-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Nunito-Bold.ttf'));
  final baloo = FontLoader('Baloo2')
    ..addFont(rootBundle.load('assets/fonts/Baloo2-SemiBold.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Baloo2-Bold.ttf'));
  await Future.wait([nunito.load(), baloo.load()]);
}

/// Pantalla de [width] de ancho con el tamaño de letra del sistema en
/// [textScale] (1.3 = "letra grande" de Android).
Future<void> pumpWithTextScale(
  WidgetTester tester,
  Widget body, {
  required double textScale,
  double width = 360,
  double height = 800,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: body),
    ),
  );
  await tester.pumpAndSettle();
}

/// Ningún texto parte una palabra: la más larga de cada texto cabe en su
/// ancho. Los de un solo renglón (se cortan con «…») no cuentan.
void expectNoBrokenWords(WidgetTester tester) {
  final paragraphs = tester.allRenderObjects
      .whereType<RenderParagraph>()
      .toSet();
  for (final paragraph in paragraphs) {
    if (paragraph.maxLines == 1) continue;
    final longestWord = paragraph.getMinIntrinsicWidth(double.infinity);
    expect(
      longestWord,
      lessThanOrEqualTo(paragraph.constraints.maxWidth + 0.01),
      reason:
          '"${paragraph.text.toPlainText()}" parte una palabra: su palabra '
          'más larga mide ${longestWord.toStringAsFixed(1)} y tiene '
          '${paragraph.constraints.maxWidth.toStringAsFixed(1)}',
    );
  }
}
