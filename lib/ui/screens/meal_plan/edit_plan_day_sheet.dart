import 'package:flutter/material.dart';

import '../../models/recipe.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/danger_buttons.dart';
import '../../widgets/pill.dart';
import 'meal_plan_saving.dart';

const _saveError = 'No se pudo cambiar tu plan. Intenta de nuevo.';
const _lateSaveError =
    'No se pudo guardar el cambio en tu plan. Revisa tu conexión e intenta '
    'de nuevo.';

/// Una receta que se puede elegir para el día: su tarjeta (ver
/// [planOptionsFor]) y lo que le falta al hogar para prepararla
/// ("licuadora").
typedef PlanDayOption = ({MealPlanEntry entry, List<String> missingAppliances});

/// Si el hogar tiene lo que pide la receta.
bool _suitable(PlanDayOption option) => option.missingAppliances.isEmpty;

/// Un cambio elegido que falta confirmar: qué se escribe, qué se dice al
/// guardarlo y cómo se pregunta.
typedef _Pending = ({
  String saving,
  Future<void> Function() write,
  String success,
  String question,
  String? detail,
  String confirmLabel,
  bool clears,
});

/// Abre [EditPlanDaySheet]. Pide confirmar el cambio antes de guardarlo y lo
/// confirma con la palomita en el mismo sheet.
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

  /// En el orden de [planOptionsFor], sin alérgenos de la familia. Las que
  /// piden algo que el hogar no tiene van al final.
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

  /// Lo que dice la confirmación, ya guardado el cambio.
  String? _done;

  /// El cambio que se está por confirmar: un toque por error en la lista no
  /// cambia el plan.
  _Pending? _pending;

  Future<void> _write(
    String saving,
    Future<void> Function() write,
    String success,
  ) async {
    if (_saving != null) return;

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
    setState(() {
      _saving = null;
      _done = withSyncNote(success, synced: synced);
    });
  }

  void _ask(_Pending pending) => setState(() {
    _error = null;
    _pending = pending;
  });

  void _pick(Recipe recipe) {
    final day = widget.dayName;
    if (widget.currentRecipeId == null) {
      return _ask((
        saving: recipe.id,
        write: () => widget.onPick(recipe),
        success: 'Elegiste la receta del $day.',
        question: '¿Elegir «${recipe.name}» para el $day?',
        detail: null,
        confirmLabel: 'Elegir receta',
        clears: false,
      ));
    }
    final current = widget.options
        .map((option) => option.entry.recipe)
        .where((option) => option.id == widget.currentRecipeId)
        .firstOrNull;
    _ask((
      saving: recipe.id,
      write: () => widget.onPick(recipe),
      success: 'Cambiaste la receta del $day.',
      question: '¿Cambiar la receta del $day?',
      detail: current == null
          ? 'Se guardará «${recipe.name}».'
          : '«${current.name}» se cambia por «${recipe.name}».',
      confirmLabel: 'Cambiar receta',
      clears: false,
    ));
  }

  void _clear(Future<void> Function() clear) => _ask((
    saving: '',
    write: clear,
    success: 'El ${widget.dayName} quedó libre.',
    question: '¿Dejar libre el ${widget.dayName}?',
    detail: 'Ese día no tendrá receta en tu plan.',
    confirmLabel: 'Dejar día libre',
    clears: true,
  ));

  void _confirm() {
    final pending = _pending;
    if (pending != null) _write(pending.saving, pending.write, pending.success);
  }

  Widget _buildConfirm(_Pending pending) {
    final error = _error;
    final saving = _saving != null;
    return AppSheet(
      title: widget.title,
      busy: saving,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(pending.question, style: AppText.baloo(19, 28.5)),
          if (pending.detail case final detail?) ...[
            const SizedBox(height: 8),
            Text(
              detail,
              style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null) ...[
            Semantics(
              liveRegion: true,
              child: InfoBanner(
                message: error,
                background: AppColors.dangerSoft,
                foreground: AppColors.dangerText,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (pending.clears)
            DangerButton(
              label: pending.confirmLabel,
              loading: saving,
              onPressed: _confirm,
            )
          else
            PrimaryButton(
              label: pending.confirmLabel,
              icon: AppIcons.check,
              loading: saving,
              onPressed: _confirm,
            ),
          const SizedBox(height: 8),
          SecondaryButton(
            label: 'Volver',
            onPressed: () {
              if (_saving == null) setState(() => _pending = null);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_done case final done?) {
      return AppSheet(
        title: widget.title,
        body: SuccessContent(
          heading: 'Plan actualizado',
          message: done,
          onDone: () => Navigator.of(context).pop(),
        ),
      );
    }
    if (_pending case final pending?) return _buildConfirm(pending);

    final error = _error;
    final clear = widget.onClear;
    final options = [
      ...widget.options.where(_suitable),
      ...widget.options.where((option) => !_suitable(option)),
    ];
    const order =
        'Elige qué cocinar este día. Primero van las que puedes preparar con '
        'tu despensa, y entre ellas las que usan lo que caduca antes.';
    final intro = options.every(_suitable)
        ? order
        : '$order Al final, las que piden algo que no tienes.';

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
          for (final (:entry, :missingAppliances) in options) ...[
            const SizedBox(height: 12),
            _OptionCard(
              entry: entry,
              missingAppliances: missingAppliances,
              current: entry.recipe.id == widget.currentRecipeId,
              onTap: () => _pick(entry.recipe),
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
                  Semantics(
                    container: true,
                    button: true,
                    label: 'Dejar este día libre: ${widget.dayName}',
                    excludeSemantics: true,
                    onTap: () => _clear(clear),
                    child: DangerButton(
                      label: 'Dejar este día libre',
                      onPressed: () => _clear(clear),
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
    required this.missingAppliances,
    required this.current,
    required this.onTap,
  });

  final MealPlanEntry entry;
  final List<String> missingAppliances;
  final bool current;
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
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
