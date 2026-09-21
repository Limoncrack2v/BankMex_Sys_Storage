import 'package:flutter/material.dart';

import '../../models/recipe.dart';
import '../../sample_data.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_header.dart';
import '../../widgets/pill.dart';
import '../recipes/recipe_detail_screen.dart';

/// Plan de comidas semanal: una receta por día, priorizando lo que caduca antes.
class MealPlanScreen extends StatelessWidget {
  const MealPlanScreen({super.key, this.entries = SampleData.mealPlan});

  final List<MealPlanEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AppHeader(title: 'Plan de comidas'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const InfoBanner(
                message: 'Tu plan usa primero lo que caduca antes',
                background: AppColors.primarySoft,
                foreground: AppColors.primaryDark,
              ),
              for (final entry in entries) ...[
                const SizedBox(height: 12),
                _DayCard(
                  entry: entry,
                  onTap: () => openRecipe(
                    context,
                    entry.recipe,
                    backLabel: 'Volver al plan de comidas',
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.entry, required this.onTap});

  final MealPlanEntry entry;
  final VoidCallback onTap;

  static const _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(16)),
    side: BorderSide(color: AppColors.border),
  );

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: _shape,
      child: InkWell(
        onTap: onTap,
        customBorder: _shape,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  entry.day.toUpperCase(),
                  style: AppText.nunito(
                    11,
                    16.5,
                    weight: FontWeight.w700,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.recipe.name,
                      style: AppText.baloo(18, 22.5, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.reason,
                      style: AppText.nunito(
                        14,
                        21,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Pill(
                label: entry.urgency.label,
                background: entry.urgency.background,
                foreground: entry.urgency.foreground,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                fontSize: 13,
                lineHeight: 19.5,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
