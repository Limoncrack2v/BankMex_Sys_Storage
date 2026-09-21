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
