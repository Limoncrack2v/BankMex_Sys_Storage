import 'package:flutter/material.dart';

import '../../../data/models/member.dart';
import '../../../data/models/pantry_item.dart';
import '../../../domain/meal_plan_edits.dart';
import '../../../domain/models/appliance.dart';
import '../../../domain/models/meal_plan.dart';
import '../../formatting.dart';
import '../../models/expiration_urgency.dart';
import '../../models/recipe.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/danger_buttons.dart';
import '../../widgets/pill.dart';
import '../profile/appliances_section.dart' show pendingSyncLabel;
import 'delete_meal_plan_sheet.dart';
import 'edit_plan_day_sheet.dart';
import 'leftover_ingredients_section.dart';
import 'meal_plan_saving.dart';
import 'plan_date_box.dart';

const _weekdays = [
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
  'domingo',
];

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

/// "miércoles 16".
String _dayName(DateTime date) => '${_weekdays[date.weekday - 1]} ${date.day}';

/// "Miércoles 16 de octubre".
String _dayTitle(DateTime date) {
  final weekday = _weekdays[date.weekday - 1];
  return '${weekday[0].toUpperCase()}${weekday.substring(1)} '
      '${_dayOfMonth(date)}';
}

/// El plan que guardó la familia (mealPlans/{id}): una tarjeta por día, de hoy
/// al último del plan (los días que ya pasaron no se muestran), y lo que le
/// sobra de la despensa después de cocinarlo. Cada día se puede cambiar de
/// receta o dejar libre, y el plan se puede eliminar.
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
    this.warnings = const [],
    this.catalogFailed = false,
    this.appliances = const [],
    required this.onOpenRecipe,
    required this.onSaveMeals,
    required this.onDelete,
  });

  final MealPlan plan;

  /// Si el plan tiene cambios que siguen en el dispositivo (sin conexión).
  final bool pendingSync;

  /// Recetas que puede ver la familia, sin ajustar al hogar.
  final List<Recipe> recipes;
  final List<Member> members;
  final List<PantryItem> pantry;
  final DateTime today;

  /// Lo que no se pudo leer; va arriba de los días.
  final List<String> warnings;

  /// Si no se pudo leer el catálogo: una receta que no está en [recipes] no
  /// se sabe si sigue en él.
  final bool catalogFailed;

  /// Ids de Appliance del hogar; vacía si no se sabe ([lacksAppliance]).
  final List<String> appliances;

  /// Recibe la receta original: el detalle ajusta las porciones él mismo.
  final ValueChanged<Recipe> onOpenRecipe;

  /// Guarda las comidas del plan después de cambiar un día. Null si no se
  /// puede: [warnings] dice por qué o, sin avisos, las recetas son de ejemplo.
  final Future<void> Function(MealPlan plan)? onSaveMeals;

  /// Elimina el plan.
  final Future<void> Function() onDelete;

  void _editDay(
    BuildContext context,
    DateTime day,
    MealPlanMeal? meal,
    List<MealPlanEntry> earlier,
    Future<void> Function(MealPlan plan) save,
  ) {
    // Como "Pedir una receta": nada con alérgenos de la familia.
    final options = planOptionsFor(
      [
        for (final recipe in recipes)
          if (recipe.id.isNotEmpty && allergyConflicts(recipe, members).isEmpty)
            scaledForHousehold(recipe, members),
      ],
      pantry,
      day,
      earlier: earlier,
    );
    showEditPlanDaySheet(
      context,
      title: _dayTitle(day),
      dayName: _dayName(day),
      options: [
        for (final entry in options)
          (entry: entry, missingAppliances: _missingAppliances(entry.recipe)),
      ],
      currentRecipeId: meal?.recipeId,
      onPick: (recipe) => save(
        MealPlanEdits.withRecipe(
          plan,
          day,
          recipeId: recipe.id,
          servings: planServings(members, recipe),
        ),
      ),
      onClear: meal == null
          ? null
          : () => save(MealPlanEdits.withoutMeal(plan, day)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final byId = {
      for (final recipe in recipes)
        if (recipe.id.isNotEmpty) recipe.id: recipe,
    };
    final start = MealPlanEdits.dateOnly(plan.dateRangeStart);
    final end = MealPlanEdits.dateOnly(plan.dateRangeEnd);
    final range = _rangeLabel(
      start,
      DateTime(end.year, end.month, end.day - 1),
    );
    final first = MealPlanEdits.dateOnly(today).isAfter(start)
        ? MealPlanEdits.dateOnly(today)
        : start;

    final save = onSaveMeals;
    // Lo que se va a cocinar de hoy en adelante, en orden: lo usan los días
    // siguientes, como en el plan sugerido, y "Lo que te sobra".
    final entries = <MealPlanEntry>[];
    final cards = <Widget>[];
    for (
      var day = first;
      day.isBefore(end) && cards.length < MealPlan.maxMeals;
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      final meal = MealPlanEdits.mealOn(plan, day);
      final recipe = meal == null ? null : byId[meal.recipeId];
      final earlier = List.of(entries);
      final edit = save == null
          ? null
          : () => _editDay(context, day, meal, earlier, save);
      if (meal == null) {
        cards.add(
          _PlanDayCard(
            date: day,
            title: 'Día libre',
            message: 'No hay receta para este día.',
            action: edit == null
                ? null
                : _CardAction(
                    label: 'Elegir receta',
                    semanticLabel: 'Elegir receta para el ${_dayName(day)}',
                    onPressed: edit,
                  ),
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
            action: edit == null
                ? null
                : _CardAction(
                    label: 'Elegir otra',
                    semanticLabel:
                        'Elegir otra receta para el ${_dayName(day)}',
                    onPressed: edit,
                  ),
          ),
        );
      } else {
        final entry = planEntryFor(
          scaledForHousehold(recipe, members),
          day,
          pantry,
          earlier: earlier,
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
            action: edit == null
                ? null
                : _CardAction(
                    label: 'Cambiar',
                    semanticLabel: 'Cambiar la receta del ${_dayName(day)}',
                    onPressed: edit,
                  ),
          ),
        );
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SavedPlanBanner(range: range, pendingSync: pendingSync),
        for (final warning in warnings) ...[
          const SizedBox(height: 12),
          InfoBanner(
            message: warning,
            background: AppColors.warningSoft,
            foreground: AppColors.warningText,
          ),
        ],
        if (save == null && warnings.isEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Para cambiar tu plan hacen falta recetas del catálogo de BAMX.',
            style: AppText.nunito(14, 21, color: AppColors.textMuted),
          ),
        ],
        for (final card in cards) ...[const SizedBox(height: 12), card],
        if (entries.isNotEmpty) ...[
          const SizedBox(height: 24),
          LeftoverIngredientsSection(
            leftovers: planLeftovers(entries, pantry, today: today),
            today: today,
          ),
        ],
        const SizedBox(height: 24),
        Center(
          child: DangerLinkButton(
            label: 'Eliminar plan',
            semanticLabel: 'Eliminar plan $range',
            onPressed: () => showDeleteMealPlanSheet(
              context,
              range: range,
              onDelete: onDelete,
            ),
          ),
        ),
      ],
    );
  }

  /// Lo que pide [recipe] y no tiene el hogar, p. ej. "licuadora".
  List<String> _missingAppliances(Recipe recipe) => [
    if (lacksAppliance(recipe, appliances))
      for (final id in recipe.requiredEquipment)
        if (!appliances.contains(id))
          switch (Appliance.fromId(id)) {
            final appliance? => applianceLabel(appliance).toLowerCase(),
            null => id,
          },
  ];

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

/// Un día del plan guardado, con el cuadro del día del plan sugerido. Sin
/// [urgency] es un día sin receta que mostrar; la acción va hasta abajo.
class _PlanDayCard extends StatelessWidget {
  const _PlanDayCard({
    required this.date,
    required this.title,
    required this.message,
    this.action,
    this.urgency,
    this.hasAllergens = false,
    this.onTap,
  });

  final DateTime date;
  final String title;

  /// Por qué se eligió la receta, o qué pasa con el día.
  final String message;

  /// "Cambiar", "Elegir receta"…; null si el día no se puede cambiar.
  final Widget? action;
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
    final action = this.action;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppText.baloo(
            18,
            22.5,
            weight: FontWeight.w600,
            color: onTap == null ? AppColors.textMuted : AppColors.text,
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
    );

    return Material(
      color: AppColors.surface,
      shape: _shape,
      child: InkWell(
        onTap: onTap,
        customBorder: _shape,
        child: Padding(
          // La acción ya trae aire abajo: mide 48 dp aunque el texto no.
          padding: EdgeInsets.fromLTRB(16, 16, 16, action == null ? 16 : 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PlanDateBox(date),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (urgency == null)
                      text
                    else
                      PillRow(
                        gap: 12,
                        leading: text,
                        trailing: Pill(
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
                      ),
                    if (action != null) ...[const SizedBox(height: 2), action],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Enlace verde subrayado de una tarjeta del plan, como [TextLinkButton] pero
/// alineado con el texto de la tarjeta y de 48 dp de alto.
class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
  });

  final String label;

  /// [label] con el día: cada tarjeta tiene un "Cambiar".
  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: semanticLabel,
      onTap: onPressed,
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: Text(
              label,
              style:
                  AppText.nunito(
                    15,
                    22.5,
                    weight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ).copyWith(
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.primaryDark,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
