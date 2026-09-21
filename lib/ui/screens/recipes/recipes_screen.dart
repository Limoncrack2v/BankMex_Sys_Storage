import 'package:flutter/material.dart';

import '../../models/recipe.dart';
import '../../sample_data.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/pill.dart';
import 'recipe_detail_screen.dart';

enum RecipeFilter {
  todas('Todas', 'Todas las recetas de nutriólogos de BAMX'),
  conLoQueTengo('Con lo que tengo', 'Recetas con lo que hay en tu despensa'),
  rapidas('Rápidas', 'Recetas de 30 minutos o menos');

  const RecipeFilter(this.label, this.description);

  final String label;
  final String description;

  bool matches(Recipe recipe) => switch (this) {
    RecipeFilter.todas => true,
    RecipeFilter.conLoQueTengo => recipe.hasAllIngredients,
    RecipeFilter.rapidas => recipe.isQuick,
  };
}

class RecipesScreen extends StatefulWidget {
  const RecipesScreen({super.key, this.recipes = SampleData.recipes});

  final List<Recipe> recipes;

  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends State<RecipesScreen> {
  RecipeFilter _filter = RecipeFilter.conLoQueTengo;

  @override
  Widget build(BuildContext context) {
    final visible = widget.recipes.where(_filter.matches).toList();

    return Column(
      children: [
        const AppHeader(title: 'Recetas'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _FilterBar(
                selected: _filter,
                onSelected: (filter) => setState(() => _filter = filter),
              ),
              const SizedBox(height: 12),
              Text(
                _filter.description,
                style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
              ),
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(
                    'No hay recetas con este filtro.',
                    textAlign: TextAlign.center,
                    style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
                  ),
                ),
              for (final recipe in visible) ...[
                const SizedBox(height: 12),
                _RecipeCard(
                  recipe: recipe,
                  onTap: () =>
                      openRecipe(context, recipe, backLabel: 'Volver a recetas'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelected});

  final RecipeFilter selected;
  final ValueChanged<RecipeFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          const AppIcon(AppIcons.filter, size: 20),
          for (final filter in RecipeFilter.values) ...[
            const SizedBox(width: 8),
            _FilterChip(
              label: filter.label,
              selected: filter == selected,
              onTap: () => onSelected(filter),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = StadiumBorder(
      side: BorderSide(
        color: selected ? AppColors.primary : AppColors.border,
        width: 2,
      ),
    );

    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? AppColors.primary : AppColors.surface,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            child: Text(
              label,
              style: AppText.nunito(
                15,
                22.5,
                weight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({required this.recipe, required this.onTap});

  final Recipe recipe;
  final VoidCallback onTap;

  static const _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(16)),
    side: BorderSide(color: AppColors.border),
  );

  @override
  Widget build(BuildContext context) {
    final missing = recipe.ingredients.length - recipe.availableIngredients;

    return Material(
      color: AppColors.surface,
      shape: _shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 244,
              child: ColoredBox(
                color: AppColors.primarySoft,
                child: Image.asset(recipe.image, fit: BoxFit.cover),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipe.name,
                    style: AppText.baloo(19, 23.75, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  RecipeMeta(recipe),
                  const SizedBox(height: 8),
                  if (missing == 0)
                    const Pill.success(label: 'Tienes todos los ingredientes')
                  else
                    Pill(
                      label: missing == 1
                          ? 'Te falta 1 ingrediente'
                          : 'Te faltan $missing ingredientes',
                      background: AppColors.warningSoft,
                      foreground: AppColors.warningText,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
