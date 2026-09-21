import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

const _fieldRadius = BorderRadius.all(Radius.circular(12));
const _disabledText = Color(0x805B6152);

OutlineInputBorder _border(Color color) => OutlineInputBorder(
  borderRadius: _fieldRadius,
  borderSide: BorderSide(color: color, width: 2),
);

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.autofillHints,
    this.obscureText = false,
    this.suffix,
    this.prefixText,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.focusNode,
    this.enabled = true,
    this.readOnly = false,
    this.minLines,
    this.maxLines = 1,
    this.maxLength,
  });

  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final Widget? suffix;

  /// Texto fijo antes del valor, p. ej. "$" en la cuota de recuperación.
  final String? prefixText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final FocusNode? focusNode;

  /// Deshabilitado: fondo gris y texto atenuado (p. ej. cuota "Exenta").
  final bool enabled;

  /// Solo lectura: útil para campos que abren un selector al tocarlos.
  final bool readOnly;
  final int? minLines;

  /// Más de 1 para áreas de texto (Notas, Justificación).
  final int? maxLines;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    final multiline = maxLines == null || maxLines! > 1;
    final textColor = enabled ? AppColors.text : _disabledText;

    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: multiline ? TextInputType.multiline : keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      inputFormatters: [
        if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
        ...?inputFormatters,
      ],
      autofillHints: autofillHints,
      obscureText: obscureText,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onTap: onTap,
      enabled: enabled,
      readOnly: readOnly,
      minLines: minLines,
      maxLines: obscureText ? 1 : maxLines,
      style: AppText.nunito(16, 24, color: textColor),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppText.nunito(16, 24, color: AppColors.hint),
        hintMaxLines: multiline ? 3 : 1,
        // prefixIcon (y no prefixText) para que el prefijo se vea siempre,
        // aunque el campo esté vacío o sin foco.
        prefixIcon: prefixText == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 12, right: 4),
                child: Text(
                  prefixText!,
                  style: AppText.nunito(
                    16,
                    24,
                    color: enabled ? AppColors.textMuted : _disabledText,
                  ),
                ),
              ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        filled: true,
        fillColor: enabled ? AppColors.surface : AppColors.background,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        suffixIcon: suffix,
        suffixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 40),
        border: _border(AppColors.border),
        enabledBorder: _border(AppColors.border),
        disabledBorder: _border(AppColors.border),
        focusedBorder: _border(AppColors.primary),
      ),
    );
  }
}

/// Etiqueta en negritas arriba de un campo, con asterisco rojo si es
/// obligatorio.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final style = AppText.nunito(15, 22.5, weight: FontWeight.w700);
    return Text.rich(
      TextSpan(
        text: text,
        style: style,
        children: [
          if (required)
            TextSpan(
              text: ' *',
              style: style.copyWith(color: AppColors.danger),
            ),
        ],
      ),
    );
  }
}

class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    this.required = false,
    required this.child,
  });

  final String label;
  final bool required;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(label, required: required),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
