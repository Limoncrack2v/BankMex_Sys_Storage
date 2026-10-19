import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// Botón rojo de ancho completo para una acción que borra, cancela o rechaza.
/// Misma forma y tamaño que [PrimaryButton]; con [onPressed] nulo se ve
/// deshabilitado (gris).
class DangerButton extends StatelessWidget {
  const DangerButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  static const _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(16)),
  );

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final foreground = enabled ? Colors.white : AppColors.textMuted;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: enabled ? AppColors.danger : AppColors.border,
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
                    ? SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: foreground,
                        ),
                      )
                    : Text(
                        label,
                        textAlign: TextAlign.center,
                        style: AppText.nunito(
                          17,
                          25.5,
                          weight: FontWeight.w700,
                          color: foreground,
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
