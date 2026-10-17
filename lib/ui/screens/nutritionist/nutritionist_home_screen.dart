import 'dart:async';

import 'package:flutter/material.dart';

import '../../../application/bank_storage_facade.dart';
import '../../../data/models/pantry_item.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/recipe_repository.dart';
import '../../../domain/models/recipe.dart';
import '../../../domain/recipe_catalog.dart';
import '../../formatting.dart';
import '../../session_navigation.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/pill.dart';
import '../session/step_up_sheet.dart';

/// Pantalla del nutriólogo: las recetas pendientes que Staff dejó para
/// revisión. Aprobar una la publica para las familias; rechazarla la regresa a
/// borrador con el motivo, que Staff ve. Las dos acciones piden una sesión
/// reciente (firestore.rules: recentlySignedIn) y son lo único que escribe.
/// No muestra nada de ninguna familia.
///
/// Los parámetros opcionales son para las pruebas: por omisión lee Firestore,
/// aprueba y rechaza con [BankStorageFacade] y confirma con la contraseña.
class NutritionistHomeScreen extends StatefulWidget {
  const NutritionistHomeScreen({
    super.key,
    required this.session,
    this.pendingRecipes,
    this.approveRecipe,
    this.rejectRecipe,
    this.confirmIdentity,
  });

  final AuthSession session;
  final Stream<List<Recipe>>? pendingRecipes;
  final Future<void> Function(String recipeId)? approveRecipe;
  final Future<void> Function(String recipeId, String note)? rejectRecipe;
  final Future<bool> Function(BuildContext context)? confirmIdentity;

  @override
  State<NutritionistHomeScreen> createState() => _NutritionistHomeScreenState();
}

class _NutritionistHomeScreenState extends State<NutritionistHomeScreen> {
  late final Stream<List<Recipe>> _pending;
  String? _working;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    // Solo las pendientes: el nutriólogo no lee las demás (firestore.rules).
    _pending =
        widget.pendingRecipes ??
        RecipeRepository().watchByStatus(RecipeStatus.pending);
  }

  String get _reviewer => widget.session.user.userId;

  Future<void> _approve(Recipe recipe) async {
    if (_working != null) return;
    final confirm = widget.confirmIdentity ?? ensureRecentSignIn;
    if (!await confirm(context) || !mounted) return;
    await _run(
      recipe,
      () =>
          (widget.approveRecipe ??
          (id) async {
            await BankStorageFacade().approveRecipe(id, reviewerUid: _reviewer);
          })(recipe.id),
      done: '«${recipe.name}» aprobada. Las familias ya la ven.',
      offline: '«${recipe.name}» se aprobará cuando vuelva la conexión.',
      failed: 'No se pudo aprobar «${recipe.name}». Intenta de nuevo.',
    );
  }

  Future<void> _reject(Recipe recipe) async {
    if (_working != null) return;
    final note = await showAppBottomSheet<String>(
      context,
      enableDrag: false,
      builder: (_) => _RejectSheet(recipeName: recipe.name),
    );
    if (note == null || !mounted) return;
    final confirm = widget.confirmIdentity ?? ensureRecentSignIn;
    if (!await confirm(context) || !mounted) return;
    await _run(
      recipe,
      () =>
          (widget.rejectRecipe ??
          (id, note) async {
            await BankStorageFacade().rejectRecipe(
              id,
              reviewerUid: _reviewer,
              note: note,
            );
          })(recipe.id, note),
      done: '«${recipe.name}» regresó a borrador con tu motivo.',
      offline: '«${recipe.name}» se rechazará cuando vuelva la conexión.',
      failed: 'No se pudo rechazar «${recipe.name}». Intenta de nuevo.',
    );
  }

  Future<void> _run(
    Recipe recipe,
    Future<void> Function() action, {
    required String done,
    required String offline,
    required String failed,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _working = recipe.id);
    String message;
    try {
      // Sin conexión Firestore deja la escritura en cola y el Future no
      // termina hasta que llega al servidor.
      await action().timeout(const Duration(seconds: 8));
      message = done;
    } on TimeoutException {
      message = offline;
    } catch (_) {
      message = failed;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    if (mounted) setState(() => _working = null);
  }

  /// signOutAndReturnToSignIn navega primero y cierra la sesión después. La
  /// bandera evita un segundo toque durante la transición.
  Future<void> _signOut() async {
    if (_signingOut) return;
    _signingOut = true;
    await signOutAndReturnToSignIn(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          AppHeader(title: 'BAMX Guadalajara', horizontalPadding: 24),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(widget.session.user.name, style: AppText.baloo(20, 30)),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Pill.success(label: 'Nutriólogo', withIcon: false),
                ),
                const SizedBox(height: 24),
                Text('Recetas por revisar', style: AppText.baloo(18, 27)),
                const SizedBox(height: 4),
                Text(
                  'Cuando apruebas una receta, las familias ya pueden verla. '
                  'Si la rechazas, regresa a borrador con tu motivo.',
                  style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                StreamBuilder<List<Recipe>>(
                  stream: _pending,
                  builder: _buildRecipes,
                ),
                const SizedBox(height: 24),
                Center(
                  child: TextLinkButton(
                    label: 'Cerrar sesión',
                    onPressed: _signOut,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecipes(
    BuildContext context,
    AsyncSnapshot<List<Recipe>> snapshot,
  ) {
    if (snapshot.hasError) {
      return const InfoBanner(
        message:
            'No se pudieron cargar las recetas por revisar. Revisa tu '
            'conexión e intenta de nuevo.',
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
    if (recipes.isEmpty) {
      return Text(
        'No hay recetas por revisar.',
        textAlign: TextAlign.center,
        style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
      );
    }
    final sorted = [...recipes]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, recipe) in sorted.indexed) ...[
          if (index > 0) const SizedBox(height: 12),
          _PendingRecipeCard(
            recipe: recipe,
            working: _working == recipe.id,
            enabled: _working == null,
            onApprove: () => _approve(recipe),
            onReject: () => _reject(recipe),
          ),
        ],
      ],
    );
  }
}

class _PendingRecipeCard extends StatelessWidget {
  const _PendingRecipeCard({
    required this.recipe,
    required this.working,
    required this.enabled,
    required this.onApprove,
    required this.onReject,
  });

  final Recipe recipe;
  final bool working;
  final bool enabled;
  final VoidCallback onApprove;
  final VoidCallback onReject;

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
          Text(recipe.name, style: AppText.baloo(18, 27)),
          const SizedBox(height: 4),
          Text(
            _summary(recipe),
            style: AppText.nunito(14, 21, color: AppColors.textMuted),
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              // ExpansionTile centra sus hijos si no se le dice otra cosa;
              // expandedCrossAxisAlignment solo los alinea entre sí.
              expandedAlignment: Alignment.centerLeft,
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              title: Text(
                'Ver ingredientes y pasos',
                style: AppText.nunito(15, 22.5, weight: FontWeight.w700),
              ),
              children: [
                for (final ingredient in recipe.ingredients)
                  Text(
                    '• ${ingredient.productName} ${_amount(ingredient)}',
                    style: AppText.nunito(15, 22.5),
                  ),
                const SizedBox(height: 8),
                for (final (index, step) in recipe.steps.indexed)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${index + 1}. $step',
                      style: AppText.nunito(15, 22.5),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          PrimaryButton(
            label: 'Aprobar receta',
            icon: AppIcons.check,
            loading: working,
            onPressed: enabled ? onApprove : null,
          ),
          const SizedBox(height: 8),
          SecondaryButton(
            label: 'Rechazar con motivo',
            onPressed: enabled ? onReject : null,
          ),
        ],
      ),
    );
  }

  /// "40 min · 4 porciones · 230 kcal por porción".
  static String _summary(Recipe recipe) {
    final servings = recipe.servings == 1 ? 'porción' : 'porciones';
    return [
      '${recipe.prepTimeMinutes} min',
      '${recipe.servings} $servings',
      if (recipe.caloriesPerServing > 0)
        '${recipe.caloriesPerServing} kcal por porción',
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

/// Pide el motivo del rechazo, obligatorio, y lo regresa sin espacios de más.
class _RejectSheet extends StatefulWidget {
  const _RejectSheet({required this.recipeName});

  final String recipeName;

  @override
  State<_RejectSheet> createState() => _RejectSheetState();
}

class _RejectSheetState extends State<_RejectSheet> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _valid => RecipeCatalog.validateReviewNote(_note.text) == null;

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: 'Rechazar receta',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '«${widget.recipeName}» regresa a borrador. Staff verá tu motivo '
            'para corregirla.',
            style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _note,
            hint: 'Ej. Falta la cantidad de sal.',
            textCapitalization: TextCapitalization.sentences,
            minLines: 3,
            maxLines: 5,
            maxLength: Recipe.maxReviewNoteLength,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      footer: PrimaryButton(
        label: 'Rechazar receta',
        onPressed: _valid
            ? () => Navigator.of(context).pop(_note.text.trim())
            : null,
      ),
    );
  }
}
