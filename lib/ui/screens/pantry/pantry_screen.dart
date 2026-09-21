import 'package:flutter/material.dart';

import '../../models/expiration_urgency.dart';
import '../../models/pantry_product.dart';
import '../../sample_data.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/coming_soon.dart';
import '../../widgets/pill.dart';

/// Despensa activa, ordenada por lo que caduca primero.
class PantryScreen extends StatelessWidget {
  const PantryScreen({super.key, this.products = SampleData.pantry});

  final List<PantryProduct> products;

  @override
  Widget build(BuildContext context) {
    final sorted = [...products]
      ..sort((a, b) => a.daysUntilExpiration.compareTo(b.daysUntilExpiration));
    final expiringSoon = sorted
        .where((p) => p.urgency != ExpirationUrgency.fresh)
        .length;

    return Column(
      children: [
        const AppHeader(title: 'Despensa'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (expiringSoon > 0) ...[
                InfoBanner(
                  message: expiringSoon == 1
                      ? '1 producto caduca pronto. ¡Úsalo primero!'
                      : '$expiringSoon productos caducan pronto. ¡Úsalos primero!',
                  background: AppColors.warningSoft,
                  foreground: AppColors.warningText,
                ),
                const SizedBox(height: 12),
              ],
              PrimaryButton(
                label: 'Registrar consumo',
                icon: AppIcons.check,
                onPressed: () => showComingSoon(context),
              ),
              if (sorted.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(
                    'Tu despensa está vacía.',
                    textAlign: TextAlign.center,
                    style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
                  ),
                ),
              for (final product in sorted) ...[
                const SizedBox(height: 12),
                _ProductCard(product),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard(this.product);

  final PantryProduct product;

  @override
  Widget build(BuildContext context) {
    final urgency = product.urgency;

    // Borde izquierdo de 8 px y 1 px en los demás lados, como en el Figma.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: urgency.accent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 1, 1, 1),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.horizontal(
              left: Radius.elliptical(8, 15),
              right: Radius.circular(15),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: AppText.baloo(
                            19,
                            23.75,
                            weight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          product.category,
                          style: AppText.nunito(
                            15,
                            22.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Pill(
                    label: _expirationLabel(product.daysUntilExpiration),
                    icon: AppIcons.urgencyClock,
                    iconSize: 14,
                    gap: 4,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    fontSize: 13,
                    lineHeight: 19.5,
                    background: urgency.background,
                    foreground: urgency.foreground,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Quedan ${product.remaining}',
                      style: AppText.nunito(16, 24, weight: FontWeight.w700),
                    ),
                  ),
                  Tooltip(
                    message: product.synchronized
                        ? 'Sincronizado'
                        : 'Pendiente de sincronizar',
                    child: AppIcon(
                      product.synchronized
                          ? AppIcons.cloudSynced
                          : AppIcons.cloudPending,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _expirationLabel(int days) => switch (days) {
  < 0 => 'Caducado',
  0 => 'Caduca hoy',
  1 => 'Caduca mañana',
  _ => 'Caduca en $days días',
};
