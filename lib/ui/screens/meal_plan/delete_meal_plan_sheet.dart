import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/danger_buttons.dart';
import '../../widgets/pill.dart';
import 'meal_plan_saving.dart';

const _title = 'Eliminar plan';
const _deleteError = 'No se pudo eliminar tu plan. Intenta de nuevo.';
const _lateDeleteError =
    'No se pudo eliminar tu plan. Revisa tu conexión e intenta de nuevo.';

/// Abre [DeleteMealPlanSheet].
Future<void> showDeleteMealPlanSheet(
  BuildContext context, {
  required String range,
  required Future<void> Function() onDelete,
}) {
  return showAppBottomSheet<void>(
    context,
    // Arrastrar para cerrar ignora AppSheet.busy y cerraría el sheet a media
    // escritura.
    enableDrag: false,
    builder: (_) => DeleteMealPlanSheet(range: range, onDelete: onDelete),
  );
}

/// Confirma antes de eliminar el plan guardado y después, en el mismo sheet,
/// avisa que se eliminó.
class DeleteMealPlanSheet extends StatefulWidget {
  const DeleteMealPlanSheet({
    super.key,
    required this.range,
    required this.onDelete,
  });

  /// "del 14 al 20 de octubre".
  final String range;
  final Future<void> Function() onDelete;

  @override
  State<DeleteMealPlanSheet> createState() => _DeleteMealPlanSheetState();
}

class _DeleteMealPlanSheetState extends State<DeleteMealPlanSheet> {
  bool _deleting = false;
  bool _deleted = false;

  /// false si se eliminó en el dispositivo y falta sincronizarlo.
  bool _synced = true;
  String? _error;

  Future<void> _delete() async {
    if (_deleting) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _deleting = true;
      _error = null;
    });
    final bool synced;
    try {
      synced = await awaitPlanWrite(
        widget.onDelete(),
        onLateError: () => showPlanSnack(messenger, _lateDeleteError),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = planWriteError(e, _deleteError);
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _deleting = false;
      _deleted = true;
      _synced = synced;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_deleted) {
      return AppSheet(
        title: _title,
        body: SuccessContent(
          heading: 'Plan eliminado',
          message: withSyncNote(
            'Ahora verás el plan sugerido con lo que hay en tu despensa.',
            synced: _synced,
          ),
          onDone: () => Navigator.of(context).pop(),
        ),
      );
    }

    final error = _error;
    return AppSheet(
      title: _title,
      busy: _deleting,
      body: Text(
        '¿Eliminar tu plan ${widget.range}? Volverás a ver el plan sugerido '
        'con lo que hay en tu despensa. Esta acción no se puede deshacer.',
        style: AppText.nunito(15, 22.5),
      ),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
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
          DangerButton(
            label: 'Eliminar',
            loading: _deleting,
            onPressed: _delete,
          ),
          const SizedBox(height: 8),
          Center(
            child: AbsorbPointer(
              absorbing: _deleting,
              child: TextLinkButton(
                label: 'Cancelar',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
