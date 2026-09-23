import 'package:flutter/material.dart';

/// Paleta tomada del Figma "Bank Storage" (página Week 5 Presentation).
abstract final class AppColors {
  static const primary = Color(0xFF2E7D32);
  static const primaryDark = Color(0xFF1B5E20);
  static const primarySoft = Color(0xFFE6F2E6);

  static const text = Color(0xFF1F2417);
  static const textMuted = Color(0xFF5B6152);
  static const hint = Color(0x801F2417);

  static const border = Color(0xFFE4E5DF);
  static const background = Color(0xFFF7F7F5);
  static const surface = Colors.white;
  static const scrim = Color(0x661F2417);

  static const danger = Color(0xFFD32F2F);
  static const dangerSoft = Color(0xFFFBE3E3);
  static const dangerText = Color(0xFFA31F1F);

  static const warning = Color(0xFFF57C00);
  static const warningSoft = Color(0xFFFDEDDB);
  static const warningText = Color(0xFFB45C00);

  // Pizarra de la paleta de gráficas del Make (badge "Reasignada"), distinta
  // de los verdes y naranjas de estado.
  static const slate = Color(0xFF6B7F99);
  static const slateSoft = Color(0x296B7F99);
}
