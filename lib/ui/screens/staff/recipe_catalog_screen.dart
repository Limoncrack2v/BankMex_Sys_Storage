import 'package:flutter/material.dart';

import '../../../application/bank_storage_facade.dart';
import '../../../data/models/pantry_item.dart';
import '../../../domain/models/recipe.dart';
import '../../formatting.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/pill.dart';
import 'recipe_form_sheet.dart';

/// Pestaña "Catálogo de recetas" del staff: da de alta, edita y elimina
/// recetas. Staff las deja en borrador o pendientes de revisión; solo el
/// nutriólogo las aprueba, y las familias solo ven las aprobadas.
class RecipeCatalogScreen extends StatefulWidget {
  const RecipeCatalogScreen({super.key});

  @override
  State<RecipeCatalogScreen> createState() => _RecipeCatalogScreenState();
}

class _RecipeCatalogScreenState extends State<RecipeCatalogScreen> {
  late final Stream<List<Recipe>> _recipes;

  @override
  void initState() {
    super.initState();
    _recipes = BankStorageFacade().watchStaffRecipes();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Catálogo de recetas', style: AppText.baloo(22, 27.5)),
          const SizedBox(height: 2),
          Text(
            'Prepara las recetas. El nutriólogo las revisa y las familias ven '
            'las que él aprueba.',
            style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Nueva receta',
            icon: AppIcons.plus,
            onPressed: () => showRecipeFormSheet(context),
          ),
          const SizedBox(height: 24),
          StreamBuilder<List<Recipe>>(
            stream: _recipes,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const InfoBanner(
                  message:
                      'No se pudieron cargar las recetas. Revisa tu conexión '
                      'e intenta de nuevo.',
                  background: AppColors.dangerSoft,
                  foreground: AppColors.dangerText,
                );
              }
              final recipes = snapshot.data;
              if (recipes == null) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                );
              }
              if (recipes.isEmpty) return const _EmptyCatalog();

              // Primero las que esperan al nutriólogo, luego los borradores y al
              // final las aprobadas; dentro de cada estado, por nombre.
              final sorted = [...recipes]
                ..sort((a, b) {
                  if (a.status != b.status) {
                    return _order(a.status).compareTo(_order(b.status));
                  }
                  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
                });

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, recipe) in sorted.indexed) ...[
                    if (index > 0) const SizedBox(height: 12),
                    _RecipeCard(
                      recipe: recipe,
                      onEdit: () => showRecipeFormSheet(context, recipe: recipe),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

int _order(RecipeStatus status) => switch (status) {
  RecipeStatus.pending => 0,
  RecipeStatus.draft => 1,
  RecipeStatus.approved => 2,
};

class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            'Aún no hay recetas en el catálogo.',
            textAlign: TextAlign.center,
            style: AppText.nunito(16, 24, weight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Las que guardes aquí quedan en borrador o pendientes. Cuando el '
            'nutriólogo las aprueba, aparecen en la app de las familias.',
            textAlign: TextAlign.center,
            style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({required this.recipe, required this.onEdit});

  final Recipe recipe;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(recipe.name, style: AppText.baloo(18, 27)),
              ),
              const SizedBox(width: 8),
              _StatusBadge(recipe.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _summary(recipe),
            style: AppText.nunito(14, 21, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          Text(
            _ingredients(recipe),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.nunito(15, 22.5),
          ),
          if (recipe.status == RecipeStatus.draft && recipe.reviewNote != null) ...[
            const SizedBox(height: 8),
            InfoBanner(
              message: 'El nutriólogo la regresó: ${recipe.reviewNote}',
              background: AppColors.warningSoft,
              foreground: AppColors.warningText,
            ),
          ],
          const SizedBox(height: 12),
          // Una pendiente está en revisión: solo se ve, no se edita.
          SecondaryButton(
            label: recipe.status == RecipeStatus.pending ? 'Ver receta' : 'Editar',
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }

  /// "40 min · 4 porciones · 230 kcal por porción".
  static String _summary(Recipe recipe) {
    final servings = recipe.servings == 1 ? 'porción' : 'porciones';
    final parts = [
      '${recipe.prepTimeMinutes} min',
      '${recipe.servings} $servings',
      if (recipe.caloriesPerServing > 0)
        '${recipe.caloriesPerServing} kcal por porción',
    ];
    return parts.join(' · ');
  }

  /// "Lenteja 0.25 kg · Jitomate 500 g".
  static String _ingredients(Recipe recipe) {
    if (recipe.ingredients.isEmpty) return 'Sin ingredientes.';
    return [
      for (final ingredient in recipe.ingredients)
        '${ingredient.productName} ${_amount(ingredient)}',
    ].join(' · ');
  }

  static String _amount(RecipeIngredient ingredient) {
    final unit = FoodUnit.values
        .where((option) => option.name == ingredient.unit.trim().toLowerCase())
        .firstOrNull;
    return unit == null
        ? '${formatNumber(ingredient.quantity)} ${ingredient.unit}'
        : formatAmount(ingredient.quantity, unit);
  }
}

/// Borrador = solo Staff; pendiente = la revisa el nutriólogo; aprobada = la
/// ven las familias.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.status);

  final RecipeStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, background, foreground) = switch (status) {
      RecipeStatus.draft => (
        'Borrador',
        AppColors.background,
        AppColors.textMuted,
      ),
      RecipeStatus.pending => (
        'Pendiente de revisión',
        AppColors.warningSoft,
        AppColors.warningText,
      ),
      RecipeStatus.approved => (
        'Aprobada',
        AppColors.primarySoft,
        AppColors.primaryDark,
      ),
    };
    return Pill(
      label: label,
      background: background,
      foreground: foreground,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      fontSize: 13,
      lineHeight: 19.5,
    );
  }
}
