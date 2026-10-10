import 'package:flutter/material.dart';

import '../formatting.dart';
import '../theme/app_assets.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'app_icon.dart';

/// Aviso de la próxima entrega de BAMX para la familia. No muestra nada si no
/// hay una programada o si la fecha ya pasó (una entrega que el staff aún no
/// marca no debe aparecer como próxima).
///
/// Solo dibuja la fecha que recibe; quien la lee de Firestore es la pantalla
/// (families/{familyId}.nextDeliveryDate, que escribe syncNextDelivery).
class NextDeliveryBanner extends StatelessWidget {
  const NextDeliveryBanner({
    super.key,
    required this.date,
    this.today,
    this.margin = EdgeInsets.zero,
  });

  final DateTime? date;

  /// Para pruebas; por defecto, hoy.
  final DateTime? today;

  /// Espacio alrededor del aviso, solo cuando se muestra.
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final date = this.date;
    if (date == null) return const SizedBox.shrink();
    final days = daysUntil(date, today: today);
    if (days < 0) return const SizedBox.shrink();

    final when = switch (days) {
      0 => 'Hoy',
      1 => 'Mañana',
      _ => 'En $days días',
    };

    return Container(
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const AppIcon(AppIcons.truck, color: AppColors.primaryDark),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tu próxima entrega',
                  style: AppText.nunito(
                    15,
                    22.5,
                    weight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
                Text(
                  '${formatDateLong(date)} · $when',
                  style: AppText.nunito(14, 21, color: AppColors.primaryDark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
