import 'dart:ui';

import '../theme/app_colors.dart';

/// Nivel de urgencia según los días que faltan para que algo caduque.
/// Rojo: 3 días o menos. Naranja: de 4 a 7 días. Verde: más de 7 días.
enum ExpirationUrgency {
  urgent(
    label: 'Urgente',
    accent: AppColors.danger,
    background: AppColors.dangerSoft,
    foreground: AppColors.dangerText,
  ),
  soon(
    label: 'Pronto',
    accent: AppColors.warning,
    background: AppColors.warningSoft,
    foreground: AppColors.warningText,
  ),
  fresh(
    label: 'Fresco',
    accent: AppColors.primary,
    background: AppColors.primarySoft,
    foreground: AppColors.primaryDark,
  );

  const ExpirationUrgency({
    required this.label,
    required this.accent,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color accent;
  final Color background;
  final Color foreground;

  static ExpirationUrgency fromDays(int days) {
    if (days <= 3) return urgent;
    if (days <= 7) return soon;
    return fresh;
  }
}
