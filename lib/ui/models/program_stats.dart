import 'dart:math' as math;

import '../../data/models/consumption_log.dart';
import '../../data/models/delivery.dart';
import '../../data/models/pantry_item.dart';

/// Kilos de [quantity] en [unit], o null si la unidad no se puede pesar:
/// piezas, latas y paquetes no guardan su peso. Un litro cuenta como un kilo.
double? kilograms(double quantity, FoodUnit unit) => switch (unit) {
  FoodUnit.kg || FoodUnit.l => quantity,
  FoodUnit.g || FoodUnit.ml => quantity / 1000,
  FoodUnit.piece || FoodUnit.can || FoodUnit.pack => null,
};

/// Kilos consumidos y desperdiciados en un mes.
class MonthlyKg {
  const MonthlyKg({
    required this.month,
    required this.consumedKg,
    required this.wastedKg,
  });

  /// Primer día del mes.
  final DateTime month;
  final double consumedKg;
  final double wastedKg;
}

/// Consumo de un producto en lo que va del mes contra los mismos días del
/// mes anterior, en la unidad del producto.
class ProductTrend {
  const ProductTrend({
    required this.productId,
    required this.unit,
    required this.current,
    required this.previous,
  });

  final String productId;
  final FoodUnit unit;
  final double current;

  /// Siempre mayor a 0: sin consumo en el periodo anterior no hay con qué
  /// comparar.
  final double previous;

  /// Porcentaje redondeado; negativo si bajó.
  int get changePercent => ((current - previous) / previous * 100).round();
}

/// Estadísticas del programa para la pestaña "Estadísticas" del staff:
///
/// - "Este mes" va del día 1 a hoy y se compara con los mismos días del mes
///   anterior, para que un mes a medias no parezca una caída.
/// - Consumo: registros de consumptionLogs con reason consumed, en el mes en
///   que se registraron.
/// - Desperdicio: registros con reason expired, más lo que sigue en una
///   despensa ya caducado, en el mes en que caducó.
/// - Los kilos salen de kg y g; L y mL cuentan como kilos. Piezas, latas y
///   paquetes no tienen peso y se reportan aparte en [unweighed].
class ProgramStats {
  const ProgramStats({
    required this.now,
    required this.familiesServed,
    required this.familiesServedBefore,
    required this.packagesDelivered,
    required this.packagesDeliveredBefore,
    required this.months,
    required this.trends,
    required this.unweighed,
  });

  /// Meses de la gráfica, contando el actual.
  static const monthsShown = 6;

  /// Primer día del mes más antiguo de la gráfica.
  static DateTime windowStart(DateTime now) =>
      DateTime(now.year, now.month - (monthsShown - 1));

  /// Primer día del mes anterior: las entregas solo cuentan para este mes y
  /// los mismos días del anterior, así que no hace falta leer más atrás.
  static DateTime deliveriesStart(DateTime now) => _previousPeriod(now).start;

  final DateTime now;

  /// Familias con al menos una entrega entregada este mes, y en los mismos
  /// días del mes anterior.
  final int familiesServed;
  final int familiesServedBefore;

  /// Despensas de las entregas entregadas este mes, y en los mismos días del
  /// mes anterior.
  final int packagesDelivered;
  final int packagesDeliveredBefore;

  /// Los [monthsShown] meses, del más antiguo al actual.
  final List<MonthlyKg> months;

  /// Los productos que más cambiaron, de mayor a menor cambio.
  final List<ProductTrend> trends;

  /// Lo que no entra en los kilos de la gráfica (piezas, latas, paquetes):
  /// cantidad por unidad, consumida o desperdiciada.
  final Map<FoodUnit, double> unweighed;

  double get consumedKg => months.fold(0, (sum, m) => sum + m.consumedKg);
  double get wastedKg => months.fold(0, (sum, m) => sum + m.wastedKg);

  /// Último día del periodo anterior con el que se compara (el mismo día del
  /// mes, o el último si el mes anterior es más corto).
  DateTime get comparedUntil =>
      _previousPeriod(now).end.subtract(const Duration(days: 1));

  factory ProgramStats.compute({
    required List<Delivery> deliveries,
    required List<ConsumptionLog> logs,
    required List<PantryItem> pantryItems,
    required DateTime now,
    int maxTrends = 6,
  }) {
    final current = _currentPeriod(now);
    final previous = _previousPeriod(now);
    final start = windowStart(now);

    final delivered = deliveries.where(
      (d) => d.status == DeliveryStatus.delivered,
    );
    Iterable<Delivery> deliveredIn(_Period period) =>
        delivered.where((d) => period.contains(d.deliveryDate));
    int packagesIn(_Period period) =>
        deliveredIn(period).fold(0, (sum, d) => sum + d.packages);

    final consumed = List<double>.filled(monthsShown, 0);
    final wasted = List<double>.filled(monthsShown, 0);
    final unweighed = <FoodUnit, double>{};
    int? monthIndex(DateTime date) {
      if (date.isBefore(start) || !date.isBefore(current.end)) return null;
      return (date.year - start.year) * 12 + date.month - start.month;
    }

    void add(DateTime date, double quantity, FoodUnit unit, bool isWaste) {
      final index = monthIndex(date);
      if (index == null) return;
      final kg = kilograms(quantity, unit);
      if (kg == null) {
        unweighed[unit] = (unweighed[unit] ?? 0) + quantity;
      } else if (isWaste) {
        wasted[index] += kg;
      } else {
        consumed[index] += kg;
      }
    }

    for (final log in logs) {
      add(log.at, log.quantity, log.unit, log.wasted);
    }
    for (final item in pantryItems) {
      if (item.quantity <= 0 || item.daysLeftOn(now) >= 0) continue;
      final received = item.localTimestamp;
      final expires = DateTime(
        received.year,
        received.month,
        received.day + item.daysUntilExpiration,
      );
      add(expires, item.quantity, item.unit, true);
    }

    return ProgramStats(
      now: now,
      familiesServed: deliveredIn(current)
          .map((d) => d.familyId)
          .toSet()
          .length,
      familiesServedBefore: deliveredIn(previous)
          .map((d) => d.familyId)
          .toSet()
          .length,
      packagesDelivered: packagesIn(current),
      packagesDeliveredBefore: packagesIn(previous),
      months: [
        for (var i = 0; i < monthsShown; i++)
          MonthlyKg(
            month: DateTime(start.year, start.month + i),
            consumedKg: consumed[i],
            wastedKg: wasted[i],
          ),
      ],
      trends: _trends(logs, current, previous, maxTrends),
      unweighed: unweighed,
    );
  }

  static List<ProductTrend> _trends(
    List<ConsumptionLog> logs,
    _Period current,
    _Period previous,
    int maxTrends,
  ) {
    final byProduct =
        <
          String,
          ({String productId, FoodUnit unit, double now, double before})
        >{};
    for (final log in logs) {
      if (log.wasted) continue;
      final inCurrent = current.contains(log.at);
      if (!inCurrent && !previous.contains(log.at)) continue;
      final key = '${log.productId.trim().toLowerCase()}|${log.unit.name}';
      final entry =
          byProduct[key] ??
          (productId: log.productId, unit: log.unit, now: 0.0, before: 0.0);
      byProduct[key] = inCurrent
          ? (
              productId: entry.productId,
              unit: entry.unit,
              now: entry.now + log.quantity,
              before: entry.before,
            )
          : (
              productId: entry.productId,
              unit: entry.unit,
              now: entry.now,
              before: entry.before + log.quantity,
            );
    }

    final trends = [
      for (final entry in byProduct.values)
        if (entry.before > 0)
          ProductTrend(
            productId: entry.productId,
            unit: entry.unit,
            current: entry.now,
            previous: entry.before,
          ),
    ];
    trends.sort((a, b) {
      final byChange = b.changePercent.abs().compareTo(a.changePercent.abs());
      return byChange != 0
          ? byChange
          : a.productId.toLowerCase().compareTo(b.productId.toLowerCase());
    });
    return trends.take(maxTrends).toList();
  }

  /// Del día 1 del mes a hoy (incluido).
  static _Period _currentPeriod(DateTime now) => _Period(
    DateTime(now.year, now.month),
    DateTime(now.year, now.month, now.day + 1),
  );

  /// Los mismos días del mes anterior: del 1 al mismo día de hoy, o hasta el
  /// último día si ese mes es más corto.
  static _Period _previousPeriod(DateTime now) {
    final start = DateTime(now.year, now.month - 1);
    final lastDay = DateTime(start.year, start.month + 1, 0).day;
    return _Period(
      start,
      DateTime(start.year, start.month, math.min(now.day, lastDay) + 1),
    );
  }
}

/// [start] incluido, [end] no.
class _Period {
  const _Period(this.start, this.end);

  final DateTime start;
  final DateTime end;

  bool contains(DateTime date) => !date.isBefore(start) && date.isBefore(end);
}
