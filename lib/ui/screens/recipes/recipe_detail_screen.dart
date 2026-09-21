import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/models/member.dart';
import '../../../data/models/pantry_item.dart';
import '../../../data/repositories/member_repository.dart';
import '../../../data/repositories/pantry_repository.dart';
import '../../models/recipe.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/pill.dart';

/// Sin conexión la escritura queda guardada en el dispositivo y Firestore la
/// sincroniza después, así que no se espera al servidor indefinidamente.
const _saveTimeout = Duration(seconds: 4);
const _pendingSyncNote = 'Se sincronizará cuando haya conexión.';

/// Resultado de "Marcar como completada": cuántos productos se descontaron y
/// si el servidor ya lo confirmó.
typedef _Completed = ({int updated, bool synced});

/// Abre el detalle de una receta y, si se marca como completada, muestra la
/// confirmación de consumo registrado. [recipe] es la receta original: el
/// detalle ajusta las porciones al número de integrantes.
Future<void> openRecipe(
  BuildContext context,
  Recipe recipe, {
  required String familyId,
  required String backLabel,
}) async {
  final result = await Navigator.of(context).push<_Completed>(
    MaterialPageRoute(
      builder: (_) => RecipeDetailScreen(
        recipe: recipe,
        familyId: familyId,
        backLabel: backLabel,
      ),
    ),
  );
  if (result == null || !context.mounted) return;

  final (:updated, :synced) = result;
  final message =
      'Se actualizó tu despensa con el consumo de $updated '
      '${updated == 1 ? 'producto' : 'productos'}.';
  await showSuccessSheet(
    context,
    title: 'Registrar consumo',
    heading: 'Consumo registrado',
    message: synced ? message : '$message $_pendingSyncNote',
  );
}

/// Detalle de receta con las porciones ajustadas al hogar y aviso de
/// alergias. Al marcarla como completada descuenta sus ingredientes de la
/// despensa y cierra la pantalla regresando cuántos productos cambiaron.
class RecipeDetailScreen extends StatefulWidget {
  const RecipeDetailScreen({
    super.key,
    required this.recipe,
    required this.familyId,
    required this.backLabel,
  });

  /// Receta original (sin ajustar).
  final Recipe recipe;
  final String familyId;
  final String backLabel;

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  StreamSubscription<List<PantryItem>>? _pantrySubscription;
  StreamSubscription<List<Member>>? _membersSubscription;
  List<PantryItem>? _pantry;
  bool _pantryFailed = false;

  /// null mientras cargan o si no se pudieron leer.
  List<Member>? _members;
  bool _membersFailed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _pantrySubscription = PantryRepository()
        .watchAllPantryItems(widget.familyId)
        .listen(
          (items) => setState(() {
            _pantry = items;
            _pantryFailed = false;
          }),
          onError: (Object _) => setState(() {
            _pantry = null;
            _pantryFailed = true;
          }),
        );
    _membersSubscription = MemberRepository()
        .watchAllMembers(widget.familyId)
        .listen(
          (members) => setState(() {
            _members = members;
            _membersFailed = false;
          }),
          onError: (Object _) => setState(() {
            _members = null;
            _membersFailed = true;
          }),
        );
  }

  @override
  void dispose() {
    _pantrySubscription?.cancel();
    _membersSubscription?.cancel();
    super.dispose();
  }

  /// La receta con porciones para los integrantes del hogar (la original
  /// mientras no se conocen o si no hay ninguno registrado).
  Recipe get _recipe => scaledRecipe(widget.recipe, _members?.length ?? 0);

  Future<void> _complete() async {
    final pantry = _pantry;
    if (pantry == null || _saving) return;

    final messenger = ScaffoldMessenger.of(context);
    final plan = planConsumption(_recipe, pantry);
    if (plan.isEmpty) {
      _showSnack(
        messenger,
        'Ninguno de estos ingredientes está en tu despensa.',
      );
      return;
    }

    setState(() => _saving = true);
    final bool synced;
    try {
      synced = await _awaitSave(
        PantryRepository().registerConsumption(widget.familyId, plan),
        onLateError: () => _showSnack(
          messenger,
          'No se pudo registrar el consumo. Revisa tu despensa e intenta de '
          'nuevo.',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showSnack(
        messenger,
        'No se pudo registrar el consumo. Intenta de nuevo.',
      );
      return;
    }
    if (!mounted) return;
    // planConsumption solo incluye cantidades mayores a 0, así que son los
    // mismos productos que registerConsumption actualiza.
    Navigator.of(context)
        .pop<_Completed>((updated: plan.length, synced: synced));
  }

  @override
  Widget build(BuildContext context) {
    final members = _members;
    final size = members?.length ?? 0;
    final recipe = _recipe;
    final pantry = _pantry;
    final availability = pantry == null
        ? null
        : checkAvailability(recipe, pantry);
    final conflicts = allergyConflicts(recipe, members ?? const []);

    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            _Header(backLabel: widget.backLabel),
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
                        if (size > 0) ...[
                          const SizedBox(height: 8),
                          const Pill.success(
                            label: 'Adaptado al tamaño de tu hogar',
                          ),
                        ],
                        const SizedBox(height: 8),
                        RecipeMeta(recipe),
                        const SizedBox(height: 4),
                        Text(
                          _description(members),
                          style: AppText.nunito(
                            14,
                            21,
                            color: AppColors.textMuted,
                          ),
                        ),
                        if (conflicts.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          InfoBanner(
                            message: conflicts.map(allergyWarning).join('\n'),
                            background: AppColors.dangerSoft,
                            foreground: AppColors.dangerText,
                          ),
                        ] else if (_membersFailed) ...[
                          const SizedBox(height: 16),
                          const InfoBanner(
                            message:
                                'No pudimos revisar las alergias de tu '
                                'familia. Revisa tu conexión e intenta de '
                                'nuevo.',
                            background: AppColors.warningSoft,
                            foreground: AppColors.warningText,
                          ),
                        ],
                        const SizedBox(height: 20),
                        const _SectionTitle('Ingredientes'),
                        const SizedBox(height: 8),
                        if (_pantryFailed)
                          const PantryErrorBanner()
                        else if (availability == null)
                          const _PantryLoading()
                        else
                          _AvailabilityPill(availability),
                        const SizedBox(height: 4),
                        for (var i = 0; i < recipe.ingredients.length; i++) ...[
                          const SizedBox(height: 8),
                          _IngredientRow(
                            recipe.ingredients[i],
                            available: availability?[i].available ?? false,
                          ),
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
                          loading: _saving,
                          // Se espera a los integrantes para descontar las
                          // porciones del hogar y no las de la receta base.
                          onPressed:
                              pantry == null ||
                                  (members == null && !_membersFailed)
                              ? null
                              : _complete,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Solo dice que las porciones se ajustaron cuando de verdad se ajustaron.
  static String _description(List<Member>? members) {
    const intro = 'Receta de nutriólogos de BAMX.';
    if (members == null) return intro;
    final size = members.length;
    if (size == 0) {
      return '$intro Registra a los integrantes de tu hogar en Perfil para '
          'ajustar las porciones.';
    }
    final count = size == 1 ? '1 integrante' : '$size integrantes';
    return '$intro Ajustamos las porciones a tu hogar ($count).';
  }
}

/// Espera a que el servidor confirme [save]. Sin conexión el Future no
/// termina hasta sincronizar: después de [_saveTimeout] se da por guardado en
/// el dispositivo (regresa false) y, si el servidor lo rechaza más tarde, se
/// llama a [onLateError] para avisar.
Future<bool> _awaitSave<T>(
  Future<T> save, {
  required VoidCallback onLateError,
}) async {
  try {
    await save.timeout(_saveTimeout);
    return true;
  } on TimeoutException {
    unawaited(save.then<void>((_) {}, onError: (Object _) => onLateError()));
    return false;
  }
}

void _showSnack(ScaffoldMessengerState messenger, String message) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Aviso rojo cuando no se pudo leer la despensa.
class PantryErrorBanner extends StatelessWidget {
  const PantryErrorBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return const InfoBanner(
      message:
          'No pudimos cargar tu despensa. Revisa tu conexión e intenta de '
          'nuevo.',
      background: AppColors.dangerSoft,
      foreground: AppColors.dangerText,
    );
  }
}

class _PantryLoading extends StatelessWidget {
  const _PantryLoading();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 33,
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

/// "Tienes X de Y ingredientes": verde si están todos, naranja si falta
/// alguno (como el badge de la tarjeta de receta).
class _AvailabilityPill extends StatelessWidget {
  const _AvailabilityPill(this.availability);

  final List<IngredientAvailability> availability;

  @override
  Widget build(BuildContext context) {
    final available = availability.where((a) => a.available).length;
    final label = 'Tienes $available de ${availability.length} ingredientes';

    if (available == availability.length) {
      return Pill.success(label: label, withIcon: false);
    }
    return Pill(
      label: label,
      background: AppColors.warningSoft,
      foreground: AppColors.warningText,
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
  const _IconText({
    required this.icon,
    required this.text,
    required this.style,
  });

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
  const _IngredientRow(this.ingredient, {required this.available});

  final RecipeIngredient ingredient;
  final bool available;

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
              color: available ? AppColors.primarySoft : null,
              border: available
                  ? null
                  : Border.all(color: AppColors.border, width: 2),
            ),
            alignment: Alignment.center,
            child: available
                ? const AppIcon(AppIcons.checkIngredient, size: 16)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(ingredient.name, style: AppText.nunito(16, 24))),
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
