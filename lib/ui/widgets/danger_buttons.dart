import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// Botón rojo de ancho completo para confirmar una acción que no se puede
/// deshacer. Misma forma y tamaño que [PrimaryButton].
class DangerButton extends StatelessWidget {
  const DangerButton({
    super.key,
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
/// Mide 48 dp de alto. Con [onPressed] nulo no responde (p. ej. mientras se
/// guarda).
class DangerLinkButton extends StatelessWidget {
  const DangerLinkButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Lo que lee TalkBack si [label] no basta, p. ej. con la fecha.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      enabled: onPressed != null,
      label: semanticLabel ?? label,
      onTap: onPressed,
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              widthFactor: 1,
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
          ),
        ),
      ),
    );
  }
}
