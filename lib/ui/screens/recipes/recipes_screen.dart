import 'package:flutter/material.dart';

import '../../../data/models/member.dart';
import '../../../data/models/pantry_item.dart';
import '../../../data/repositories/member_repository.dart';
import '../../../data/repositories/pantry_repository.dart';
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

  /// [missing] son los ingredientes que faltan en la despensa (null si aún no
  /// se conoce la despensa).
  bool matches(Recipe recipe, {required int? missing}) => switch (this) {
    RecipeFilter.todas => true,
    RecipeFilter.conLoQueTengo => missing == 0,
    RecipeFilter.rapidas => recipe.isQuick,
  };
}

class RecipesScreen extends StatefulWidget {
  const RecipesScreen({
    super.key,
    required this.familyId,
    this.recipes = SampleData.recipes,
  });

  final String familyId;
  final List<Recipe> recipes;

  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends State<RecipesScreen> {
  RecipeFilter _filter = RecipeFilter.conLoQueTengo;
  late Stream<List<PantryItem>> _pantry;
  late Stream<List<Member>> _members;

  @override
  void initState() {
    super.initState();
    _watch();
  }

  @override
  void didUpdateWidget(RecipesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.familyId != widget.familyId) _watch();
  }

  void _watch() {
    _pantry = PantryRepository().watchAllPantryItems(widget.familyId);
    _members = MemberRepository().watchAllMembers(widget.familyId);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AppHeader(title: 'Recetas'),
        Expanded(
          // Mientras cargan los integrantes (o si fallan) las recetas se
          // muestran con sus porciones originales y sin revisar alergias.
          child: StreamBuilder<List<Member>>(
            stream: _members,
            builder: (context, members) => StreamBuilder<List<PantryItem>>(
              stream: _pantry,
              builder: (context, pantry) => _buildList(
                context,
                pantry,
                members.hasError ? const [] : members.data ?? const [],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildList(
    BuildContext context,
    AsyncSnapshot<List<PantryItem>> snapshot,
    List<Member> members,
  ) {
    final pantry = snapshot.hasError ? null : snapshot.data;
    final loading = pantry == null && !snapshot.hasError;
    // "Con lo que tengo" no se puede calcular sin la despensa.
    final needsPantry = _filter == RecipeFilter.conLoQueTengo && pantry == null;

    final visible = <_VisibleRecipe>[];
    if (!needsPantry) {
      for (final recipe in widget.recipes) {
        // Porciones para el número de integrantes del hogar.
        final scaled = scaledRecipe(recipe, members.length);
        final missing = pantry == null
            ? null
            : _missingIngredients(scaled, pantry);
        if (_filter.matches(scaled, missing: missing)) {
          visible.add((
            recipe: recipe,
            scaled: scaled,
            missing: missing,
            hasAllergens: allergyConflicts(recipe, members).isNotEmpty,
          ));
        }
      }
    }

    return ListView(
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
        if (snapshot.hasError) ...[
          const SizedBox(height: 12),
          const PantryErrorBanner(),
        ],
        if (loading && needsPantry)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          )
        else if (visible.isEmpty && !needsPantry)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(
              'No hay recetas con este filtro.',
              textAlign: TextAlign.center,
              style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
            ),
          ),
        for (final (:recipe, :scaled, :missing, :hasAllergens) in visible) ...[
          const SizedBox(height: 12),
          _RecipeCard(
            recipe: scaled,
            missing: missing,
            hasAllergens: hasAllergens,
            // El detalle vuelve a ajustar las porciones desde la receta
            // original.
            onTap: () => openRecipe(
              context,
              recipe,
              familyId: widget.familyId,
              backLabel: 'Volver a recetas',
            ),
          ),
        ],
      ],
    );
  }
}

typedef _VisibleRecipe = ({
  Recipe recipe,
  Recipe scaled,
  int? missing,
  bool hasAllergens,
});

int _missingIngredients(Recipe recipe, List<PantryItem> pantry) =>
    checkAvailability(recipe, pantry).where((a) => !a.available).length;

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
  const _RecipeCard({
    required this.recipe,
    required this.missing,
    required this.hasAllergens,
    required this.onTap,
  });

  /// Receta con las porciones del hogar.
  final Recipe recipe;

  /// Ingredientes que faltan; null mientras carga la despensa (sin badge).
  final int? missing;

  /// Si lleva algo a lo que un integrante es alérgico.
  final bool hasAllergens;
  final VoidCallback onTap;

  static const _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(16)),
    side: BorderSide(color: AppColors.border),
  );

  @override
  Widget build(BuildContext context) {
    final missing = this.missing;

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
                  if (missing != null || hasAllergens) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (missing == 0)
                          const Pill.success(
                            label: 'Tienes todos los ingredientes',
                          )
                        else if (missing != null)
                          Pill(
                            label: missing == 1
                                ? 'Te falta 1 ingrediente'
                                : 'Te faltan $missing ingredientes',
                            background: AppColors.warningSoft,
                            foreground: AppColors.warningText,
                          ),
                        if (hasAllergens)
                          const Pill(
                            label: 'Contiene alérgenos de tu familia',
                            background: AppColors.dangerSoft,
                            foreground: AppColors.dangerText,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
