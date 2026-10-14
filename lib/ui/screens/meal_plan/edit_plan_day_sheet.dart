import 'package:flutter/material.dart';

import '../../models/recipe.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/danger_buttons.dart';
import '../../widgets/pill.dart';
import 'meal_plan_saving.dart';

const _saveError = 'No se pudo cambiar tu plan. Intenta de nuevo.';
const _lateSaveError =
    'No se pudo guardar el cambio en tu plan. Revisa tu conexión e intenta '
    'de nuevo.';

/// Una receta que se puede elegir para el día: su tarjeta (ver
/// [planOptionsFor]), si lleva alérgenos de la familia y lo que le falta al
/// hogar para prepararla ("licuadora").
typedef PlanDayOption = ({
  MealPlanEntry entry,
  bool hasAllergens,
  List<String> missingAppliances,
});

/// Si la receta le conviene al hogar: sin alérgenos y con lo que pide.
bool _suitable(PlanDayOption option) =>
    !option.hasAllergens && option.missingAppliances.isEmpty;

/// Abre [EditPlanDaySheet]. Al guardar se cierra y avisa con un snackbar.
Future<void> showEditPlanDaySheet(
  BuildContext context, {
  required String title,
  required String dayName,
  required List<PlanDayOption> options,
  required String? currentRecipeId,
  required Future<void> Function(Recipe recipe) onPick,
  required Future<void> Function()? onClear,
}) {
  return showAppBottomSheet<void>(
    context,
    // Arrastrar para cerrar ignora AppSheet.busy y cerraría el sheet a media
    // escritura.
    enableDrag: false,
    builder: (_) => EditPlanDaySheet(
      title: title,
      dayName: dayName,
      options: options,
      currentRecipeId: currentRecipeId,
      onPick: onPick,
      onClear: onClear,
    ),
  );
}

/// Elegir la receta de un día del plan guardado, o dejar el día libre.
class EditPlanDaySheet extends StatefulWidget {
  const EditPlanDaySheet({
    super.key,
    required this.title,
    required this.dayName,
    required this.options,
    required this.currentRecipeId,
    required this.onPick,
    required this.onClear,
  });

  /// "Miércoles 16 de octubre".
  final String title;

  /// "miércoles 16", para el aviso al guardar.
  final String dayName;

  /// En el orden de [planOptionsFor]. Las que no le convienen al hogar van
  /// al final; "Pedir una receta" ni siquiera las sugiere.
  final List<PlanDayOption> options;

  /// La receta guardada para el día; null si está libre.
  final String? currentRecipeId;

  /// Guarda el plan con la receta elegida (ajustada al hogar) en el día.
  final Future<void> Function(Recipe recipe) onPick;

  /// Deja el día libre. Null si ya lo está.
  final Future<void> Function()? onClear;

  @override
  State<EditPlanDaySheet> createState() => _EditPlanDaySheetState();
}

class _EditPlanDaySheetState extends State<EditPlanDaySheet> {
  /// Id de la receta que se está guardando, o '' al dejar el día libre.
  String? _saving;
  String? _error;

  Future<void> _write(
    String saving,
    Future<void> Function() write,
    String success,
  ) async {
    if (_saving != null) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = saving;
      _error = null;
    });
    final bool synced;
    try {
      synced = await awaitPlanWrite(
        write(),
        onLateError: () => showPlanSnack(messenger, _lateSaveError),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = null;
        _error = planWriteError(e, _saveError);
      });
      return;
    }
    if (!mounted) return;
    navigator.pop();
    showPlanSnack(messenger, withSyncNote(success, synced: synced));
  }

  void _pick(Recipe recipe) => _write(
    recipe.id,
    () => widget.onPick(recipe),
    widget.currentRecipeId == null
        ? 'Elegiste la receta del ${widget.dayName}.'
        : 'Cambiaste la receta del ${widget.dayName}.',
  );

  void _clear(Future<void> Function() clear) =>
      _write('', clear, 'El ${widget.dayName} quedó libre.');

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final clear = widget.onClear;
    final options = [
      ...widget.options.where(_suitable),
      ...widget.options.where((option) => !_suitable(option)),
    ];
    final intro = options.every(_suitable)
        ? 'Elige qué cocinar este día. Primero van las recetas que usan lo que '
              'caduca antes.'
        : 'Elige qué cocinar este día. Primero van las recetas que usan lo que '
              'caduca antes; al final, las que llevan alérgenos de tu familia '
              'o piden algo que no tienes.';

    return AppSheet(
      title: widget.title,
      busy: _saving != null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            options.isEmpty
                ? 'No hay recetas del catálogo para elegir.'
                : intro,
            style: AppText.nunito(14, 21, color: AppColors.textMuted),
          ),
          for (final (:entry, :hasAllergens, :missingAppliances)
              in options) ...[
            const SizedBox(height: 12),
            _OptionCard(
              entry: entry,
              hasAllergens: hasAllergens,
              missingAppliances: missingAppliances,
              current: entry.recipe.id == widget.currentRecipeId,
              saving: _saving == entry.recipe.id,
              onTap: _saving == null ? () => _pick(entry.recipe) : null,
            ),
          ],
        ],
      ),
      footer: clear == null && error == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (error != null)
                  Semantics(
                    liveRegion: true,
                    child: InfoBanner(
                      message: error,
                      background: AppColors.dangerSoft,
                      foreground: AppColors.dangerText,
                    ),
                  ),
                if (error != null && clear != null) const SizedBox(height: 8),
                if (clear != null)
                  Center(
                    child: _saving == ''
                        ? const SizedBox(
                            height: 48,
                            child: Center(child: _Saving()),
                          )
                        : DangerLinkButton(
                            label: 'Dejar este día libre',
                            semanticLabel:
                                'Dejar este día libre: ${widget.dayName}',
                            onPressed: _saving == null
                                ? () => _clear(clear)
                                : null,
                          ),
                  ),
              ],
            ),
    );
  }
}

/// Una receta para elegir. La que ya tiene el día va marcada como "Actual" y
/// no se puede volver a elegir.
class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.entry,
    required this.hasAllergens,
    required this.missingAppliances,
    required this.current,
    required this.saving,
    required this.onTap,
  });

  final MealPlanEntry entry;
  final bool hasAllergens;
  final List<String> missingAppliances;
  final bool current;
  final bool saving;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final recipe = entry.recipe;
    final shape = RoundedRectangleBorder(
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      side: current
          ? const BorderSide(color: AppColors.primary, width: 2)
          : const BorderSide(color: AppColors.border),
    );
    final muted = AppText.nunito(14, 21, color: AppColors.textMuted);

    return Semantics(
      selected: current,
      button: !current,
      child: Material(
        color: current ? AppColors.primarySoft : AppColors.surface,
        shape: shape,
        child: InkWell(
          onTap: current ? null : onTap,
          customBorder: shape,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recipe.name,
                        style: AppText.baloo(
                          17,
                          21.25,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const AppIcon(AppIcons.clock, size: 16),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text('${recipe.minutes} min', style: muted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(entry.reason, style: muted),
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
                      if (missingAppliances.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Necesita ${joinWithAnd(missingAppliances)}',
                          style: muted,
                        ),
                      ],
                    ],
                  ),
                ),
                if (current) ...[
                  const SizedBox(width: 12),
                  const Pill.success(label: 'Actual'),
                ] else if (saving) ...[
                  const SizedBox(width: 12),
                  const _Saving(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Saving extends StatelessWidget {
  const _Saving();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 22,
      child: CircularProgressIndicator(
        strokeWidth: 2.5,
        color: AppColors.primary,
      ),
    );
  }
}
