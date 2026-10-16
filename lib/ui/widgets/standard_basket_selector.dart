import 'package:flutter/material.dart';

import '../../data/models/standard_basket.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'app_buttons.dart';
import 'app_text_field.dart';
import 'option_button.dart';
import 'pill.dart';

/// Despensas estándar que el staff puede elegir en el formulario de entregas
/// para llenar los productos. Solo dibuja: el estado y la lógica de llenado
/// están en el formulario.
class StandardBasketSelector extends StatelessWidget {
  const StandardBasketSelector({
    super.key,
    required this.baskets,
    required this.hasError,
    required this.selectedIds,
    required this.onToggle,
    this.message,
    this.problem,
    this.staleNotice = false,
    this.onRefill,
  });

  /// Las despensas del banco; null mientras cargan.
  final List<StandardBasket>? baskets;

  /// La carga falló (p. ej. sin conexión y sin copia en el dispositivo).
  final bool hasError;
  final Set<String> selectedIds;
  final ValueChanged<StandardBasket> onToggle;

  /// Aviso neutro bajo las opciones (qué falta, o con qué se llenó la lista).
  final String? message;

  /// Por qué no se pudieron llenar los productos.
  final String? problem;

  /// El staff ya editó los productos y la lista no se actualizó con el
  /// último cambio; [onRefill] la reemplaza.
  final bool staleNotice;
  final VoidCallback? onRefill;

  static const emptyMessage =
      'No hay despensas estándar disponibles. Si no tienes conexión, es '
      'posible que aún no se hayan descargado. Agrega los productos a mano.';
  static const errorMessage =
      'No se pudieron cargar las despensas estándar. Agrega los productos a '
      'mano.';
  static const staleMessage =
      'Los productos no se actualizaron porque ya los habías editado. '
      'Revisa la lista o reemplázala con las despensas elegidas.';

  @override
  Widget build(BuildContext context) {
    final baskets = this.baskets;
    final message = this.message;
    final problem = this.problem;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FieldLabel('Despensas estándar'),
        const SizedBox(height: 2),
        if (baskets == null && !hasError)
          const _Loading()
        else if (baskets == null)
          const _Note(errorMessage, color: AppColors.dangerText)
        else if (baskets.isEmpty)
          const _Note(emptyMessage)
        else ...[
          const _Note(
            'Llena los productos con lo que lleva cada despensa, por el '
            'número de despensas. Después puedes quitar o cambiar lo que '
            'haya faltado ese día.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final basket in baskets)
                OptionButton(
                  label: basket.name,
                  pill: true,
                  selected: selectedIds.contains(basket.basketId),
                  onTap: () => onToggle(basket),
                ),
            ],
          ),
        ],
        if (problem != null) ...[
          const SizedBox(height: 8),
          _Note(problem, color: AppColors.dangerText),
        ] else if (message != null) ...[
          const SizedBox(height: 8),
          _Note(message),
        ],
        if (staleNotice && problem == null) ...[
          const SizedBox(height: 12),
          const InfoBanner(
            message: staleMessage,
            background: AppColors.warningSoft,
            foreground: AppColors.warningText,
          ),
          const SizedBox(height: 8),
          SecondaryButton(label: 'Reemplazar productos', onPressed: onRefill),
        ],
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.color = AppColors.textMuted});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppText.nunito(14, 21, color: color));
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(child: _Note('Cargando despensas estándar…')),
      ],
    );
  }
}
