import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/consumption_log.dart';
import 'package:bank_storage_app/data/models/delivery.dart';
import 'package:bank_storage_app/data/models/pantry_item.dart';
import 'package:bank_storage_app/ui/models/program_stats.dart';

// "Hoy" en todas las pruebas: 13 de octubre de 2026, a media tarde.
final now = DateTime(2026, 10, 13, 16);

Delivery delivery(
  String familyId,
  DateTime date, {
  int packages = 1,
  DeliveryStatus status = DeliveryStatus.delivered,
}) => Delivery(
  deliveryId: 'd-$familyId-${date.toIso8601String()}',
  familyId: familyId,
  familyName: familyId,
  deliveryDate: date,
  packages: packages,
  status: status,
  items: const [],
  createdAt: date,
);

ConsumptionLog log(
  String productId,
  double quantity,
  FoodUnit unit,
  DateTime at, {
  bool wasted = false,
}) => ConsumptionLog(
  productId: productId,
  quantity: quantity,
  unit: unit,
  type: FoodType.grain,
  at: at,
  reason: wasted ? ConsumptionReason.expired : ConsumptionReason.consumed,
);

PantryItem pantryItem(
  double quantity,
  FoodUnit unit, {
  required DateTime received,
  required int daysUntilExpiration,
}) => PantryItem(
  pantryItemId: 'p',
  productId: 'Leche entera',
  deliveryId: 'd',
  type: FoodType.dairy,
  quantity: quantity,
  unit: unit,
  daysUntilExpiration: daysUntilExpiration,
  deviceId: 'device',
  localTimestamp: received,
);

ProgramStats compute({
  List<Delivery> deliveries = const [],
  List<ConsumptionLog> logs = const [],
  List<PantryItem> pantryItems = const [],
}) => ProgramStats.compute(
  deliveries: deliveries,
  logs: logs,
  pantryItems: pantryItems,
  now: now,
);

MonthlyKg month(ProgramStats stats, int monthNumber) =>
    stats.months.singleWhere((m) => m.month.month == monthNumber);

void main() {
  test('kilos: g y mL se dividen entre 1000, L cuenta como kg y las unidades '
      'sin peso no cuentan', () {
    expect(kilograms(2, FoodUnit.kg), 2);
    expect(kilograms(250, FoodUnit.g), 0.25);
    expect(kilograms(1.5, FoodUnit.l), 1.5);
    expect(kilograms(500, FoodUnit.ml), 0.5);
    expect(kilograms(3, FoodUnit.piece), isNull);
    expect(kilograms(3, FoodUnit.can), isNull);
    expect(kilograms(3, FoodUnit.pack), isNull);
  });

  test('la gráfica cubre los últimos 6 meses, del más antiguo al actual', () {
    final stats = compute();
    expect(ProgramStats.windowStart(now), DateTime(2026, 5));
    expect(stats.months.map((m) => m.month), [
      DateTime(2026, 5),
      DateTime(2026, 6),
      DateTime(2026, 7),
      DateTime(2026, 8),
      DateTime(2026, 9),
      DateTime(2026, 10),
    ]);
  });

  group('este mes contra los mismos días del mes anterior', () {
    test('familias distintas y despensas de entregas entregadas', () {
      final stats = compute(
        deliveries: [
          delivery('a', DateTime(2026, 10, 2), packages: 2),
          delivery('a', DateTime(2026, 10, 9)),
          delivery('b', DateTime(2026, 10, 13)),
          // No cuentan: programada, cancelada, reasignada y después de hoy.
          delivery(
            'c',
            DateTime(2026, 10, 5),
            status: DeliveryStatus.scheduled,
          ),
          delivery(
            'd',
            DateTime(2026, 10, 5),
            status: DeliveryStatus.cancelled,
          ),
          delivery(
            'e',
            DateTime(2026, 10, 5),
            status: DeliveryStatus.reassigned,
          ),
          delivery('f', DateTime(2026, 10, 14)),
          // Mes anterior: solo del 1 al 13 de septiembre.
          delivery('a', DateTime(2026, 9, 1), packages: 3),
          delivery('g', DateTime(2026, 9, 13, 23)),
          delivery('h', DateTime(2026, 9, 14)),
        ],
      );
      expect(stats.familiesServed, 2);
      expect(stats.packagesDelivered, 4);
      expect(stats.familiesServedBefore, 2);
      expect(stats.packagesDeliveredBefore, 4);
      expect(stats.comparedUntil, DateTime(2026, 9, 13));
    });

    test('si el mes anterior es más corto, se compara hasta su último día', () {
      final stats = ProgramStats.compute(
        deliveries: [
          delivery('a', DateTime(2026, 9, 30)),
          delivery('b', DateTime(2026, 9, 29)),
        ],
        logs: const [],
        pantryItems: const [],
        now: DateTime(2026, 10, 31),
      );
      expect(stats.comparedUntil, DateTime(2026, 9, 30));
      expect(stats.familiesServedBefore, 2);
    });
  });

  group('consumo y desperdicio por mes', () {
    test('cada registro va al mes en que se escribió, en kilos', () {
      final stats = compute(
        logs: [
          log('Arroz', 2, FoodUnit.kg, DateTime(2026, 10, 3)),
          log('Frijol', 500, FoodUnit.g, DateTime(2026, 10, 10)),
          log('Leche entera', 1, FoodUnit.l, DateTime(2026, 9, 20)),
          log('Yogurt', 250, FoodUnit.g, DateTime(2026, 9, 21), wasted: true),
          // Antes de la ventana: no cuenta.
          log('Arroz', 9, FoodUnit.kg, DateTime(2026, 4, 30)),
        ],
      );
      expect(month(stats, 10).consumedKg, 2.5);
      expect(month(stats, 9).consumedKg, 1);
      expect(month(stats, 9).wastedKg, 0.25);
      expect(stats.consumedKg, 3.5);
      expect(stats.wastedKg, 0.25);
    });

    test('lo que sigue en la despensa ya caducado es desperdicio del mes en '
        'que caducó; lo que aún sirve no cuenta', () {
      final stats = compute(
        pantryItems: [
          // Recibido el 20 sep, caducó el 27 sep: desperdicio de septiembre.
          pantryItem(
            2,
            FoodUnit.l,
            received: DateTime(2026, 9, 20, 10),
            daysUntilExpiration: 7,
          ),
          // Caduca hoy: todavía sirve.
          pantryItem(
            1,
            FoodUnit.kg,
            received: DateTime(2026, 10, 10),
            daysUntilExpiration: 3,
          ),
          // Ya se acabó.
          pantryItem(
            0,
            FoodUnit.kg,
            received: DateTime(2026, 9, 1),
            daysUntilExpiration: 1,
          ),
        ],
      );
      expect(month(stats, 9).wastedKg, 2);
      expect(stats.wastedKg, 2);
      expect(stats.consumedKg, 0);
    });

    test('piezas, latas y paquetes van aparte, sumados por unidad', () {
      final stats = compute(
        logs: [
          log('Plátano', 8, FoodUnit.piece, DateTime(2026, 10, 1)),
          log('Plátano', 2, FoodUnit.piece, DateTime(2026, 9, 1), wasted: true),
          log('Atún en lata', 3, FoodUnit.can, DateTime(2026, 8, 1)),
          log('Atún en lata', 5, FoodUnit.can, DateTime(2026, 1, 1)),
        ],
        pantryItems: [
          pantryItem(
            1,
            FoodUnit.pack,
            received: DateTime(2026, 9, 1),
            daysUntilExpiration: 2,
          ),
        ],
      );
      expect(stats.unweighed, {
        FoodUnit.piece: 10,
        FoodUnit.can: 3,
        FoodUnit.pack: 1,
      });
      expect(stats.consumedKg, 0);
      expect(stats.wastedKg, 0);
    });
  });

  group('tendencias de consumo', () {
    test('comparan lo consumido por producto y unidad, y ordenan por el '
        'cambio más grande', () {
      final stats = compute(
        logs: [
          log('Arroz', 2, FoodUnit.kg, DateTime(2026, 10, 2)),
          log('arroz ', 1, FoodUnit.kg, DateTime(2026, 10, 5)),
          log('Arroz', 2, FoodUnit.kg, DateTime(2026, 9, 3)),
          log('Frijol', 1, FoodUnit.kg, DateTime(2026, 10, 2)),
          log('Frijol', 4, FoodUnit.kg, DateTime(2026, 9, 4)),
          // Sin consumo antes: no hay con qué comparar.
          log('Lenteja', 1, FoodUnit.kg, DateTime(2026, 10, 2)),
          // Después del 13 sep: fuera del periodo anterior.
          log('Avena', 1, FoodUnit.kg, DateTime(2026, 10, 2)),
          log('Avena', 9, FoodUnit.kg, DateTime(2026, 9, 20)),
          // El desperdicio no es consumo.
          log(
            'Leche entera',
            1,
            FoodUnit.l,
            DateTime(2026, 10, 2),
            wasted: true,
          ),
          log('Leche entera', 1, FoodUnit.l, DateTime(2026, 9, 2)),
        ],
      );
      expect(
        [for (final t in stats.trends) (t.productId, t.changePercent)],
        [('Leche entera', -100), ('Frijol', -75), ('Arroz', 50)],
      );
    });

    test('se queda con los que más cambiaron', () {
      final stats = ProgramStats.compute(
        deliveries: const [],
        logs: [
          for (final (i, name) in ['A', 'B', 'C', 'D'].indexed) ...[
            log(name, 1.0 + i, FoodUnit.kg, DateTime(2026, 10, 2)),
            log(name, 1, FoodUnit.kg, DateTime(2026, 9, 2)),
          ],
        ],
        pantryItems: const [],
        now: now,
        maxTrends: 2,
      );
      expect(stats.trends.map((t) => t.productId), ['D', 'C']);
    });
  });
}
