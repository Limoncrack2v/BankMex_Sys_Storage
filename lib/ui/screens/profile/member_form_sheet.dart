import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models/member.dart';
import '../../../data/repositories/member_repository.dart';
import '../../formatting.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/option_button.dart';
import '../../widgets/pill.dart';

/// Formulario de integrante del hogar (agregar, editar o eliminar). Guarda en
/// families/{familyId}/members y después el mismo sheet muestra la
/// confirmación.
Future<void> showMemberFormSheet(
  BuildContext context, {
  required String familyId,
  Member? initial,
}) {
  return showAppBottomSheet<void>(
    context,
    // Arrastrar para cerrar ignora AppSheet.busy y cerraría el sheet a media
    // escritura.
    enableDrag: false,
    builder: (_) => MemberFormSheet(familyId: familyId, initial: initial),
  );
}

/// Opciones de "Tipo de integrante" del diseño.
enum _MemberKind {
  adult('Adulto'),
  boy('Niño'),
  girl('Niña');

  const _MemberKind(this.label);

  final String label;
}

const _ageError = 'La edad debe estar entre 0 y ${Member.maxAge} años.';
final _weightError =
    'El peso debe ser mayor a 0 y no más de ${formatNumber(Member.maxWeightKg)} kg.';
const _saveError = 'No se pudo guardar el integrante. Intenta de nuevo.';
const _lateSaveError =
    'No se pudo guardar el integrante. Revisa tu conexión e intenta de nuevo.';
const _deleteError = 'No se pudo eliminar el integrante. Intenta de nuevo.';
const _lateDeleteError =
    'No se pudo eliminar el integrante. Revisa tu conexión e intenta de nuevo.';
const _notFoundError = 'Este integrante ya no está registrado en tu hogar.';
const _pendingSyncNote = 'Se sincronizará cuando haya conexión.';
const _deleteTitle = 'Eliminar integrante';

// Sin conexión, Firestore aplica el cambio en el dispositivo (la lista de
// integrantes se actualiza al instante) pero el guardado no termina hasta
// volver a estar en línea. Pasado este tiempo se da por guardado y se
// sincroniza después.
const _saveTimeout = Duration(seconds: 4);

class MemberFormSheet extends StatefulWidget {
  const MemberFormSheet({super.key, required this.familyId, this.initial});

  final String familyId;
  final Member? initial;

  @override
  State<MemberFormSheet> createState() => _MemberFormSheetState();
}

class _MemberFormSheetState extends State<MemberFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _age;
  late final TextEditingController _weight;

  /// null solo al editar a una niña o niño sin sexo capturado: se guarda como
  /// niño o niña sin especificar mientras no se elija una opción.
  _MemberKind? _kind;
  late final Set<Allergy> _allergies;
  late bool _noAllergies;
  bool _saving = false;
  bool _deleting = false;
  bool _confirmingDelete = false;
  String? _error;
  Member? _saved;
  bool _deleted = false;

  /// false si el cambio quedó en el dispositivo y falta sincronizarlo.
  bool _synced = true;

  bool get _isEditing => widget.initial != null;

  bool get _busy => _saving || _deleting;

  bool get _canSave =>
      _name.text.trim().isNotEmpty &&
      _age.text.trim().isNotEmpty &&
      (_noAllergies || _allergies.isNotEmpty);

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final weight = initial?.weightKg;
    _name = TextEditingController(text: initial?.name);
    _age = TextEditingController(text: initial?.age?.toString());
    _weight = TextEditingController(
      text: weight == null ? null : formatNumber(weight),
    );
    _kind = switch (initial) {
      null => _MemberKind.adult,
      Member(memberType: MemberType.adult) => _MemberKind.adult,
      Member(sex: MemberSex.male) => _MemberKind.boy,
      Member(sex: MemberSex.female) => _MemberKind.girl,
      _ => null,
    };
    _allergies = {...?initial?.allergies};
    _noAllergies = initial?.allergies?.isEmpty ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _weight.dispose();
    super.dispose();
  }

  void _toggleAllergy(Allergy allergy) {
    setState(() {
      _error = null;
      _noAllergies = false;
      if (!_allergies.remove(allergy)) _allergies.add(allergy);
    });
  }

  void _selectNoAllergies() {
    setState(() {
      _error = null;
      _noAllergies = true;
      _allergies.clear();
    });
  }

  void _selectKind(_MemberKind kind) {
    setState(() {
      _error = null;
      _kind = kind;
    });
  }

  /// Arma el integrante con lo capturado o regresa el error a mostrar.
  ({Member? member, String? error}) _buildMember() {
    final age = int.tryParse(_age.text.trim());
    if (age == null) return (member: null, error: _ageError);

    final weightText = _weight.text.trim().replaceAll(',', '.');
    final weight = weightText.isEmpty ? null : double.tryParse(weightText);
    if (weightText.isNotEmpty && weight == null) {
      return (member: null, error: _weightError);
    }

    final initial = widget.initial;
    final member = Member(
      memberId: initial?.memberId ?? '',
      name: _name.text.trim(),
      memberType: _kind == _MemberKind.adult
          ? MemberType.adult
          : MemberType.child,
      createdAt: initial?.createdAt ?? DateTime.now(),
      age: age,
      weightKg: weight,
      sex: switch (_kind) {
        _MemberKind.boy => MemberSex.male,
        _MemberKind.girl => MemberSex.female,
        _ => null,
      },
      allergies: _noAllergies
          ? const []
          : Allergy.values.where(_allergies.contains).toList(),
    );
    final error = member.validate();
    return error == null
        ? (member: member, error: null)
        : (member: null, error: _sentence(error));
  }

  Future<void> _save() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();

    final (:member, :error) = _buildMember();
    if (member == null) {
      setState(() => _error = error);
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    final bool synced;
    try {
      final repository = MemberRepository();
      synced = await _awaitSave(
        _isEditing
            ? repository.replaceMember(widget.familyId, member)
            : repository.createMember(widget.familyId, member),
        onLateError: () => _showSnack(messenger, _lateSaveError),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _errorMessage(e, _saveError);
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = member;
      _synced = synced;
    });
  }

  void _askDelete() {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _confirmingDelete = true;
    });
  }

  void _cancelDelete() {
    setState(() {
      _error = null;
      _confirmingDelete = false;
    });
  }

  Future<void> _delete() async {
    final member = widget.initial;
    if (_busy || member == null) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _deleting = true;
      _error = null;
    });
    final bool synced;
    try {
      synced = await _awaitSave(
        MemberRepository().deleteMember(widget.familyId, member.memberId),
        onLateError: () => _showSnack(messenger, _lateDeleteError),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = _errorMessage(e, _deleteError);
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

  String _errorMessage(Object error, String fallback) {
    if (error is ArgumentError && error.message is String) {
      return _sentence(error.message as String);
    }
    if (error is FirebaseException && error.code == 'not-found') {
      return _notFoundError;
    }
    return fallback;
  }

  /// Agrega la nota de sincronización si el cambio sigue pendiente.
  String _withSyncNote(String message) =>
      _synced ? message : '$message $_pendingSyncNote';

  @override
  Widget build(BuildContext context) {
    final title = _isEditing ? 'Editar integrante' : 'Agregar integrante';
    final saved = _saved;
    final error = _error;

    if (_deleted) {
      return AppSheet(
        title: _deleteTitle,
        body: SuccessContent(
          heading: 'Integrante eliminado',
          message: _withSyncNote(
            'Se actualizó la lista de integrantes de tu hogar.',
          ),
          onDone: () => Navigator.of(context).pop(),
        ),
      );
    }

    if (saved != null) {
      return AppSheet(
        title: title,
        body: SuccessContent(
          heading: _isEditing ? 'Cambios guardados' : 'Integrante añadido',
          message: _withSyncNote(
            _isEditing
                ? 'Se actualizó la información de ${saved.name}.'
                : 'Se actualizó la lista de integrantes de tu hogar.',
          ),
          onDone: () => Navigator.of(context).pop(),
        ),
      );
    }

    if (_confirmingDelete) return _buildDeleteConfirmation();

    return AppSheet(
      title: title,
      busy: _saving,
      body: AbsorbPointer(absorbing: _saving, child: _buildForm()),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (error != null) ...[
            InfoBanner(
              message: error,
              background: AppColors.dangerSoft,
              foreground: AppColors.dangerText,
            ),
            const SizedBox(height: 8),
          ],
          Text(
            'Nombre, edad y alergias son obligatorios para guardar.',
            style: AppText.nunito(14, 21, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          PrimaryButton(
            label: _isEditing ? 'Guardar cambios' : 'Guardar integrante',
            icon: AppIcons.check,
            loading: _saving,
            onPressed: _canSave ? _save : null,
          ),
          if (_isEditing) ...[
            const SizedBox(height: 8),
            Center(
              child: _DangerLinkButton(
                label: 'Eliminar integrante',
                onPressed: _saving ? null : _askDelete,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeleteConfirmation() {
    final error = _error;

    return AppSheet(
      title: _deleteTitle,
      busy: _deleting,
      body: Text(
        '¿Eliminar a ${widget.initial!.name} de tu hogar? Esta acción no se '
        'puede deshacer.',
        style: AppText.nunito(15, 22.5),
      ),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (error != null) ...[
            InfoBanner(
              message: error,
              background: AppColors.dangerSoft,
              foreground: AppColors.dangerText,
            ),
            const SizedBox(height: 8),
          ],
          _DangerButton(
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
                onPressed: _cancelDelete,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    void refresh(String _) => setState(() => _error = null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LabeledField(
          label: 'Nombre',
          required: true,
          child: AppTextField(
            controller: _name,
            hint: 'Nombre del integrante',
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            maxLength: Member.maxNameLength,
            onChanged: refresh,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LabeledField(
                label: 'Edad (años)',
                required: true,
                child: AppTextField(
                  controller: _age,
                  hint: '0',
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  onChanged: refresh,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LabeledField(
                label: 'Peso (kg)',
                child: AppTextField(
                  controller: _weight,
                  hint: '0',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    LengthLimitingTextInputFormatter(5),
                  ],
                  onChanged: refresh,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: 'Tipo de integrante',
          child: Row(
            children: [
              for (final kind in _MemberKind.values) ...[
                if (kind != _MemberKind.values.first) const SizedBox(width: 8),
                Expanded(
                  child: OptionButton(
                    label: kind.label,
                    selected: _kind == kind,
                    onTap: () => _selectKind(kind),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: 'Alergias',
          required: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Toca las que apliquen o elige «Ninguna». Puedes elegir varias.',
                style: AppText.nunito(14, 21, color: AppColors.textMuted),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OptionButton(
                    label: 'Ninguna',
                    selected: _noAllergies,
                    pill: true,
                    onTap: _selectNoAllergies,
                  ),
                  for (final allergy in Allergy.values)
                    OptionButton(
                      label: allergyLabel(allergy),
                      selected: _allergies.contains(allergy),
                      pill: true,
                      onTap: () => _toggleAllergy(allergy),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Botón rojo de ancho completo para confirmar una acción que no se puede
/// deshacer. Misma forma y tamaño que [PrimaryButton].
class _DangerButton extends StatelessWidget {
  const _DangerButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool loading;

  static const _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(16)),
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: AppColors.danger,
        shape: _shape,
        child: InkWell(
          onTap: loading ? null : onPressed,
          customBorder: _shape,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              child: Center(
                child: loading
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        label,
                        textAlign: TextAlign.center,
                        style: AppText.nunito(
                          17,
                          25.5,
                          weight: FontWeight.w700,
                          color: Colors.white,
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

/// Enlace rojo subrayado, como [TextLinkButton], para acciones de borrar.
/// Con [onPressed] nulo no responde (p. ej. mientras se guarda).
class _DangerLinkButton extends StatelessWidget {
  const _DangerLinkButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style:
              AppText.nunito(
                15,
                22.5,
                weight: FontWeight.w700,
                color: AppColors.dangerText,
              ).copyWith(
                decoration: TextDecoration.underline,
                decorationColor: AppColors.dangerText,
              ),
        ),
      ),
    );
  }
}

/// Espera [save] hasta [_saveTimeout]. Regresa false si se agotó el tiempo:
/// el cambio ya está en el dispositivo y se sincroniza al volver la conexión.
/// Si después el servidor lo rechaza, llama a [onLateError].
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

/// Los mensajes de validación del modelo no llevan punto final.
String _sentence(String message) =>
    RegExp(r'[.?!]$').hasMatch(message) ? message : '$message.';
