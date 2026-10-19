import 'package:flutter/material.dart';

import '../../../data/models/member.dart';
import '../../../domain/exclusion_list.dart';
import '../../../domain/models/recipe.dart';
import '../../../domain/models/recipe_adjustment.dart';
import '../../../domain/recipe_adjustment.dart';
import '../../formatting.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/pill.dart';
import 'adjustment_review_screen.dart';

/// Por qué la familia nunca vería una adaptación aunque se aprobara. Una
/// adaptación se decide una sola vez y el nutriólogo no la puede borrar, así
/// que estas no se aprueban: solo se rechazan.
enum AdjustmentStaleness {
  /// La receta se editó después de la sugerencia.
  changed,

  /// La receta ya no está publicada: está en borrador o en revisión, o se
  /// borró.
  unavailable,

  /// Un ingrediente de la adaptación lleva un alérgeno del hogar.
  unsafe,
}

/// Una adaptación pendiente con lo que hace falta para revisarla: la receta
/// publicada de la que salió y las alergias del hogar. No muestra nada que
/// identifique a la familia.
class AdjustmentQueueItem {
  factory AdjustmentQueueItem(RecipeAdjustment adjustment, Recipe? recipe) {
    final allergies = allergiesOfHouseholdKey(adjustment.householdKey);
    // La misma regla de alérgenos con la que la familia descarta una
    // adaptación aprobada (applyAdjustments).
    final allergen = adjustment.ingredients
        .where(
          (ingredient) => allergies.any(
            (allergy) => containsAllergen(ingredient.productName, allergy),
          ),
        )
        .firstOrNull
        ?.productName;
    final sameVersion =
        recipe != null && recipeSignature(recipe) == adjustment.baseSignature;
    return AdjustmentQueueItem._(
      adjustment: adjustment,
      recipe: recipe,
      allergies: allergies,
      allergenIngredient: allergen,
      sameVersion: sameVersion,
      staleness: recipe == null
          ? AdjustmentStaleness.unavailable
          : !sameVersion
          ? AdjustmentStaleness.changed
          : allergen != null
          ? AdjustmentStaleness.unsafe
          : null,
    );
  }

  const AdjustmentQueueItem._({
    required this.adjustment,
    required this.recipe,
    required this.allergies,
    required this.allergenIngredient,
    required this.sameVersion,
    required this.staleness,
  });

  final RecipeAdjustment adjustment;

  /// La receta publicada; null si ya no lo está.
  final Recipe? recipe;

  /// Las alergias del hogar, leídas de su clave.
  final List<Allergy> allergies;

  /// El primer ingrediente de la adaptación con un alérgeno del hogar.
  final String? allergenIngredient;

  /// Si [recipe] es la misma versión de la que salió la sugerencia.
  final bool sameVersion;

  /// null si se puede aprobar.
  final AdjustmentStaleness? staleness;

  /// El nombre de la receta para los títulos.
  String get title => recipe?.name ?? 'Receta no disponible';

  /// El nombre de la receta para los mensajes: «Avena con fruta», o "esta
  /// receta" si ya no está publicada.
  String get quotedName {
    final recipe = this.recipe;
    return recipe == null ? 'esta receta' : '«${recipe.name}»';
  }

  /// "4 integrantes", "1 integrante".
  String get householdMembers {
    final size = adjustment.householdSize;
    return size == 1 ? '1 integrante' : '$size integrantes';
  }

  /// "Alergias: Lácteos, Gluten" o "Sin alergias".
  String get allergiesLabel => allergies.isEmpty
      ? 'Sin alergias'
      : 'Alergias: ${allergies.map(allergyLabel).join(', ')}';

  /// "Porciones: 2 → 3", o "Porciones: 3" si no se sabe cuántas daba la
  /// receta de la que salió la sugerencia (ya no está publicada o cambió).
  String get portionsLabel {
    final servings = adjustment.servings;
    return sameVersion
        ? 'Porciones: ${recipe!.servings} → $servings'
        : 'Porciones: $servings';
  }

  /// Un cambio en pocas palabras: [portionsLabel] o "Leche entera → Bebida
  /// de avena".
  String changeTitle(AdjustmentChange change) {
    if (change.kind == AdjustmentChange.kindPortions) return portionsLabel;
    final from = change.from;
    final to = change.to;
    if (from != null && to != null) return '$from → $to';
    return to ?? from ?? change.reason;
  }

  /// Todo lo que cambia, en una línea. Sale de los datos y no del resumen,
  /// que está escrito para la familia ("tu hogar").
  String get changesLine => adjustment.changes.map(changeTitle).join(' · ');
}

/// Las adaptaciones de [pending] con su receta de [approved], la más vieja
/// primero; las que todavía no tienen la hora del servidor van al final.
/// Se ordenan aquí para no necesitar un índice compuesto (status +
/// createdAt).
List<AdjustmentQueueItem> adjustmentQueue(
  List<RecipeAdjustment> pending,
  List<Recipe> approved,
) {
  final recipes = {for (final recipe in approved) recipe.id: recipe};
  int byAge(AdjustmentQueueItem a, AdjustmentQueueItem b) {
    final first = a.adjustment.createdAt;
    final second = b.adjustment.createdAt;
    if (first != null && second != null) {
      final order = first.compareTo(second);
      if (order != 0) return order;
    } else if (first != null) {
      return -1;
    } else if (second != null) {
      return 1;
    }
    return a.adjustment.id.compareTo(b.adjustment.id);
  }

  return [
    for (final adjustment in pending)
      AdjustmentQueueItem(adjustment, recipes[adjustment.recipeId]),
  ]..sort(byAge);
}

/// La sección "Adaptaciones por revisar" del inicio del nutriólogo: las
/// adaptaciones pendientes de todas las familias, sin nombres ni ids. Cada
/// tarjeta abre su revisión.
class AdjustmentQueue extends StatelessWidget {
  const AdjustmentQueue({
    super.key,
    required this.adjustments,
    required this.approvedRecipes,
    required this.reviewerUid,
    this.approveAdjustment,
    this.rejectAdjustment,
    this.confirmIdentity,
  });

  /// Las adaptaciones pendientes (AdjustmentRepository.watchPending).
  final Stream<List<RecipeAdjustment>> adjustments;

  /// Las recetas publicadas, para el nombre y la versión de cada una.
  final Stream<List<Recipe>> approvedRecipes;

  /// El uid del nutriólogo, que firma cada decisión.
  final String reviewerUid;

  /// Para las pruebas: por omisión se decide con BankStorageFacade y se
  /// confirma con la contraseña (ensureRecentSignIn).
  final Future<void> Function(String adjustmentId)? approveAdjustment;
  final Future<void> Function(String adjustmentId, String reason)?
  rejectAdjustment;
  final Future<bool> Function(BuildContext context)? confirmIdentity;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Adaptaciones por revisar', style: AppText.baloo(18, 27)),
        const SizedBox(height: 4),
        Text(
          'La app sugiere cómo adaptar una receta publicada a un hogar: las '
          'porciones y los ingredientes que cambian por alergia. La familia ve '
          'la receta original hasta que apruebes la adaptación.',
          style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),
        StreamBuilder<List<RecipeAdjustment>>(
          stream: adjustments,
          builder: (_, pending) => StreamBuilder<List<Recipe>>(
            stream: approvedRecipes,
            // Se abre con el context de la sección y no con el de la
            // tarjeta: la tarjeta desaparece en cuanto se decide.
            builder: (_, recipes) => _buildList(context, pending, recipes),
          ),
        ),
      ],
    );
  }

  Widget _buildList(
    BuildContext context,
    AsyncSnapshot<List<RecipeAdjustment>> pending,
    AsyncSnapshot<List<Recipe>> recipes,
  ) {
    const error = InfoBanner(
      message:
          'No se pudieron cargar las adaptaciones. Revisa tu conexión e '
          'intenta de nuevo.',
      background: AppColors.dangerSoft,
      foreground: AppColors.dangerText,
    );
    if (pending.hasError) return error;
    final adjustments = pending.data;
    // Sin adaptaciones no hace falta esperar a las recetas.
    if (adjustments != null && adjustments.isEmpty) {
      return Text(
        'No hay adaptaciones por revisar.',
        textAlign: TextAlign.center,
        style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
      );
    }
    // Sin las recetas no se sabe cuáles siguen publicadas: no se marcan
    // todas como "no disponible".
    if (recipes.hasError) return error;
    final approved = recipes.data;
    if (adjustments == null || approved == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            semanticsLabel: 'Cargando adaptaciones',
          ),
        ),
      );
    }
    final items = adjustmentQueue(adjustments, approved);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, item) in items.indexed) ...[
          if (index > 0) const SizedBox(height: 12),
          _AdjustmentCard(
            item: item,
            onTap: () => openAdjustmentReview(context, item: item),
          ),
        ],
      ],
    );
  }
}

class _AdjustmentCard extends StatelessWidget {
  const _AdjustmentCard({required this.item, required this.onTap});

  final AdjustmentQueueItem item;
  final VoidCallback onTap;

  static const _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(16)),
    side: BorderSide(color: AppColors.border),
  );

  @override
  Widget build(BuildContext context) {
    final muted = AppText.nunito(15, 22.5, color: AppColors.textMuted);
    final name = Text(item.title, style: AppText.baloo(18, 27));
    final staleness = item.staleness;

    return Semantics(
      container: true,
      button: true,
      label:
          'Revisar la adaptación de ${item.recipe?.name ?? 'esta receta'} '
          'para un hogar de ${item.householdMembers}',
      child: Material(
        color: AppColors.surface,
        shape: _shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (staleness == null)
                  name
                else
                  PillRow(
                    leading: name,
                    trailing: Pill(
                      label: switch (staleness) {
                        AdjustmentStaleness.changed => 'La receta cambió',
                        AdjustmentStaleness.unavailable =>
                          'Receta no disponible',
                        AdjustmentStaleness.unsafe => 'Lleva un alérgeno',
                      },
                      background: AppColors.warningSoft,
                      foreground: AppColors.warningText,
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  'Hogar de ${item.householdMembers} · ${item.allergiesLabel}',
                  style: muted,
                ),
                const SizedBox(height: 6),
                Text(item.changesLine, style: muted),
                const SizedBox(height: 8),
                // La etiqueta de la tarjeta ya dice "Revisar".
                ExcludeSemantics(
                  child: Text(
                    'Revisar',
                    textAlign: TextAlign.end,
                    style: AppText.nunito(
                      15,
                      22.5,
                      weight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
