import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Tipografías del diseño: Baloo 2 para títulos y Nunito para texto.
/// Los tamaños y alturas de línea están en px de Figma (= píxeles lógicos).
abstract final class AppText {
  static TextStyle baloo(
    double size,
    double lineHeight, {
    FontWeight weight = FontWeight.w700,
    Color color = AppColors.text,
  }) => TextStyle(
    fontFamily: 'Baloo2',
    fontSize: size,
    height: lineHeight / size,
    fontWeight: weight,
    color: color,
  );

  static TextStyle nunito(
    double size,
    double lineHeight, {
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.text,
  }) => TextStyle(
    fontFamily: 'Nunito',
    fontSize: size,
    height: lineHeight / size,
    fontWeight: weight,
    color: color,
  );
}
