import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/models/pantry_item.dart';
import '../../../data/repositories/delivery_repository.dart';
import '../../../data/repositories/family_repository.dart';
import '../../../data/repositories/pantry_repository.dart';
import '../../formatting.dart';
import '../../models/program_stats.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/pill.dart';

/// Lee lo que necesitan las estadísticas: las entregas de este mes y del
/// anterior y, de cada familia, sus registros de consumo y su despensa. Son
/// lecturas puntuales (dos por familia), sin listeners, y del servidor: sin
/// conexión fallan y la pestaña lo avisa, en lugar de mostrar como totales lo
/// que haya en la caché.
Future<ProgramStats> loadProgramStats({DateTime? now}) async {
  // shortcut: cada visita a la pestaña vuelve a leer todas las familias y, de
  // cada una, su despensa y seis meses de registros (dos consultas por
  // familia). Con pocas familias está bien; con cientos, conviene que una
  // Cloud Function lleve totales por mes y que la pestaña lea solo esos.
  final clock = now ?? DateTime.now();
  final since = ProgramStats.windowStart(clock);
  final pantry = PantryRepository();
  final (families, deliveries) = await (
    FamilyRepository().getAllFamilies(),
    DeliveryRepository().getDeliveriesSince(
      ProgramStats.deliveriesStart(clock),
    ),
  ).wait;
  final perFamily = await Future.wait([
    for (final family in families)
      (
        pantry.getConsumptionLogs(family.familyId, since: since),
        pantry.getPantryItems(family.familyId),
      ).wait,
  ]);
  return ProgramStats.compute(
    deliveries: deliveries,
    logs: [for (final (logs, _) in perFamily) ...logs],
    pantryItems: [for (final (_, items) in perFamily) ...items],
    now: clock,
  );
}

/// Pestaña "Estadísticas" del staff: consumo y desperdicio del programa de
/// despensas (qué cuenta cada número está en [ProgramStats]). Se actualiza al
/// abrirla y al jalar hacia abajo.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, this.load = loadProgramStats});

  /// Solo para pruebas; por defecto [loadProgramStats].
  final Future<ProgramStats> Function() load;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  ProgramStats? _stats;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final stats = await widget.load();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _retry() {
    setState(() => _failed = false);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _reload,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Estadísticas', style: AppText.baloo(22, 27.5)),
            const SizedBox(height: 2),
            Text(
              'Consumo y desperdicio del programa de despensas.',
              style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 24),
            if (_failed) ...[
              const InfoBanner(
                message:
                    'No se pudieron cargar las estadísticas. Revisa tu '
                    'conexión e intenta de nuevo.',
                background: AppColors.dangerSoft,
                foreground: AppColors.dangerText,
              ),
              const SizedBox(height: 12),
              SecondaryButton(label: 'Reintentar', onPressed: _retry),
              const SizedBox(height: 24),
            ],
            if (stats != null)
              _StatsBody(stats: stats)
            else if (!_failed)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatsBody extends StatelessWidget {
  const _StatsBody({required this.stats});

  final ProgramStats stats;

  @override
  Widget build(BuildContext context) {
    final before = _previousPeriodLabel(stats);
    final total = stats.consumedKg + stats.wastedKg;
    final consumedShare = total == 0
        ? 0
        : (stats.consumedKg / total * 100).round();
    final first = stats.months.first.month;
    final last = stats.months.last.month;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Caption('Este mes · ${_currentPeriodLabel(stats.now)}'),
        const SizedBox(height: 8),
        _MetricRow(
          left: _MetricCard(
            label: 'Familias atendidas',
            value: formatInteger(stats.familiesServed),
            note: _countChange(
              stats.familiesServed,
              stats.familiesServedBefore,
              before,
            ),
          ),
          right: _MetricCard(
            label: 'Despensas entregadas',
            value: formatInteger(stats.packagesDelivered),
            note: _percentChange(
              stats.packagesDelivered,
              stats.packagesDeliveredBefore,
              before,
            ),
          ),
        ),
        const SizedBox(height: 24),
        _Caption(
          'Últimos ${ProgramStats.monthsShown} meses · '
          '${monthShort(first)}–${monthShort(last)}',
        ),
        const SizedBox(height: 8),
        _MetricRow(
          left: _MetricCard(
            label: 'Kg aprovechados',
            value: formatKg(stats.consumedKg),
            note: total == 0 ? 'Sin registros' : '$consumedShare% del total',
          ),
          right: _MetricCard(
            label: 'Kg desperdiciados',
            value: formatKg(stats.wastedKg),
            note: total == 0
                ? 'Sin registros'
                : '${100 - consumedShare}% del total',
          ),
        ),
        const SizedBox(height: 16),
        _ConsumptionChart(stats: stats),
        const SizedBox(height: 32),
        _Trends(stats: stats),
      ],
    );
  }
}

/// "Del 1 al 13 de oct", o "Hoy, 1 de oct" el primer día del mes.
String _currentPeriodLabel(DateTime now) => now.day == 1
    ? 'hoy, 1 de ${monthShort(now)}'
    : 'del 1 al ${now.day} de ${monthShort(now)}';

/// Los mismos días del mes anterior: "1–13 sep", o "1 sep". Con espacio
/// que no se corta y sin corte después del guion (U+2060), para que la fecha
/// no quede partida en dos renglones.
String _previousPeriodLabel(ProgramStats stats) {
  final end = stats.comparedUntil;
  return end.day == 1
      ? '1\u00a0${monthShort(end)}'
      : '1–\u2060${end.day}\u00a0${monthShort(end)}';
}

String _countChange(int now, int before, String period) {
  final diff = now - before;
  if (diff == 0) return 'Igual que $period';
  return '${diff > 0 ? '+' : '−'}${diff.abs()} vs.\u00a0$period';
}

String _percentChange(int now, int before, String period) {
  if (before == 0) return 'Sin entregas en $period';
  final percent = ((now - before) / before * 100).round();
  if (percent == 0) return 'Igual que $period';
  return '${percent > 0 ? '+' : '−'}${percent.abs()}% vs.\u00a0$period';
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: AppText.nunito(15, 22.5, weight: FontWeight.w700));
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: 12),
          Expanded(child: right),
        ],
      ),
    );
  }
}

/// Tarjeta de métrica del panel (MetricCard del Make).
class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.note,
  });

  final String label;
  final String value;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppText.nunito(
              15,
              21,
              weight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: AppText.baloo(30, 36)),
          const Spacer(),
          const SizedBox(height: 8),
          Text(
            note,
            style: AppText.nunito(
              14,
              20,
              weight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

final _cardDecoration = BoxDecoration(
  color: AppColors.surface,
  border: Border.all(color: AppColors.border),
  borderRadius: BorderRadius.circular(16),
);

/// "Consumo vs. desperdicio (kg por mes)": barras apiladas, consumido abajo y
/// desperdicio arriba. Al tocar un mes, sus valores exactos aparecen arriba
/// de la gráfica; por omisión, el mes actual.
class _ConsumptionChart extends StatefulWidget {
  const _ConsumptionChart({required this.stats});

  final ProgramStats stats;

  @override
  State<_ConsumptionChart> createState() => _ConsumptionChartState();
}

class _ConsumptionChartState extends State<_ConsumptionChart> {
  late int _selected = widget.stats.months.length - 1;

  @override
  Widget build(BuildContext context) {
    final months = widget.stats.months;
    final selected = months[_selected];
    final empty = months.every((m) => m.consumedKg == 0 && m.wastedKg == 0);
    final unweighed = widget.stats.unweighed;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Consumo vs. desperdicio (kg por mes)',
            style: AppText.baloo(19, 24),
          ),
          const SizedBox(height: 12),
          if (empty)
            Text(
              'Aún no hay consumo ni desperdicio registrado en estos meses.',
              style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
            )
          else ...[
            _MonthReadout(month: selected),
            const SizedBox(height: 16),
            _BarChart(
              months: months,
              selected: _selected,
              onSelect: (index) => setState(() => _selected = index),
            ),
            const SizedBox(height: 16),
            const Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                _LegendItem(
                  color: AppColors.chartConsumed,
                  label: 'Consumido (kg)',
                ),
                _LegendItem(
                  color: AppColors.chartWasted,
                  label: 'Desperdicio (kg)',
                ),
              ],
            ),
          ],
          if (unweighed.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _unweighedNote(unweighed),
              style: AppText.nunito(14, 20, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// "No incluye 12 piezas y 3 latas, que no tienen peso registrado."
String _unweighedNote(Map<FoodUnit, double> unweighed) {
  final parts = [
    for (final unit in FoodUnit.values)
      if (unweighed[unit] case final quantity?) formatAmount(quantity, unit),
  ];
  final list = parts.length == 1
      ? parts.single
      : '${parts.sublist(0, parts.length - 1).join(', ')} y ${parts.last}';
  return 'No incluye $list, que no tienen peso registrado.';
}

class _MonthReadout extends StatelessWidget {
  const _MonthReadout({required this.month});

  final MonthlyKg month;

  @override
  Widget build(BuildContext context) {
    final style = AppText.nunito(15, 22.5, weight: FontWeight.w600);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${monthShort(month.month)} ${month.month.year}',
          style: AppText.nunito(15, 22.5, weight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            _LegendItem(
              color: AppColors.chartConsumed,
              label: '${formatKg(month.consumedKg)} kg consumidos',
              style: style,
            ),
            _LegendItem(
              color: AppColors.chartWasted,
              label: '${formatKg(month.wastedKg)} kg desperdiciados',
              style: style,
            ),
          ],
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label, this.style});

  final Color color;
  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style:
              style ??
              AppText.nunito(
                14,
                20,
                weight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
        ),
      ],
    );
  }
}

class _BarChart extends StatelessWidget {
  const _BarChart({
    required this.months,
    required this.selected,
    required this.onSelect,
  });

  final List<MonthlyKg> months;
  final int selected;
  final ValueChanged<int> onSelect;

  static const _plotHeight = 160.0;
  static const _axisWidth = 44.0;

  @override
  Widget build(BuildContext context) {
    final maxKg = _niceMax(
      months.fold<double>(
        0,
        (max, m) => math.max(max, m.consumedKg + m.wastedKg),
      ),
    );
    final labelStyle = AppText.nunito(
      12,
      16,
      weight: FontWeight.w600,
      color: AppColors.textMuted,
    );

    return Column(
      children: [
        SizedBox(
          height: _plotHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: ExcludeSemantics(
                  child: CustomPaint(
                    painter: _BarsPainter(
                      months: months,
                      maxKg: maxKg,
                      selected: selected,
                      axisWidth: _axisWidth,
                      labelStyle: labelStyle,
                    ),
                  ),
                ),
              ),
              // Áreas de toque más grandes que las barras, una por mes.
              Positioned.fill(
                left: _axisWidth,
                child: Row(
                  children: [
                    for (final (index, month) in months.indexed)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: index == selected,
                          label:
                              '${monthShort(month.month)} ${month.month.year}: '
                              '${formatKg(month.consumedKg)} kg consumidos, '
                              '${formatKg(month.wastedKg)} kg desperdiciados',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onSelect(index),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.only(left: _axisWidth),
            child: Row(
              children: [
                for (final (index, month) in months.indexed)
                  Expanded(
                    child: Text(
                      monthShort(month.month),
                      textAlign: TextAlign.center,
                      style: index == selected
                          ? labelStyle.copyWith(
                              color: AppColors.text,
                              fontWeight: FontWeight.w700,
                            )
                          : labelStyle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Tope "redondo" del eje: 1, 2, 2.5 o 5 por una potencia de 10.
double _niceMax(double value) {
  if (value <= 0) return 1;
  final magnitude = math
      .pow(10, (math.log(value) / math.ln10).floor())
      .toDouble();
  for (final step in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
    if (value <= step * magnitude) return step * magnitude;
  }
  return 10 * magnitude;
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.months,
    required this.maxKg,
    required this.selected,
    required this.axisWidth,
    required this.labelStyle,
  });

  final List<MonthlyKg> months;
  final double maxKg;
  final int selected;
  final double axisWidth;
  final TextStyle labelStyle;

  static const _top = 8.0;
  static const _radius = Radius.circular(4);

  /// Separación del color de la superficie entre consumido y desperdicio.
  static const _gap = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final bottom = size.height;
    final plotHeight = bottom - _top;
    final step = (size.width - axisWidth) / months.length;
    final barWidth = math.min(28.0, step * 0.5);
    double heightOf(double kg) =>
        kg <= 0 ? 0 : math.max(2, kg / maxKg * plotHeight);

    // Fondo del mes elegido.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(axisWidth + step * selected + 2, 0, step - 4, bottom),
        const Radius.circular(8),
      ),
      Paint()..color = AppColors.background,
    );

    // Líneas guía en 0, la mitad y el tope, con su valor a la izquierda.
    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (final kg in [0.0, maxKg / 2, maxKg]) {
      final y = bottom - kg / maxKg * plotHeight;
      canvas.drawLine(Offset(axisWidth, y), Offset(size.width, y), grid);
      final label = TextPainter(
        text: TextSpan(text: formatKg(kg), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: axisWidth - 8);
      label.paint(
        canvas,
        Offset(axisWidth - 8 - label.width, y - label.height / 2),
      );
    }

    for (final (index, month) in months.indexed) {
      final left = axisWidth + step * index + (step - barWidth) / 2;
      final consumed = heightOf(month.consumedKg);
      final wasted = heightOf(month.wastedKg);

      if (consumed > 0) {
        final rect = Rect.fromLTWH(left, bottom - consumed, barWidth, consumed);
        canvas.drawRRect(
          wasted > 0
              ? RRect.fromRectAndRadius(rect, Radius.zero)
              : RRect.fromRectAndCorners(
                  rect,
                  topLeft: _radius,
                  topRight: _radius,
                ),
          Paint()..color = AppColors.chartConsumed,
        );
      }
      if (wasted > 0) {
        final base = bottom - consumed - (consumed > 0 ? _gap : 0);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(left, base - wasted, barWidth, wasted),
            topLeft: _radius,
            topRight: _radius,
          ),
          Paint()..color = AppColors.chartWasted,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.months != months || old.maxKg != maxKg || old.selected != selected;
}

class _Trends extends StatelessWidget {
  const _Trends({required this.stats});

  final ProgramStats stats;

  @override
  Widget build(BuildContext context) {
    final trends = stats.trends;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Tendencias de consumo', style: AppText.baloo(19, 24)),
        const SizedBox(height: 2),
        Text(
          '${_capitalize(_currentPeriodLabel(stats.now))} contra '
          '${_previousPeriodLabel(stats)}.',
          style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
        ),
        const SizedBox(height: 12),
        if (trends.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration.copyWith(color: AppColors.background),
            child: Text(
              'Todavía no hay productos consumidos en los dos periodos para '
              'comparar.',
              style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
            ),
          )
        else
          for (final (index, trend) in trends.indexed) ...[
            if (index > 0) const SizedBox(height: 12),
            _TrendCard(trend: trend),
          ],
      ],
    );
  }
}

/// Cantidad redondeada como los kilos de las tarjetas: desde 100 sin
/// decimales y abajo con uno ("68.4 kg", "120 kg", "3 latas").
String _roundedAmount(double quantity, FoodUnit unit) => formatAmount(
  quantity >= 100 ? quantity.roundToDouble() : (quantity * 10).round() / 10,
  unit,
);

String _capitalize(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.trend});

  final ProductTrend trend;

  @override
  Widget build(BuildContext context) {
    final percent = trend.changePercent;
    final (arrow, meaning) = percent > 0
        ? ('↑', 'subió')
        : percent < 0
        ? ('↓', 'bajó')
        : ('=', 'sin cambio');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productDisplayName(trend.productId),
                  style: AppText.nunito(16, 24, weight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_roundedAmount(trend.current, trend.unit)} ahora · '
                  '${_roundedAmount(trend.previous, trend.unit)} antes',
                  style: AppText.nunito(14, 20, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Semantics(
            label: percent == 0 ? meaning : '$meaning ${percent.abs()}%',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$arrow ${percent.abs()}%',
                style: AppText.baloo(16, 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
