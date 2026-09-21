import 'package:flutter/material.dart';

import '../../../data/models/pantry_item.dart';
import '../../../data/repositories/pantry_repository.dart';
import '../../formatting.dart';
import '../../models/expiration_urgency.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/pill.dart';
import 'consumption_sheet.dart';

typedef _PantryRow = ({PantryItem item, bool pendingSync});

/// Despensa activa de la familia, ordenada por lo que caduca primero.
class PantryScreen extends StatefulWidget {
  const PantryScreen({super.key, required this.familyId});

  final String familyId;

  @override
  State<PantryScreen> createState() => _PantryScreenState();
}

class _PantryScreenState extends State<PantryScreen> {
  late Stream<List<_PantryRow>> _items;

  @override
  void initState() {
    super.initState();
    _items = _watchItems();
  }

  @override
  void didUpdateWidget(PantryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.familyId != widget.familyId) _items = _watchItems();
  }

  // Con los metadatos de cada documento se sabe si un cambio (p. ej. un
  // consumo registrado sin conexión) sigue pendiente de llegar al servidor.
  Stream<List<_PantryRow>> _watchItems() =>
      PantryRepository().watchPantryWithSyncStatus(widget.familyId);

  void _retry() => setState(() => _items = _watchItems());

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AppHeader(title: 'Despensa'),
        Expanded(
          child: StreamBuilder<List<_PantryRow>>(
            stream: _items,
            builder: (context, snapshot) {
              final waiting =
                  snapshot.connectionState == ConnectionState.waiting;
              if (snapshot.hasError && !waiting) {
                return _PantryError(onRetry: _retry);
              }
              final rows = snapshot.data;
              if (rows == null) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                );
              }
              return _PantryList(
                entries: _sortedEntries(rows),
                onRegisterConsumption: (items) => showConsumptionSheet(
                  context,
                  familyId: widget.familyId,
                  items: items,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

List<_PantryEntry> _sortedEntries(List<_PantryRow> rows) {
  final today = DateTime.now();
  return [
    for (final (:item, :pendingSync) in rows)
      _PantryEntry(item, today, pendingSync: pendingSync),
  ]..sort((a, b) {
    final byDays = a.days.compareTo(b.days);
    if (byDays != 0) return byDays;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
}

class _PantryEntry {
  _PantryEntry(this.item, DateTime today, {required this.pendingSync})
    : name = productDisplayName(item.productId),
      days = daysLeft(item, today: today);

  final PantryItem item;
  final String name;
  final int days;

  /// Tiene cambios en el dispositivo que aún no llegan al servidor.
  final bool pendingSync;

  ExpirationUrgency get urgency => ExpirationUrgency.fromDays(days);
}

class _PantryList extends StatelessWidget {
  const _PantryList({
    required this.entries,
    required this.onRegisterConsumption,
  });

  final List<_PantryEntry> entries;
  final ValueChanged<List<PantryItem>> onRegisterConsumption;

  @override
  Widget build(BuildContext context) {
    // Los caducados (días < 0) van en su propio aviso: no se debe invitar a
    // "usarlos primero".
    final expired = entries.where((e) => e.days < 0).length;
    final expiringSoon = entries
        .where((e) => e.days >= 0 && e.urgency != ExpirationUrgency.fresh)
        .length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (expired > 0) ...[
          InfoBanner(
            message: expired == 1
                ? '1 producto ya caducó. Revísalo antes de consumirlo.'
                : '$expired productos ya caducaron. Revísalos antes de '
                      'consumirlos.',
            background: AppColors.dangerSoft,
            foreground: AppColors.dangerText,
          ),
          const SizedBox(height: 12),
        ],
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
          onPressed: entries.isEmpty
              ? null
              : () => onRegisterConsumption([for (final e in entries) e.item]),
        ),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(
              'Tu despensa está vacía. Cuando BAMX registre una entrega, '
              'tus productos aparecerán aquí.',
              textAlign: TextAlign.center,
              style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
            ),
          ),
        for (final entry in entries) ...[
          const SizedBox(height: 12),
          _ProductCard(entry),
        ],
      ],
    );
  }
}

class _PantryError extends StatelessWidget {
  const _PantryError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const InfoBanner(
          message:
              'No pudimos cargar tu despensa. Revisa tu conexión e intenta '
              'de nuevo.',
          background: AppColors.dangerSoft,
          foreground: AppColors.dangerText,
        ),
        const SizedBox(height: 12),
        Center(
          child: TextLinkButton(label: 'Reintentar', onPressed: onRetry),
        ),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard(this.entry);

  final _PantryEntry entry;

  @override
  Widget build(BuildContext context) {
    final item = entry.item;
    final urgency = entry.urgency;

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
                          entry.name,
                          style: AppText.baloo(
                            19,
                            23.75,
                            weight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          foodTypeLabel(item.type),
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
                    label: expirationLabel(entry.days),
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
                      remainingLabel(item.quantity, item.unit),
                      style: AppText.nunito(16, 24, weight: FontWeight.w700),
                    ),
                  ),
                  Tooltip(
                    message: entry.pendingSync
                        ? 'Pendiente de sincronizar'
                        : 'Sincronizado',
                    child: AppIcon(
                      entry.pendingSync
                          ? AppIcons.cloudPending
                          : AppIcons.cloudSynced,
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
