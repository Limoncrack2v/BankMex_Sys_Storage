import 'package:flutter/widgets.dart';

/// Ancho de la palabra más larga de [text] con [style] y la letra del sistema.
/// En un espacio más angosto, Flutter parte esa palabra en dos renglones.
double longestWordWidth(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = painter.minIntrinsicWidth;
  painter.dispose();
  return width;
}
