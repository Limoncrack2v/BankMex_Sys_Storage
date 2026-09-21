import 'package:flutter/material.dart';

import '../../models/recipe.dart';
import '../../sample_data.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/pill.dart';

/// Abre el detalle de una receta y, si se marca como completada, muestra la
/// confirmación de consumo registrado.
Future<void> openRecipe(
  BuildContext context,
  Recipe recipe, {
  required String backLabel,
}) async {
  final completed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => RecipeDetailScreen(
        recipe: recipe,
        backLabel: backLabel,
        householdSize: SampleData.members.length,
      ),
    ),
  );
  if (completed != true || !context.mounted) return;

  final count = recipe.ingredients.length;
  await showSuccessSheet(
    context,
    title: 'Registrar consumo',
    heading: 'Consumo registrado',
    message:
        'Se actualizó tu despensa con el consumo de $count '
        '${count == 1 ? 'producto' : 'productos'}.',
  );
}

class RecipeDetailScreen extends StatelessWidget {
  const RecipeDetailScreen({
    super.key,
    required this.recipe,
    required this.backLabel,
    required this.householdSize,
  });

  final Recipe recipe;
  final String backLabel;
  final int householdSize;

  @override
  Widget build(BuildContext context) {
    final members = householdSize == 1
        ? '1 integrante'
        : '$householdSize integrantes';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _Header(backLabel: backLabel),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                AspectRatio(
                  aspectRatio: 3 / 2,
                  child: ColoredBox(
                    color: AppColors.primarySoft,
                    child: Image.asset(recipe.image, fit: BoxFit.cover),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(recipe.name, style: AppText.baloo(24, 30)),
                      const SizedBox(height: 8),
                      const Pill.success(label: 'Adaptado al tamaño de tu hogar'),
                      const SizedBox(height: 8),
                      RecipeMeta(recipe),
                      const SizedBox(height: 4),
                      Text(
                        'Receta de nutriólogos de BAMX. Ajustamos las porciones '
                        'a tu hogar ($members) y los cambios seguros según las '
                        'alergias de tu familia.',
                        style: AppText.nunito(
                          14,
                          21,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const _SectionTitle('Ingredientes'),
                      const SizedBox(height: 8),
                      Pill.success(
                        label:
                            'Tienes ${recipe.availableIngredients} de '
                            '${recipe.ingredients.length} ingredientes',
                        withIcon: false,
                      ),
                      const SizedBox(height: 4),
                      for (final ingredient in recipe.ingredients) ...[
                        const SizedBox(height: 8),
                        _IngredientRow(ingredient),
                      ],
                      const SizedBox(height: 20),
                      const _SectionTitle('Preparación'),
                      for (var i = 0; i < recipe.steps.length; i++) ...[
                        SizedBox(height: i == 0 ? 8 : 12),
                        _StepRow(number: i + 1, text: recipe.steps[i]),
                      ],
                      const SizedBox(height: 20),
                      PrimaryButton(
                        label: 'Marcar como completada',
                        icon: AppIcons.check,
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tiempo, porciones y calorías de una receta.
class RecipeMeta extends StatelessWidget {
  const RecipeMeta(this.recipe, {super.key});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final style = AppText.nunito(15, 22.5, color: AppColors.textMuted);

    return Wrap(
      spacing: 16,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _IconText(
          icon: AppIcons.clock,
          text: '${recipe.minutes} min',
          style: style,
        ),
        _IconText(
          icon: AppIcons.users,
          text: recipe.servings == 1
              ? '1 porción'
              : '${recipe.servings} porciones',
          style: style,
        ),
        Text('${recipe.kcalPerServing} kcal por porción', style: style),
      ],
    );
  }
}

class _IconText extends StatelessWidget {
  const _IconText({required this.icon, required this.text, required this.style});

  final String icon;
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(icon, size: 16),
        const SizedBox(width: 4),
        Text(text, style: style),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.backLabel});

  final String backLabel;

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
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
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
                      Text(
                        backLabel,
                        style: AppText.nunito(
                          16,
                          24,
                          weight: FontWeight.w700,
                          color: AppColors.primaryDark,
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

class _IngredientRow extends StatelessWidget {
  const _IngredientRow(this.ingredient);

  final RecipeIngredient ingredient;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ingredient.available ? AppColors.primarySoft : null,
              border: ingredient.available
                  ? null
                  : Border.all(color: AppColors.border, width: 2),
            ),
            alignment: Alignment.center,
            child: ingredient.available
                ? const AppIcon(AppIcons.checkIngredient, size: 16)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(ingredient.name, style: AppText.nunito(16, 24)),
          ),
          const SizedBox(width: 12),
          Text(
            ingredient.amount,
            style: AppText.nunito(15, 22.5, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
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
    );
  }
}
