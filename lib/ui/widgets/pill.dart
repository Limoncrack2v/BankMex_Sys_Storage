import 'package:flutter/material.dart';

import '../theme/app_assets.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'app_icon.dart';

/// Etiqueta redondeada (badges de caducidad, "Tienes todos los ingredientes",
/// etc.).
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
    this.iconSize = 16,
    this.gap = 6,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    this.fontSize = 14,
    this.lineHeight = 21,
  });

  /// Pill verde con palomita, usado en recetas.
  const Pill.success({super.key, required this.label, bool withIcon = true})
    : background = AppColors.primarySoft,
      foreground = AppColors.primaryDark,
      icon = withIcon ? AppIcons.checkBadge : null,
      iconSize = 16,
      gap = 6,
      padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      fontSize = 14,
      lineHeight = 21;

  final String label;
  final Color background;
  final Color foreground;
  final String? icon;
  final double iconSize;
  final double gap;
  final EdgeInsets padding;
  final double fontSize;
  final double lineHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: ShapeDecoration(
        color: background,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            AppIcon(icon!, size: iconSize, color: foreground),
            SizedBox(width: gap),
          ],
          Text(
            label,
            style: AppText.nunito(
              fontSize,
              lineHeight,
              weight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

/// Aviso de ancho completo con fondo de color (p. ej. "7 productos caducan
/// pronto").
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.message,
    required this.background,
    required this.foreground,
  });

  final String message;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
        style: AppText.nunito(
          15,
          22.5,
          weight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}
