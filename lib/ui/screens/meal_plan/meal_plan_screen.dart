import 'package:flutter/material.dart';

import '../../../data/catalog_source.dart';
import '../../../data/models/family.dart';
import '../../../data/models/member.dart';
import '../../../data/models/pantry_item.dart';
import '../../../data/repositories/family_repository.dart';
import '../../../data/repositories/meal_plan_repository.dart';
import '../../../data/repositories/member_repository.dart';
import '../../../data/repositories/pantry_repository.dart';
import '../../../domain/meal_plan_edits.dart';
import '../../../domain/meal_plan_length.dart';
import '../../../domain/models/meal_plan.dart';
import '../../formatting.dart';
import '../../models/recipe.dart';
import '../../sample_data.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_header.dart';
import '../../widgets/pill.dart';
import '../recipes/recipe_detail_screen.dart';
import 'leftover_ingredients_section.dart';
import 'meal_plan_saving.dart';
import 'saved_meal_plan_view.dart';

/// Plan de comidas semanal o quincenal, según la próxima entrega de la
/// familia (ver [MealPlanLength]): una receta por día, armado con la despensa
/// real de la familia y priorizando lo que caduca antes (ver [buildMealPlan]).
///
/// Si la familia guardó un plan que abarca hoy se muestra ese
/// ([SavedPlanView]); si no, el plan sugerido, que se puede guardar
/// ([SuggestedPlanView]).
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

/// Los planes guardados de la familia y si cada uno tiene cambios sin
/// sincronizar.
typedef SavedPlans = List<({MealPlan plan, bool pendingSync})>;

class _MealPlanScreenState extends State<MealPlanScreen> {
  late Stream<List<PantryItem>> _pantry;
  late Stream<List<Member>> _members;
  late Stream<List<Recipe>> _catalog;

  // El hogar trae nextDeliveryDate (lo escribe syncNextDelivery): al ser un
  // stream, el plan se alarga o se acorta en vivo si el staff programa o
  // cancela una entrega.
  late Stream<Family?> _family;

  /// Los planes que guardó la familia.
  late Stream<SavedPlans> _plans;

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
    _plans = MealPlanRepository().watchByFamily(widget.familyId);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AppHeader(title: 'Plan de comidas'),
        Expanded(
          child: StreamBuilder<List<Recipe>>(
            stream: _catalog,
            builder: (context, catalog) => StreamBuilder<Family?>(
              stream: _family,
              builder: (context, family) => StreamBuilder<List<Member>>(
                stream: _members,
                builder: (context, members) => StreamBuilder<List<PantryItem>>(
                  stream: _pantry,
                  builder: (context, pantry) => StreamBuilder<SavedPlans>(
                    stream: _plans,
                    builder: (context, plans) => MealPlanView(
                      familyId: widget.familyId,
                      catalog: catalog,
                      family: family,
                      members: members,
                      pantry: pantry,
                      plans: plans,
                      sampleRecipes: widget.recipes,
                      onSave: MealPlanRepository().create,
                      onSaveMeals: MealPlanRepository().updateMeals,
                      onDelete: MealPlanRepository().delete,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

const _plansWarning =
    'No pudimos revisar si ya guardaste un plan. Revisa tu conexión e '
    'intenta de nuevo.';
const _membersWarning =
    'No pudimos revisar las alergias de tu familia. Revisa tu conexión e '
    'intenta de nuevo.';
const _familyWarning =
    'No pudimos cargar los datos de tu hogar. Revisa tu conexión e intenta '
    'de nuevo.';
const _catalogWarning =
    'No pudimos cargar las recetas de BAMX. Revisa tu conexión e intenta de '
    'nuevo.';

/// Si [snapshot] aún no trae datos ni un error (el hogar puede llegar null).
bool _loading(AsyncSnapshot<Object?> snapshot) =>
    !snapshot.hasData &&
    !snapshot.hasError &&
    snapshot.connectionState != ConnectionState.active &&
    snapshot.connectionState != ConnectionState.done;

/// Lo que muestra [MealPlanScreen] con lo que ya leyó de Firestore: el plan
/// guardado que abarca hoy o, si no hay, el sugerido.
class MealPlanView extends StatelessWidget {
  const MealPlanView({
    super.key,
    required this.familyId,
    required this.catalog,
    required this.family,
    required this.members,
    required this.pantry,
    required this.plans,
    required this.onSave,
    required this.onSaveMeals,
    required this.onDelete,
    this.sampleRecipes = SampleData.recipes,
    this.clock = DateTime.now,
  });

  final String familyId;

  /// Las recetas aprobadas del catálogo de BAMX.
  final AsyncSnapshot<List<Recipe>> catalog;
  final AsyncSnapshot<Family?> family;
  final AsyncSnapshot<List<Member>> members;
  final AsyncSnapshot<List<PantryItem>> pantry;
  final AsyncSnapshot<SavedPlans> plans;

  /// Guarda un plan nuevo.
  final Future<void> Function(MealPlan plan) onSave;

  /// Guarda las comidas de un plan después de cambiar un día.
  final Future<void> Function(MealPlan plan) onSaveMeals;

  /// Elimina el plan con ese id.
  final Future<void> Function(String planId) onDelete;

  /// Las que se muestran si el catálogo está vacío o no se pudo leer.
  final List<Recipe> sampleRecipes;
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context) {
    if (pantry.hasError) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [PantryErrorBanner()],
      );
    }
    final items = pantry.data;
    // Hasta tener todo no se muestra el plan: se podría guardar otro encima
    // del que ya hay, o uno con recetas o porciones de relleno.
    if (items == null || [catalog, family, members, plans].any(_loading)) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    final today = clock();
    void open(Recipe recipe) => openRecipe(
      context,
      recipe,
      familyId: familyId,
      backLabel: 'Volver al plan de comidas',
    );
    final approved = catalog.hasError
        ? const <Recipe>[]
        : catalog.data ?? const <Recipe>[];
    final recipes = approved.isEmpty ? sampleRecipes : approved;
    final household = members.hasError
        ? const <Member>[]
        : members.data ?? const <Member>[];
    final warnings = [
      if (members.hasError) _membersWarning,
      if (family.hasError) _familyWarning,
      if (catalog.hasError) _catalogWarning,
    ];
    // Un plan guardado apunta a recipes/{id}: las de ejemplo no se guardan.
    final canWrite = warnings.isEmpty && approved.isNotEmpty;

    final saved = plans.data ?? const [];
    final current = MealPlanEdits.current(
      saved.map((entry) => entry.plan),
      today,
    );
    if (current != null) {
      return SavedPlanView(
        plan: current,
        pendingSync: saved.any(
          (entry) => identical(entry.plan, current) && entry.pendingSync,
        ),
        recipes: recipes,
        members: household,
        pantry: items,
        today: today,
        warnings: warnings,
        catalogFailed: catalog.hasError,
        appliances: family.data?.appliances ?? const [],
        onOpenRecipe: open,
        onSaveMeals: canWrite ? onSaveMeals : null,
        onDelete: () => onDelete(current.id),
      );
    }
    return SuggestedPlanView(
      familyId: familyId,
      recipes: recipes,
      members: household,
      pantry: items,
      nextDelivery: family.data?.nextDeliveryDate,
      warnings: [if (plans.hasError) _plansWarning, ...warnings],
      onOpenRecipe: open,
      // Sin los planes guardados no se ofrece guardar: ya podría haber uno.
      onSave: canWrite && !plans.hasError ? onSave : null,
      clock: clock,
    );
  }
}

/// El plan que se arma con la despensa ([buildMealPlan]) y, arriba de los
/// días, "Guardar este plan" para que sus recetas ya no cambien.
class SuggestedPlanView extends StatefulWidget {
  const SuggestedPlanView({
    super.key,
    required this.familyId,
    required this.recipes,
    required this.members,
    required this.pantry,
    required this.nextDelivery,
    required this.onOpenRecipe,
    required this.onSave,
    this.warnings = const [],
    this.clock = DateTime.now,
  });

  final String familyId;

  /// Recetas originales, sin ajustar al hogar.
  final List<Recipe> recipes;
  final List<Member> members;
  final List<PantryItem> pantry;

  /// La próxima entrega del hogar: el plan es de 7 o 14 días
  /// ([MealPlanLength]).
  final DateTime? nextDelivery;

  /// Recibe la receta original: el detalle ajusta las porciones él mismo.
  final ValueChanged<Recipe> onOpenRecipe;

  /// Guarda el plan que se ve. Null si no se puede: [warnings] dice por qué
  /// o, sin avisos, las recetas no son del catálogo de BAMX.
  final Future<void> Function(MealPlan plan)? onSave;

  /// Lo que no se pudo leer; va arriba de los días.
  final List<String> warnings;

  /// Hoy. Se vuelve a leer al guardar: la pestaña pudo quedar abierta desde
  /// ayer.
  final DateTime Function() clock;

  @override
  State<SuggestedPlanView> createState() => _SuggestedPlanViewState();
}

class _SuggestedPlanViewState extends State<SuggestedPlanView> {
  bool _saving = false;

  /// Cada receta ajustada al hogar, con su original: el detalle recibe la
  /// original y ajusta las porciones él mismo.
  Map<Recipe, Recipe> _originals() {
    final originals = Map<Recipe, Recipe>.identity();
    for (final recipe in widget.recipes) {
      originals[scaledForHousehold(recipe, widget.members)] = recipe;
    }
    return originals;
  }

  int _daysFrom(DateTime today) =>
      MealPlanLength.daysFor(nextDelivery: widget.nextDelivery, now: today);

  List<MealPlanEntry> _planFrom(DateTime today, Iterable<Recipe> recipes) =>
      buildMealPlan(
        recipes.toList(),
        widget.pantry,
        today: today,
        days: _daysFrom(today),
      );

  Future<void> _save() async {
    final onSave = widget.onSave;
    if (_saving || onSave == null) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    final bool synced;
    try {
      final today = widget.clock();
      final plan = MealPlanEdits.create(
        familyId: widget.familyId,
        start: today,
        days: _daysFrom(today),
        meals: [
          for (final entry in _planFrom(today, _originals().keys))
            MealPlanMeal(
              date: entry.date,
              recipeId: entry.recipe.id,
              servings: planServings(widget.members, entry.recipe),
            ),
        ],
      );
      synced = await awaitPlanWrite(
        onSave(plan),
        onLateError: () => showPlanSnack(
          messenger,
          'No se pudo guardar tu plan. Revisa tu conexión e intenta de nuevo.',
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      showPlanSnack(
        messenger,
        planWriteError(e, 'No se pudo guardar tu plan. Intenta de nuevo.'),
      );
      return;
    }
    // En cuanto el plan queda en el dispositivo la pantalla cambia al plan
    // guardado, así que esta vista ya puede no estar.
    if (mounted) setState(() => _saving = false);
    showPlanSnack(messenger, withSyncNote('Plan guardado.', synced: synced));
  }

  @override
  Widget build(BuildContext context) {
    final today = widget.clock();
    final originals = _originals();
    final plan = _planFrom(today, originals.keys);
    final hasProducts = widget.pantry.any(
      (item) => item.quantity > 0 && daysLeft(item, today: today) >= 0,
    );
    final save = plan.isEmpty ? null : _buildSave(plan);

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
        for (final warning in widget.warnings) ...[
          const SizedBox(height: 12),
          InfoBanner(
            message: warning,
            background: AppColors.warningSoft,
            foreground: AppColors.warningText,
          ),
        ],
        // Guardar va arriba: un plan de 14 días es muy largo.
        if (save != null) ...[const SizedBox(height: 12), save],
        for (final entry in plan) ...[
          const SizedBox(height: 12),
          _DayCard(
            entry: entry,
            hasAllergens: allergyConflicts(
              entry.recipe,
              widget.members,
            ).isNotEmpty,
            onTap: () =>
                widget.onOpenRecipe(originals[entry.recipe] ?? entry.recipe),
          ),
        ],
        if (plan.isNotEmpty) ...[
          const SizedBox(height: 24),
          LeftoverIngredientsSection(
            leftovers: planLeftovers(plan, widget.pantry, today: today),
            today: today,
          ),
        ],
      ],
    );
  }

  /// "Guardar este plan", o por qué no se puede si [warnings] no lo dice.
  Widget? _buildSave(List<MealPlanEntry> plan) {
    final note = AppText.nunito(14, 21, color: AppColors.textMuted);
    // Un plan guardado apunta a recipes/{id}: sin id no se puede guardar.
    if (widget.onSave == null || plan.any((e) => e.recipe.id.isEmpty)) {
      if (widget.warnings.isNotEmpty) return null;
      return Text(
        'Para guardar tu plan hacen falta recetas del catálogo de BAMX.',
        style: note,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrimaryButton(
          label: 'Guardar este plan',
          icon: AppIcons.check,
          loading: _saving,
          onPressed: _save,
        ),
        const SizedBox(height: 8),
        Text(
          'Al guardarlo, las recetas de cada día ya no cambian y puedes '
          'cambiarlas tú.',
          textAlign: TextAlign.center,
          style: note,
        ),
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
                child: PillRow(
                  gap: 12,
                  leading: Column(
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
                  trailing: Pill(
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
