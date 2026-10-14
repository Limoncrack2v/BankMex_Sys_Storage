import 'package:flutter/material.dart';

import '../../../data/catalog_source.dart';
import '../../../data/models/family.dart';
import '../../../data/models/member.dart';
import '../../../data/models/pantry_item.dart';
import '../../../data/repositories/family_repository.dart';
import '../../../data/repositories/member_repository.dart';
import '../../../data/repositories/pantry_repository.dart';
import '../../../domain/meal_plan_length.dart';
import '../../formatting.dart';
import '../../models/recipe.dart';
import '../../sample_data.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_header.dart';
import '../../widgets/pill.dart';
import '../recipes/recipe_detail_screen.dart';

/// Plan de comidas semanal o quincenal, según la próxima entrega de la
/// familia (ver [MealPlanLength]): una receta por día, armado con la despensa
/// real de la familia y priorizando lo que caduca antes (ver [buildMealPlan]).
class MealPlanScreen extends StatefulWidget {
  const MealPlanScreen({
    super.key,
    required this.familyId,
    this.recipes = SampleData.recipes,
  });

  final String familyId;
  final List<Recipe> recipes;

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends State<MealPlanScreen> {
  late Stream<List<PantryItem>> _pantry;
  late Stream<List<Member>> _members;
  late Stream<List<Recipe>> _catalog;

  // El hogar trae nextDeliveryDate (lo escribe syncNextDelivery): al ser un
  // stream, el plan se alarga o se acorta en vivo si el staff programa o
  // cancela una entrega.
  late Stream<Family?> _family;

  @override
  void initState() {
    super.initState();
    _watch();
  }

  @override
  void didUpdateWidget(MealPlanScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.familyId != widget.familyId) _watch();
  }

  void _watch() {
    _pantry = PantryRepository().watchAllPantryItems(widget.familyId);
    _members = MemberRepository().watchAllMembers(widget.familyId);
    _catalog = watchApprovedCatalogRecipes();
    _family = FamilyRepository().watchFamily(widget.familyId);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AppHeader(title: 'Plan de comidas'),
        Expanded(
          // Mientras cargan los integrantes (o si fallan) se usan las
          // porciones originales de las recetas; mientras carga el hogar (o
          // si falla), el plan es semanal.
          child: StreamBuilder<List<Recipe>>(
            stream: _catalog,
            builder: (context, catalog) {
              final recipes =
                  catalog.hasData && catalog.data!.isNotEmpty
                      ? catalog.data!
                      : widget.recipes;
              return StreamBuilder<Family?>(
                stream: _family,
                builder: (context, family) => StreamBuilder<List<Member>>(
                  stream: _members,
                  builder: (context, members) =>
                      StreamBuilder<List<PantryItem>>(
                        stream: _pantry,
                        builder: (context, pantry) => _buildPlan(
                          context,
                          pantry,
                          members.hasError
                              ? const []
                              : members.data ?? const [],
                          recipes,
                          family.data?.nextDeliveryDate,
                        ),
                      ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPlan(
    BuildContext context,
    AsyncSnapshot<List<PantryItem>> snapshot,
    List<Member> members,
    List<Recipe> recipes,
    DateTime? nextDelivery,
  ) {
    if (snapshot.hasError) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [PantryErrorBanner()],
      );
    }
    final pantry = snapshot.data;
    if (pantry == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    final today = DateTime.now();
    // El plan se calcula con las porciones del hogar, pero el detalle recibe
    // la receta original (la ajusta él mismo).
    final originals = Map<Recipe, Recipe>.identity();
    for (final recipe in recipes) {
      originals[scaledForHousehold(recipe, members)] = recipe;
    }
    final plan = buildMealPlan(
      originals.keys.toList(),
      pantry,
      today: today,
      days: MealPlanLength.daysFor(nextDelivery: nextDelivery, now: today),
    );
    final hasProducts = pantry.any(
      (item) => item.quantity > 0 && daysLeft(item, today: today) >= 0,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        InfoBanner(
          message: hasProducts
              ? 'Tu plan usa primero lo que caduca antes'
              : 'Cuando tengas productos en tu despensa, tu plan se armará '
                    'con lo que caduca primero.',
          background: AppColors.primarySoft,
          foreground: AppColors.primaryDark,
        ),
        for (final entry in plan) ...[
          const SizedBox(height: 12),
          _DayCard(
            entry: entry,
            hasAllergens: allergyConflicts(entry.recipe, members).isNotEmpty,
            onTap: () => openRecipe(
              context,
              originals[entry.recipe] ?? entry.recipe,
              familyId: widget.familyId,
              backLabel: 'Volver al plan de comidas',
            ),
          ),
        ],
      ],
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.entry,
    required this.hasAllergens,
    required this.onTap,
  });

  final MealPlanEntry entry;

  /// Si la receta lleva algo a lo que un integrante es alérgico.
  final bool hasAllergens;
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
                // Día y número: en un plan de 14 días hay dos "LUN".
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.day.toUpperCase(),
                      style: AppText.nunito(
                        11,
                        16.5,
                        weight: FontWeight.w700,
                        color: AppColors.textMuted,
                      ),
                    ),
                    Text(
                      '${entry.date.day}',
                      style: AppText.baloo(16, 20, weight: FontWeight.w600),
                    ),
                  ],
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
              const SizedBox(width: 12),
              Pill(
                label: entry.urgency.label,
                background: entry.urgency.background,
                foreground: entry.urgency.foreground,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
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
