import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// Botón seleccionable del diseño (tipo de integrante, alergias, estado de
/// entrega, "Exenta"). Rectangular con radio 12, o píldora con [pill].
/// Seleccionado: fondo verde claro, borde verde y texto verde oscuro.
class OptionButton extends StatelessWidget {
  const OptionButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.pill = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool pill;

  double get _horizontalPadding => pill ? 16 : 8;

  TextStyle get _labelStyle => AppText.nunito(
    15,
    22.5,
    weight: FontWeight.w700,
    color: selected ? AppColors.primaryDark : AppColors.text,
  );

  /// Ancho mínimo del botón para que ninguna palabra de [label] se parta,
  /// con la letra del sistema.
  double minWidth(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: _labelStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.minIntrinsicWidth;
    painter.dispose();
    return width + 2 * _horizontalPadding;
  }

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
            padding: EdgeInsets.symmetric(horizontal: _horizontalPadding),
            alignment: pill ? null : Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, textAlign: TextAlign.center, style: _labelStyle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opciones del mismo ancho en un renglón; si una etiqueta no cabe sin partir
/// una palabra (letra grande), van una debajo de otra a todo lo ancho.
class OptionButtonRow extends StatelessWidget {
  const OptionButtonRow({super.key, required this.options, this.spacing = 8});

  final List<OptionButton> options;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = options.length;
        final cell = (constraints.maxWidth - spacing * (count - 1)) / count;
        final fits =
            !cell.isFinite ||
            options.every((option) => option.minWidth(context) <= cell);
        if (fits) {
          return Row(
            children: [
              for (final (index, option) in options.indexed) ...[
                if (index > 0) SizedBox(width: spacing),
                Expanded(child: option),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, option) in options.indexed) ...[
              if (index > 0) SizedBox(height: spacing),
              option,
            ],
          ],
        );
      },
    );
  }
}
