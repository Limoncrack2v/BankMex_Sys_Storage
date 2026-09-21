import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'app_icon.dart';

const _buttonShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(16)),
);

/// Botón verde de ancho completo. Con [onPressed] nulo se muestra deshabilitado
/// (gris), como en el Figma.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
  });

  final String label;
  final String? icon;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final foreground = enabled ? Colors.white : AppColors.textMuted;

    return SizedBox(
      width: double.infinity,
      child: Material(
        color: enabled ? AppColors.primary : AppColors.border,
        shape: _buttonShape,
        child: InkWell(
          onTap: loading ? null : onPressed,
          customBorder: _buttonShape,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              child: loading
                  ? Center(
                      child: SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: foreground,
                        ),
                      ),
                    )
                  : _ButtonContent(
                      label: label,
                      icon: icon,
                      color: foreground,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Botón blanco con borde verde (p. ej. "Agregar integrante").
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
  });

  final String label;
  final String? icon;
  final VoidCallback? onPressed;

  static const _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(16)),
    side: BorderSide(color: AppColors.primary, width: 2),
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: AppColors.surface,
        shape: _shape,
        child: InkWell(
          onTap: onPressed,
          customBorder: _shape,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              child: _ButtonContent(
                label: label,
                icon: icon,
                color: AppColors.primaryDark,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Enlace verde subrayado (p. ej. "¿Olvidaste tu contraseña?").
class TextLinkButton extends StatelessWidget {
  const TextLinkButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

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
          style: AppText.nunito(
            15,
            22.5,
            weight: FontWeight.w700,
            color: AppColors.primaryDark,
          ).copyWith(
            decoration: TextDecoration.underline,
            decorationColor: AppColors.primaryDark,
          ),
        ),
      ),
    );
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({required this.label, this.icon, required this.color});

  final String label;
  final String? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          AppIcon(icon!, size: 20, color: color),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppText.nunito(
              17,
              25.5,
              weight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
