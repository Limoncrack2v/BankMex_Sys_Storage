import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models/family.dart';
import '../../../data/repositories/family_repository.dart';
import '../../../domain/name_normalizer.dart';
import '../../formatting.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/option_button.dart';
import '../../widgets/pill.dart';

/// Sin conexión el update no termina hasta sincronizar; pasado este tiempo
/// se da por guardado (igual que en Entregas).
const _saveTimeout = Duration(seconds: 4);
const _pendingSyncNote = 'Se sincronizará cuando haya conexión.';

/// Familias registradas, para que el staff corrija el nombre, la dirección o
/// la cuota de recuperación de una.
Future<void> showFamiliesSheet(BuildContext context) {
  return showAppBottomSheet<void>(
    context,
    // Arrastrar para cerrar ignoraría AppSheet.busy mientras se guarda.
    enableDrag: false,
    builder: (_) => const _FamiliesSheet(),
  );
}

class _FamiliesSheet extends StatefulWidget {
  const _FamiliesSheet();

  @override
  State<_FamiliesSheet> createState() => _FamiliesSheetState();
}

class _FamiliesSheetState extends State<_FamiliesSheet> {
  late final Stream<List<Family>> _families;
  final _search = TextEditingController();

  /// Familia que se está editando; null muestra la lista.
  Family? _selected;

  @override
  void initState() {
    super.initState();
    _families = FamilyRepository().watchAllFamilies();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Family family, String query) =>
      NameNormalizer.normalize(family.displayName).contains(query) ||
      NameNormalizer.normalize(family.address).contains(query);

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    if (selected != null) {
      return FamilyEditForm(
        family: selected,
        onDone: () => setState(() => _selected = null),
      );
    }

    return AppSheet(
      title: 'Familias',
      body: StreamBuilder<List<Family>>(
        stream: _families,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const InfoBanner(
              message:
                  'No se pudieron cargar las familias. Revisa tu '
                  'conexión.',
              background: AppColors.dangerSoft,
              foreground: AppColors.dangerText,
            );
          }
          final families = snapshot.data;
          if (families == null) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            );
          }
          final query = NameNormalizer.normalize(_search.text);
          final shown = [
            for (final family in families)
              if (query.isEmpty || _matches(family, query)) family,
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                controller: _search,
                hint: 'Buscar por nombre o dirección',
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    families.isEmpty
                        ? 'No hay familias registradas.'
                        : 'Ninguna familia coincide con la búsqueda.',
                    textAlign: TextAlign.center,
                    style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
                  ),
                ),
              for (final (index, family) in shown.indexed) ...[
                if (index > 0) const SizedBox(height: 12),
                _FamilyCard(
                  family: family,
                  onEdit: () => setState(() => _selected = family),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _FamilyCard extends StatelessWidget {
  const _FamilyCard({required this.family, required this.onEdit});

  final Family family;
  final VoidCallback onEdit;

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
          Text(
            family.displayName,
            style: AppText.nunito(16, 24, weight: FontWeight.w700),
          ),
          Text(
            family.address,
            style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
          ),
          Text(
            'Cuota de recuperación: '
            '${formatRecoveryFee(family.recoveryQuotaDefault)}',
            style: AppText.nunito(14, 21, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          SecondaryButton(label: 'Editar', onPressed: onEdit),
        ],
      ),
    );
  }
}

/// FamilyRepository.updateFamilyDetails; las pruebas pasan uno falso.
typedef SaveFamilyDetails = Future<void> Function(
  Family family, {
  required String name,
  required String address,
  required double? recoveryQuotaDefault,
});

/// Corrige el nombre, la dirección y la cuota de recuperación por defecto de
/// [family]. Nunca toca la cuenta dueña ni la fecha de la próxima entrega.
/// Rechaza en el formulario lo que validFamily rechazaría.
class FamilyEditForm extends StatefulWidget {
  const FamilyEditForm({
    super.key,
    required this.family,
    required this.onDone,
    this.save,
  });

  final Family family;

  /// Volver a la lista.
  final VoidCallback onDone;

  /// Por omisión, FamilyRepository().updateFamilyDetails.
  final SaveFamilyDetails? save;

  @override
  State<FamilyEditForm> createState() => _FamilyEditFormState();
}

class _FamilyEditFormState extends State<FamilyEditForm> {
  late final _name = TextEditingController(text: widget.family.name ?? '');
  late final _address = TextEditingController(text: widget.family.address);
  late final _quota = TextEditingController(
    text: switch (widget.family.recoveryQuotaDefault) {
      final quota? => formatNumber(quota),
      null => '',
    },
  );
  late bool _exempt = widget.family.recoveryQuotaDefault == null;
  bool _saving = false;
  String? _error;
  String? _successMessage;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _quota.dispose();
    super.dispose();
  }

  /// La cuota escrita; null si está vacía o no es un número.
  double? get _quotaAmount {
    final value = double.tryParse(_quota.text.trim().replaceAll(',', '.'));
    return value != null && value.isFinite ? value : null;
  }

  /// Lo que impide guardar, o null.
  String? get _problem {
    if (!_exempt && _quotaAmount == null) {
      return 'Escribe la cuota de recuperación o márcala como Exenta.';
    }
    return Family.validateDetails(
      name: _name.text,
      address: _address.text,
      recoveryQuotaDefault: _exempt ? null : _quotaAmount,
    );
  }

  bool get _changed => widget.family
      .detailChanges(
        name: _name.text,
        address: _address.text,
        recoveryQuotaDefault: _exempt ? null : _quotaAmount,
      )
      .isNotEmpty;

  void _onChanged(String _) => setState(() => _error = null);

  void _toggleExempt() => setState(() {
    _error = null;
    _exempt = !_exempt;
  });

  Future<void> _save() async {
    if (_saving || _problem != null || !_changed) return;
    FocusScope.of(context).unfocus();
    final messenger = ScaffoldMessenger.of(context);
    final name = _name.text.trim();
    setState(() {
      _saving = true;
      _error = null;
    });

    final save = widget.save ?? FamilyRepository().updateFamilyDetails;
    final bool synced;
    try {
      synced = await _awaitSave(
        save(
          widget.family,
          name: _name.text,
          address: _address.text,
          recoveryQuotaDefault: _exempt ? null : _quotaAmount,
        ),
        onLateError: (error) => _showSnack(
          messenger,
          'No se pudieron sincronizar los cambios de $name. Revisa la '
          'familia e intenta de nuevo.',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _errorMessage(e);
      });
      return;
    }
    if (!mounted) return;

    var message = 'Se guardaron los datos de $name.';
    if (!synced) message = '$message $_pendingSyncNote';
    setState(() {
      _saving = false;
      _successMessage = message;
    });
  }

  String _errorMessage(Object error) {
    if (error is ArgumentError && error.message is String) {
      return error.message as String;
    }
    if (error is FirebaseException && error.code == 'permission-denied') {
      return 'Tu cuenta no tiene permiso para editar esta familia.';
    }
    return 'No se pudieron guardar los cambios. Revisa tu conexión e intenta '
        'de nuevo.';
  }

  @override
  Widget build(BuildContext context) {
    final successMessage = _successMessage;
    if (successMessage != null) {
      return AppSheet(
        title: 'Editar familia',
        body: SuccessContent(
          heading: 'Cambios guardados',
          message: successMessage,
          onDone: widget.onDone,
        ),
      );
    }

    final problem = _problem;
    final error = _error;

    return AppSheet(
      title: 'Editar familia',
      busy: _saving,
      body: IgnorePointer(ignoring: _saving, child: _buildFields()),
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
            const SizedBox(height: 12),
          ] else if (problem != null) ...[
            Text(
              problem,
              style: AppText.nunito(14, 21, color: AppColors.dangerText),
            ),
            const SizedBox(height: 8),
          ],
          PrimaryButton(
            label: 'Guardar cambios',
            icon: AppIcons.check,
            loading: _saving,
            onPressed: problem == null && _changed ? _save : null,
          ),
          const SizedBox(height: 8),
          Center(
            child: Opacity(
              opacity: _saving ? 0.4 : 1,
              child: TextLinkButton(
                label: 'Volver',
                onPressed: () {
                  if (!_saving) widget.onDone();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LabeledField(
          label: 'Nombre de la familia',
          required: true,
          child: AppTextField(
            key: const ValueKey('familyName'),
            controller: _name,
            hint: 'Familia Ramírez',
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            maxLength: Family.maxNameLength,
            onChanged: _onChanged,
          ),
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: 'Dirección',
          required: true,
          child: AppTextField(
            key: const ValueKey('familyAddress'),
            controller: _address,
            hint: 'Calle, número y colonia',
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            keyboardType: TextInputType.streetAddress,
            maxLength: Family.maxAddressLength,
            onChanged: _onChanged,
          ),
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: 'Cuota de recuperación por defecto',
          child: Row(
            children: [
              Expanded(
                child: AppTextField(
                  key: const ValueKey('familyQuota'),
                  controller: _quota,
                  hint: formatNumber(Family.standardRecoveryQuota),
                  prefixText: r'$',
                  enabled: !_exempt,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  maxLength: 9,
                  onChanged: _onChanged,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 84,
                child: OptionButton(
                  label: 'Exenta',
                  selected: _exempt,
                  onTap: _toggleExempt,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'El formulario de entregas la propone para esta familia.',
          style: AppText.nunito(14, 21, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

/// Espera a que Firestore confirme [save]. Regresa false si pasado
/// [_saveTimeout] sigue pendiente (sin conexión el cambio ya quedó en el
/// dispositivo); si después falla al sincronizar, llama a [onLateError].
Future<bool> _awaitSave(
  Future<void> save, {
  required void Function(Object error) onLateError,
}) async {
  try {
    await save.timeout(_saveTimeout);
    return true;
  } on TimeoutException {
    unawaited(save.then<void>((_) {}, onError: onLateError));
    return false;
  }
}

void _showSnack(ScaffoldMessengerState messenger, String message) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
