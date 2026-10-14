import 'package:flutter/material.dart';

import '../../../data/models/member.dart';
import '../../../data/models/pantry_item.dart';
import '../../../domain/meal_plan_edits.dart';
import '../../../domain/models/meal_plan.dart';
import '../../models/expiration_urgency.dart';
import '../../models/recipe.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/pill.dart';
import '../profile/appliances_section.dart' show pendingSyncLabel;
import 'leftover_ingredients_section.dart';

const _months = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// "14 de octubre".
String _dayOfMonth(DateTime date) =>
    '${date.day} de ${_months[date.month - 1]}';

/// "del 14 al 20 de octubre", "del 28 de septiembre al 4 de octubre".
String _rangeLabel(DateTime first, DateTime last) {
  final sameMonth = first.year == last.year && first.month == last.month;
  return 'del ${sameMonth ? first.day : _dayOfMonth(first)} al '
      '${_dayOfMonth(last)}';
}

/// El plan que guardó la familia (mealPlans/{id}): una tarjeta por día, de hoy
/// al último del plan (los días que ya pasaron no se muestran), y lo que le
/// sobra de la despensa después de cocinarlo.
///
/// Los recipeId del plan se buscan en [recipes]; si la receta ya no está (se
/// borró del catálogo o volvió a revisión), el día dice "Receta no
/// disponible".
class SavedPlanView extends StatelessWidget {
  const SavedPlanView({
    super.key,
    required this.plan,
    required this.pendingSync,
    required this.recipes,
    required this.members,
    required this.pantry,
    required this.today,
    this.catalogFailed = false,
    required this.onOpenRecipe,
  });

  final MealPlan plan;

  /// Si el plan tiene cambios que siguen en el dispositivo (sin conexión).
  final bool pendingSync;

  /// Recetas que puede ver la familia, sin ajustar al hogar.
  final List<Recipe> recipes;
  final List<Member> members;
  final List<PantryItem> pantry;
  final DateTime today;

  /// Si no se pudo leer el catálogo: una receta que no está en [recipes] no
  /// se sabe si sigue en él.
  final bool catalogFailed;

  /// Recibe la receta original: el detalle ajusta las porciones él mismo.
  final ValueChanged<Recipe> onOpenRecipe;

  @override
  Widget build(BuildContext context) {
    final byId = {
      for (final recipe in recipes)
        if (recipe.id.isNotEmpty) recipe.id: recipe,
    };
    final start = MealPlanEdits.dateOnly(plan.dateRangeStart);
    final end = MealPlanEdits.dateOnly(plan.dateRangeEnd);
    final first = MealPlanEdits.dateOnly(today).isAfter(start)
        ? MealPlanEdits.dateOnly(today)
        : start;

    // Lo que se va a cocinar de hoy en adelante, para "Lo que te sobra".
    final entries = <MealPlanEntry>[];
    final cards = <Widget>[];
    for (
      var day = first;
      day.isBefore(end) && cards.length < MealPlanEdits.maxMeals;
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      final meal = MealPlanEdits.mealOn(plan, day);
      final recipe = meal == null ? null : byId[meal.recipeId];
      if (meal == null) {
        cards.add(
          _PlanDayCard(
            date: day,
            title: 'Día libre',
            message: 'No hay receta para este día.',
          ),
        );
      } else if (recipe == null && catalogFailed) {
        cards.add(_notLoadedCard(day));
      } else if (recipe == null) {
        cards.add(
          _PlanDayCard(
            date: day,
            title: 'Receta no disponible',
            message:
                'La receta que guardaste ya no está en el catálogo de BAMX.',
          ),
        );
      } else {
        final entry = planEntryFor(
          scaledForHousehold(recipe, members),
          day,
          pantry,
          today: today,
        );
        entries.add(entry);
        cards.add(
          _PlanDayCard(
            date: day,
            title: recipe.name,
            message: entry.reason,
            urgency: entry.urgency,
            hasAllergens: allergyConflicts(recipe, members).isNotEmpty,
            onTap: () => onOpenRecipe(recipe),
          ),
        );
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SavedPlanBanner(
          range: _rangeLabel(start, DateTime(end.year, end.month, end.day - 1)),
          pendingSync: pendingSync,
        ),
        for (final card in cards) ...[const SizedBox(height: 12), card],
        if (entries.isNotEmpty) ...[
          const SizedBox(height: 24),
          LeftoverIngredientsSection(
            leftovers: planLeftovers(entries, pantry, today: today),
            today: today,
          ),
        ],
      ],
    );
  }

  /// El día de una receta que no se sabe si sigue en el catálogo.
  Widget _notLoadedCard(DateTime day) => _PlanDayCard(
    date: day,
    title: 'Receta sin cargar',
    message: 'No pudimos cargar esta receta.',
  );
}

/// Aviso de arriba: las fechas del plan y si falta sincronizarlo.
class _SavedPlanBanner extends StatelessWidget {
  const _SavedPlanBanner({required this.range, required this.pendingSync});

  final String range;
  final bool pendingSync;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tu plan guardado: $range',
            style: AppText.nunito(
              15,
              22.5,
              weight: FontWeight.w700,
              color: AppColors.primaryDark,
            ),
          ),
          if (pendingSync) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const AppIcon(AppIcons.cloudPending, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    pendingSyncLabel,
                    style: AppText.nunito(14, 21, color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Un día del plan guardado, con el mismo cuadro del día que las tarjetas del
/// plan sugerido. Sin [urgency] es un día sin receta que mostrar.
class _PlanDayCard extends StatelessWidget {
  const _PlanDayCard({
    required this.date,
    required this.title,
    required this.message,
    this.urgency,
    this.hasAllergens = false,
    this.onTap,
  });

  final DateTime date;
  final String title;

  /// Por qué se eligió la receta, o qué pasa con el día.
  final String message;
  final ExpirationUrgency? urgency;

  /// Si la receta lleva algo a lo que un integrante es alérgico.
  final bool hasAllergens;

  /// Abre la receta; null en un día sin receta.
  final VoidCallback? onTap;

  static const _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(16)),
    side: BorderSide(color: AppColors.border),
  );

  @override
  Widget build(BuildContext context) {
    final urgency = this.urgency;

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
              _DayTile(date),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppText.baloo(
                        18,
                        22.5,
                        weight: FontWeight.w600,
                        color: onTap == null
                            ? AppColors.textMuted
                            : AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message,
                      style: AppText.nunito(14, 21, color: AppColors.textMuted),
                    ),
                    if (hasAllergens) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Contiene alérgenos de tu familia',
                        style: AppText.nunito(
                          14,
                          21,
                          weight: FontWeight.w700,
                          color: AppColors.dangerText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (urgency != null) ...[
                const SizedBox(width: 12),
                Pill(
                  label: urgency.label,
                  background: urgency.background,
                  foreground: urgency.foreground,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  fontSize: 13,
                  lineHeight: 19.5,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Día de la semana y número: en un plan de 14 días hay dos "LUN".
class _DayTile extends StatelessWidget {
  const _DayTile(this.date);

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
