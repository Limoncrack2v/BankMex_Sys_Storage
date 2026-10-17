import 'package:flutter/material.dart';

import '../../models/recipe.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';

/// Día de la semana y número de una tarjeta del plan: en un plan de 14 días
/// hay dos "LUN". Mide 48 × 48 y crece con la letra grande.
class PlanDateBox extends StatelessWidget {
  const PlanDateBox(this.date, {super.key});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            planDayLabel(date).toUpperCase(),
            style: AppText.nunito(
              11,
              16.5,
              weight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
          Text(
            '${date.day}',
            style: AppText.baloo(16, 20, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
