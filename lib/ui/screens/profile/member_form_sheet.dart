import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/household_member.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_text_field.dart';

/// Formulario de integrante del hogar (agregar o editar). Después de guardar,
/// el mismo sheet muestra la confirmación.
Future<void> showMemberFormSheet(
  BuildContext context, {
  HouseholdMember? initial,
  required ValueChanged<HouseholdMember> onSave,
}) {
  return showAppBottomSheet<void>(
    context,
    builder: (_) => MemberFormSheet(initial: initial, onSave: onSave),
  );
}

class MemberFormSheet extends StatefulWidget {
  const MemberFormSheet({super.key, this.initial, required this.onSave});

  final HouseholdMember? initial;
  final ValueChanged<HouseholdMember> onSave;

  @override
  State<MemberFormSheet> createState() => _MemberFormSheetState();
}

class _MemberFormSheetState extends State<MemberFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _age;
  late final TextEditingController _weight;
  late MemberType _type;
  late final Set<String> _allergies;
  late bool _noAllergies;
  HouseholdMember? _saved;

  bool get _isEditing => widget.initial != null;

  bool get _canSave =>
      _name.text.trim().isNotEmpty &&
      int.tryParse(_age.text) != null &&
      (_noAllergies || _allergies.isNotEmpty);

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name);
    _age = TextEditingController(text: initial?.age.toString());
    _weight = TextEditingController(
      text: initial?.weightKg == null ? null : formatKg(initial!.weightKg!),
    );
    _type = initial?.type ?? MemberType.adulto;
    _allergies = {...?initial?.allergies};
    _noAllergies = initial != null && initial.allergies.isEmpty;
  }

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _weight.dispose();
    super.dispose();
  }

  void _toggleAllergy(String allergy) {
    setState(() {
      _noAllergies = false;
      if (!_allergies.remove(allergy)) _allergies.add(allergy);
    });
  }

  void _selectNoAllergies() {
    setState(() {
      _noAllergies = true;
      _allergies.clear();
    });
  }

  void _save() {
    FocusScope.of(context).unfocus();
    final member = HouseholdMember(
      name: _name.text.trim(),
      age: int.parse(_age.text),
      weightKg: double.tryParse(_weight.text.replaceAll(',', '.')),
      type: _type,
      allergies: _noAllergies
          ? const []
          : allergyOptions.where(_allergies.contains).toList(),
    );
    widget.onSave(member);
    setState(() => _saved = member);
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEditing ? 'Editar integrante' : 'Agregar integrante';
    final saved = _saved;

    if (saved != null) {
      return AppSheet(
        title: title,
        body: SuccessContent(
          heading: _isEditing ? 'Cambios guardados' : 'Integrante añadido',
          message: _isEditing
              ? 'Se actualizó la información de ${saved.name}.'
              : 'Se actualizó la lista de integrantes de tu hogar.',
          onDone: () => Navigator.of(context).pop(),
        ),
      );
    }

    return AppSheet(
      title: title,
      body: _buildForm(),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nombre, edad y alergias son obligatorios para guardar.',
            style: AppText.nunito(14, 21, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          PrimaryButton(
            label: _isEditing ? 'Guardar cambios' : 'Guardar integrante',
            icon: AppIcons.check,
            onPressed: _canSave ? _save : null,
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    void refresh(String _) => setState(() {});

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
                required: true,
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
              for (final type in MemberType.values) ...[
                if (type != MemberType.values.first) const SizedBox(width: 8),
                Expanded(
                  child: _OptionButton(
                    label: type.label,
                    selected: _type == type,
                    onTap: () => setState(() => _type = type),
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
                  _OptionButton(
                    label: 'Ninguna',
                    selected: _noAllergies,
                    pill: true,
                    onTap: _selectNoAllergies,
                  ),
                  for (final allergy in allergyOptions)
                    _OptionButton(
                      label: allergy,
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

/// Botón seleccionable del formulario: tipo de integrante (rectangular) o
/// alergia ([pill]).
class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.pill = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool pill;

  @override
  Widget build(BuildContext context) {
    final side = BorderSide(
      color: selected ? AppColors.primary : AppColors.border,
      width: 2,
    );
    final ShapeBorder shape = pill
        ? StadiumBorder(side: side)
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: side,
          );

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.primarySoft : AppColors.surface,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: Container(
            constraints: BoxConstraints(minHeight: pill ? 44 : 48),
            padding: EdgeInsets.symmetric(horizontal: pill ? 16 : 8),
            alignment: pill ? null : Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: AppText.nunito(
                    15,
                    22.5,
                    weight: FontWeight.w700,
                    color: selected ? AppColors.primaryDark : AppColors.text,
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
