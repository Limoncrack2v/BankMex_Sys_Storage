import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_text_field.dart';
import 'option_button.dart';

/// Campo de la cuota de recuperación con el botón "Exenta" a la derecha. Lo
/// usan el formulario de entregas y el de editar una familia.
class RecoveryQuotaField extends StatelessWidget {
  const RecoveryQuotaField({
    super.key,
    required this.controller,
    required this.exempt,
    required this.onToggleExempt,
    required this.onChanged,
    this.fieldKey,
    this.hint = '0',
    this.textInputAction = TextInputAction.next,
  });

  final TextEditingController controller;

  /// "Exenta" está seleccionada y el campo, deshabilitado.
  final bool exempt;
  final VoidCallback onToggleExempt;
  final ValueChanged<String> onChanged;

  /// Key del campo de texto, para encontrarlo en las pruebas.
  final Key? fieldKey;
  final String hint;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    final exemptButton = OptionButton(
      label: 'Exenta',
      selected: exempt,
      onTap: onToggleExempt,
    );
    // IntrinsicHeight: "Exenta" mide lo mismo que el campo, también con letra
    // grande.
    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(
            child: AppTextField(
              key: fieldKey,
              controller: controller,
              hint: hint,
              prefixText: r'$',
              enabled: !exempt,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: textInputAction,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              maxLength: 9,
              onChanged: onChanged,
            ),
          ),
          const SizedBox(width: 8),
          // 84 como en el diseño; con letra grande, lo que pida la palabra
          // para no partirse ("Exen ta").
          SizedBox(
            width: math.max(84, exemptButton.minWidth(context)),
            child: exemptButton,
          ),
        ],
      ),
    );
  }
}
