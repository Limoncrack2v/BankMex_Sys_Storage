import 'package:flutter/material.dart';

import '../../../data/models/pantry_item.dart';
import '../../../domain/models/recipe.dart';
import '../../../domain/models/recipe_adjustment.dart';
import '../../../domain/recipe_adjustment.dart';
import '../../formatting.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/pill.dart';
import 'adjustment_queue.dart';

/// Abre la revisión de [item].
Future<void> openAdjustmentReview(
  BuildContext context, {
  required AdjustmentQueueItem item,
}) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => AdjustmentReviewScreen(item: item)),
  );
}

/// La revisión de una adaptación pendiente: la receta publicada, el hogar
/// (tamaño y alergias, sin nombres), qué cambia y por qué, y cómo quedan los
/// ingredientes. Si la familia nunca la vería, lo avisa.
class AdjustmentReviewScreen extends StatelessWidget {
  const AdjustmentReviewScreen({super.key, required this.item});

  final AdjustmentQueueItem item;

  @override
  Widget build(BuildContext context) {
    final adjustment = item.adjustment;
    final recipe = item.recipe;
    final warning = _warning(item);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const _Header(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                Text(item.title, style: AppText.baloo(24, 30)),
                if (recipe != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _meta(recipe),
                    style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
                  ),
                ],
                const SizedBox(height: 16),
                _HouseholdBox(item),
                const SizedBox(height: 20),
                const _SectionTitle('Cambios'),
                for (final change in adjustment.changes) ...[
                  const SizedBox(height: 8),
                  _ChangeRow(
                    title: item.changeTitle(change),
                    detail: _changeDetail(item, change),
                  ),
                ],
                const SizedBox(height: 20),
                const _SectionTitle('Ingredientes de la adaptación'),
                for (final (ingredient, replaced) in _withReplaced(
                  adjustment,
                )) ...[
                  const SizedBox(height: 8),
                  _IngredientRow(ingredient, replaced: replaced),
                ],
                if (recipe != null && recipe.steps.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const _SectionTitle('Preparación'),
                  for (final (index, step) in recipe.steps.indexed) ...[
                    SizedBox(height: index == 0 ? 8 : 12),
                    _StepRow(number: index + 1, text: step),
                  ],
                ],
                if (warning != null) ...[
                  const SizedBox(height: 20),
                  InfoBanner(
                    message: warning,
                    background: AppColors.warningSoft,
                    foreground: AppColors.warningText,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "10 min · 2 porciones · 180 kcal por porción", como en las recetas por
  /// revisar.
  static String _meta(Recipe recipe) => [
    '${recipe.prepTimeMinutes} min',
    recipe.servings == 1 ? '1 porción' : '${recipe.servings} porciones',
    if (recipe.caloriesPerServing > 0)
      '${recipe.caloriesPerServing} kcal por porción',
  ].join(' · ');

  /// Por qué la familia no vería la adaptación, o null si sí la vería.
  static String? _warning(AdjustmentQueueItem item) => switch (item.staleness) {
    null => null,
    AdjustmentStaleness.changed =>
      'La receta cambió después de esta sugerencia y la familia ya no la '
          'vería. Recházala; se sugerirá otra cuando la familia vuelva a abrir '
          'la receta.',
    AdjustmentStaleness.unavailable =>
      'La receta ya no está publicada, así que la familia no vería esta '
          'adaptación. Puedes rechazarla.',
    AdjustmentStaleness.unsafe =>
      'Esta adaptación todavía lleva un ingrediente con un alérgeno del hogar '
          '(${item.allergenIngredient}). Recházala.',
  };

  /// "Para 4 integrantes" o, de una sustitución, su motivo: "Por alergia a
  /// lácteos".
  static String? _changeDetail(
    AdjustmentQueueItem item,
    AdjustmentChange change,
  ) {
    if (change.kind == AdjustmentChange.kindPortions) {
      return 'Para ${item.householdMembers}';
    }
    final reason = change.reason.trim();
    if (reason.isEmpty) return null;
    return 'Por ${reason[0].toLowerCase()}${reason.substring(1)}';
  }

  /// Los ingredientes de la adaptación, cada uno con el que reemplaza si
  /// salió de una sustitución. Las sustituciones se toman en orden, así que
  /// dos ingredientes con el mismo sustituto no se confunden.
  static List<(RecipeIngredient, String?)> _withReplaced(
    RecipeAdjustment adjustment,
  ) {
    final substitutions = [
      for (final change in adjustment.changes)
        if (change.kind == AdjustmentChange.kindSubstitution &&
            change.from != null)
          change,
    ];
    final rows = <(RecipeIngredient, String?)>[];
    for (final ingredient in adjustment.ingredients) {
      final index = substitutions.indexWhere(
        (change) => change.to == ingredient.productName,
      );
      rows.add((
        ingredient,
        index < 0 ? null : substitutions.removeAt(index).from,
      ));
    }
    return rows;
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              button: true,
              child: InkWell(
                onTap: () => Navigator.of(context).maybePop(),
                customBorder: const StadiumBorder(),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AppIcon(AppIcons.arrowLeft, size: 20),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Volver a la lista',
                            style: AppText.nunito(
                              16,
                              24,
                              weight: FontWeight.w700,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// El hogar para el que se sugirió y lo que verá la familia si se aprueba.
class _HouseholdBox extends StatelessWidget {
  const _HouseholdBox(this.item);

  final AdjustmentQueueItem item;

  @override
  Widget build(BuildContext context) {
    final text = AppText.nunito(15, 22.5);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Adaptación para un hogar de ${item.householdMembers}',
            style: AppText.nunito(
              15,
              22.5,
              weight: FontWeight.w700,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(item.allergiesLabel, style: text),
          const SizedBox(height: 8),
          Text(
            'Lo que verá la familia: ${item.adjustment.summary}',
            style: text,
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppText.baloo(19, 28.5));
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.title, required this.detail});

  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppText.nunito(16, 24, weight: FontWeight.w700)),
          if (detail != null)
            Text(
              detail,
              style: AppText.nunito(14, 21, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow(this.ingredient, {required this.replaced});

  final RecipeIngredient ingredient;

  /// El ingrediente de la receta que este reemplaza, si es una sustitución.
  final String? replaced;

  @override
  Widget build(BuildContext context) {
    final replaced = this.replaced;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      // Con letra grande la cantidad baja en vez de partir el nombre.
      child: PillRow(
        leading: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ingredient.productName, style: AppText.nunito(16, 24)),
            if (replaced != null)
              Text(
                'En lugar de $replaced',
                style: AppText.nunito(14, 21, color: AppColors.textMuted),
              ),
          ],
        ),
        trailing: Text(
          _amount(ingredient),
          style: AppText.nunito(15, 22.5, weight: FontWeight.w700),
        ),
      ),
    );
  }

  /// "0.25 kg", "2 latas"; una unidad que no se reconoce va como está (igual
  /// que en las recetas por revisar).
  static String _amount(RecipeIngredient ingredient) {
    final unit = FoodUnit.values
        .where((option) => option.name == ingredient.unit.trim().toLowerCase())
        .firstOrNull;
    return unit == null
        ? '${formatNumber(ingredient.quantity)} ${ingredient.unit}'
        : formatAmount(ingredient.quantity, unit);
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    // El círculo crece con la letra para que el número quepa.
    final size = MediaQuery.textScalerOf(context).scale(32);

    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$number',
              style: AppText.baloo(16, 24, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(text, style: AppText.nunito(16, 22)),
            ),
          ),
        ],
      ),
    );
  }
}
