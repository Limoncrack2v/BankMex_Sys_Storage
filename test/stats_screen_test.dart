import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/consumption_log.dart';
import 'package:bank_storage_app/data/models/delivery.dart';
import 'package:bank_storage_app/data/models/pantry_item.dart';
import 'package:bank_storage_app/ui/models/program_stats.dart';
import 'package:bank_storage_app/ui/screens/staff/stats_screen.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';

final now = DateTime(2026, 10, 13, 16);

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

Delivery delivered(String familyId, DateTime date, int packages) => Delivery(
  deliveryId: 'd-$familyId-${date.day}',
  familyId: familyId,
  familyName: familyId,
  deliveryDate: date,
  packages: packages,
  status: DeliveryStatus.delivered,
  items: const [],
  createdAt: date,
);

final sample = ProgramStats.compute(
  deliveries: [
    delivered('a', DateTime(2026, 10, 2), 2),
    delivered('b', DateTime(2026, 10, 9), 1),
    delivered('a', DateTime(2026, 9, 3), 1),
  ],
  logs: [
    log('Arroz', 3, FoodUnit.kg, DateTime(2026, 10, 2)),
    log('Arroz', 2, FoodUnit.kg, DateTime(2026, 9, 3)),
    log('Leche entera', 1, FoodUnit.l, DateTime(2026, 10, 3), wasted: true),
    log('Frijol', 4, FoodUnit.kg, DateTime(2026, 9, 20)),
    log('Plátano', 6, FoodUnit.piece, DateTime(2026, 10, 4)),
  ],
  pantryItems: const [],
  now: now,
);

Future<void> pumpStats(
  WidgetTester tester,
  Future<ProgramStats> Function() load,
) async {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: StatsScreen(load: load)),
    ),
  );
}

void main() {
  testWidgets('muestra las métricas, la gráfica y las tendencias', (
    tester,
  ) async {
    await pumpStats(tester, () async => sample);
    await tester.pumpAndSettle();

    expect(find.text('Este mes · del 1 al 13 de oct'), findsOneWidget);
    // 2 familias y 3 despensas, contra 1 y 1 del 1 al 13 de septiembre.
    expect(find.text('+1 vs.\u00a01–\u206013\u00a0sep'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('+200% vs.\u00a01–\u206013\u00a0sep'), findsOneWidget);

    // 9 kg consumidos (3 arroz oct, 2 arroz y 4 frijol sep) y 1 L caducado.
    expect(find.text('Últimos 6 meses · may–oct'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('90% del total'), findsOneWidget);
    expect(find.text('10% del total'), findsOneWidget);

    // La gráfica abre en el mes actual.
    expect(find.text('oct 2026'), findsOneWidget);
    expect(find.text('3 kg consumidos'), findsOneWidget);
    expect(find.text('1 kg desperdiciados'), findsOneWidget);
    expect(
      find.text('No incluye 6 piezas, que no tienen peso registrado.'),
      findsOneWidget,
    );

    // Arroz: 3 kg contra 2 kg del 1 al 13 sep. Frijol fue el 20 sep: no entra.
    await tester.scrollUntilVisible(find.text('Arroz'), 200);
    expect(find.text('3 kg ahora · 2 kg antes'), findsOneWidget);
    expect(find.text('↑ 50%'), findsOneWidget);
    expect(find.text('Frijol'), findsNothing);
  });

  testWidgets('al tocar un mes muestra sus valores', (tester) async {
    await pumpStats(tester, () async => sample);
    await tester.pumpAndSettle();

    final september = find.bySemanticsLabel(RegExp(r'^sep 2026'));
    await tester.ensureVisible(september);
    await tester.pumpAndSettle();
    await tester.tap(september);
    await tester.pump();

    expect(find.text('sep 2026'), findsOneWidget);
    expect(find.text('6 kg consumidos'), findsOneWidget);
    expect(find.text('0 kg desperdiciados'), findsOneWidget);
  });

  testWidgets('sin registros lo dice en lugar de dibujar barras vacías', (
    tester,
  ) async {
    final empty = ProgramStats.compute(
      deliveries: const [],
      logs: const [],
      pantryItems: const [],
      now: now,
    );
    await pumpStats(tester, () async => empty);
    await tester.pumpAndSettle();

    expect(
      find.text('Aún no hay consumo ni desperdicio registrado en estos meses.'),
      findsOneWidget,
    );
    expect(find.text('Sin registros'), findsNWidgets(2));
    expect(find.text('Sin entregas en 1–\u206013\u00a0sep'), findsOneWidget);
  });

  testWidgets('si falla la carga avisa y se puede reintentar', (tester) async {
    var calls = 0;
    final second = Completer<ProgramStats>();
    await pumpStats(tester, () {
      calls++;
      return calls == 1 ? Future.error(StateError('sin red')) : second.future;
    });
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No se pudieron cargar las estadísticas. Revisa tu conexión e '
        'intenta de nuevo.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    second.complete(sample);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Reintentar'), findsNothing);
    expect(find.text('oct 2026'), findsOneWidget);
  });
}
