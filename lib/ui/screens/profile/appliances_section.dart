import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../domain/models/appliance.dart';
import '../../formatting.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/option_button.dart';
import '../../widgets/pill.dart';

const pendingSyncLabel = 'Pendiente de sincronizar';

/// "Electrodomésticos" del Perfil: la familia marca los que tiene el hogar,
/// con las mismas opciones que Staff usa al registrarla.
///
/// La selección viene del documento de la familia ([applianceIds]): Firestore
/// aplica el cambio local al instante, también sin conexión, y [pendingSync]
/// dice si aún no llega al servidor. [onSave] recibe la lista completa.
class AppliancesSection extends StatefulWidget {
  const AppliancesSection({
    super.key,
    required this.applianceIds,
    required this.pendingSync,
    required this.onSave,
  });

  final List<String> applianceIds;
  final bool pendingSync;
  final Future<void> Function(List<String> ids, {Set<String> keep}) onSave;

  @override
  State<AppliancesSection> createState() => _AppliancesSectionState();
}

class _AppliancesSectionState extends State<AppliancesSection> {
  String? _error;

  /// Ids guardados que esta versión de la app no conoce: se conservan.
  Set<String> get _unknown => {
    for (final id in widget.applianceIds)
      if (Appliance.fromId(id) == null) id,
  };

  Future<void> _toggle(Appliance appliance) async {
    final selected = widget.applianceIds.toSet();
    if (!selected.remove(appliance.id)) selected.add(appliance.id);
    final unknown = _unknown;
    final ids = [
      for (final value in Appliance.values)
        if (selected.contains(value.id)) value.id,
      ...unknown,
    ];
    setState(() => _error = null);
    try {
      await widget.onSave(ids, keep: unknown);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _errorMessage(e));
    }
  }

  String _errorMessage(Object error) {
    if (error is ArgumentError && error.message is String) {
      return '${error.message}.';
    }
    if (error is FirebaseException && error.code == 'permission-denied') {
      return 'No tienes permiso para cambiar los electrodomésticos.';
    }
    return 'No se pudieron guardar los electrodomésticos. Revisa tu conexión '
        'e intenta de nuevo.';
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.applianceIds.toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Electrodomésticos',
                style: AppText.nunito(15, 22.5, weight: FontWeight.w700),
              ),
            ),
            if (widget.pendingSync)
              const Tooltip(
                message: pendingSyncLabel,
                child: AppIcon(AppIcons.cloudPending, size: 20),
              ),
          ],
        ),
        Text(
          'Toca los que tiene el hogar. Sirven para sugerir recetas que pueda '
          'preparar.',
          style: AppText.nunito(14, 21, color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final appliance in Appliance.values)
              OptionButton(
                label: applianceLabel(appliance),
                selected: selected.contains(appliance.id),
                pill: true,
                onTap: () => _toggle(appliance),
              ),
          ],
        ),
        if (_error case final error?) ...[
          const SizedBox(height: 8),
          InfoBanner(
            message: error,
            background: AppColors.dangerSoft,
            foreground: AppColors.dangerText,
          ),
        ],
      ],
    );
  }
}
