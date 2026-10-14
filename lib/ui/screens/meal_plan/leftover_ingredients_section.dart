import 'package:flutter/material.dart';

import '../../formatting.dart';
import '../../models/expiration_urgency.dart';
import '../../models/recipe.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/pill.dart';

/// Lo que queda de la despensa después de cocinar el plan de comidas (ver
/// [planLeftovers]): los productos que sobran, primero los que caducan antes, y
/// los que el plan se come completos en una sola línea.
class LeftoverIngredientsSection extends StatelessWidget {
  const LeftoverIngredientsSection({
    super.key,
    required this.leftovers,
    required this.today,
  });

  final List<PlanLeftover> leftovers;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    // Sin productos vigentes no hay nada que repartir; el aviso de arriba del
    // plan ya dice que hace falta llenar la despensa.
    if (leftovers.isEmpty) return const SizedBox.shrink();

    final remaining = [
      for (final leftover in leftovers)
        if (leftover.status != LeftoverStatus.usedUp) leftover,
    ];
    // Una entrega por línea: el mismo producto puede estar en la despensa varias
    // veces. Se nombra una sola vez y solo si no le queda nada en ningún lote.
    final stillThere = {
      for (final leftover in remaining) _productKey(leftover.item.productId),
    };
    final usedUp = <String, String>{};
    for (final leftover in leftovers) {
      final key = _productKey(leftover.item.productId);
      if (leftover.status == LeftoverStatus.usedUp &&
          !stillThere.contains(key)) {
        usedUp.putIfAbsent(
          key,
          () => productDisplayName(leftover.item.productId),
        );
      }
    }
    final touchesNothing = leftovers.every(
      (leftover) => leftover.status == LeftoverStatus.untouched,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Lo que te sobra',
          style: AppText.baloo(20, 25, weight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          'Lo que queda de tu despensa después de cocinar tu plan. Lo que '
          'caduca primero va arriba.',
          style: AppText.nunito(14, 21, color: AppColors.textMuted),
        ),
        if (remaining.isEmpty) ...[
          const SizedBox(height: 12),
          const InfoBanner(
            message: 'Tu plan usa todo lo que hay en tu despensa.',
            background: AppColors.primarySoft,
            foreground: AppColors.primaryDark,
          ),
        ] else if (touchesNothing) ...[
          const SizedBox(height: 12),
          const InfoBanner(
            message: 'Tu plan no usa ningún producto de tu despensa.',
            background: AppColors.warningSoft,
            foreground: AppColors.warningText,
          ),
        ],
        for (final leftover in remaining) ...[
          const SizedBox(height: 12),
          _LeftoverCard(leftover: leftover, today: today),
        ],
        if (usedUp.isNotEmpty && remaining.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'El plan usa por completo: ${joinWithAnd(usedUp.values.toList())}.',
            style: AppText.nunito(14, 21, color: AppColors.textMuted),
          ),
        ],
      ],
    );
  }
}

/// Cuándo dos productos de la despensa son el mismo: igual nombre sin contar
/// mayúsculas ni espacios de las orillas, como en
/// [StandardBasket.deliveryItemsFor].
String _productKey(String productId) => productId.trim().toLowerCase();

class _LeftoverCard extends StatelessWidget {
  const _LeftoverCard({required this.leftover, required this.today});

  final PlanLeftover leftover;
  final DateTime today;

  static const _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(16)),
    side: BorderSide(color: AppColors.border),
  );

  @override
  Widget build(BuildContext context) {
    final item = leftover.item;
    final days = daysLeft(item, today: today);
    final urgency = ExpirationUrgency.fromDays(days);
    final usage = leftover.status == LeftoverStatus.untouched
        ? 'Tu plan no lo usa'
        : 'Tu plan usa ${formatAmount(leftover.used, item.unit)} de '
              '${formatAmount(item.quantity, item.unit)}';

    return Material(
      color: AppColors.surface,
      shape: _shape,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    productDisplayName(item.productId),
                    style: AppText.baloo(18, 22.5, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    remainingLabel(leftover.remaining, item.unit),
                    style: AppText.nunito(16, 24, weight: FontWeight.w700),
                  ),
                  Text(
                    usage,
                    style: AppText.nunito(14, 21, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Pill(
              label: expirationLabel(days),
              background: urgency.background,
              foreground: urgency.foreground,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              fontSize: 13,
              lineHeight: 19.5,
            ),
          ],
        ),
      ),
    );
  }
}
