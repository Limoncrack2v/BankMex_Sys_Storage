import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/pantry_item.dart';
import 'package:bank_storage_app/ui/screens/pantry/consumption_sheet.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';

PantryItem item(String id, String productId, {int days = 5}) => PantryItem(
  pantryItemId: id,
  productId: productId,
  deliveryId: 'entrega-001',
  type: FoodType.other,
  quantity: 2,
  unit: FoodUnit.kg,
  daysUntilExpiration: days,
  deviceId: 'device-test',
  localTimestamp: DateTime.now(),
);

/// Abre el sheet como lo hace la tarjeta de un producto en Despensa.
Future<void> openSheet(
  WidgetTester tester,
  List<PantryItem> items, {
  String? focusedItemId,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showConsumptionSheet(
              context,
              familyId: 'fam',
              items: items,
              focusedItemId: focusedItemId,
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  // Doce productos: el último queda fuera de la vista si nadie lo acerca.
  final pantry = [
    for (var i = 0; i < 11; i++) item('item-$i', 'Producto $i'),
    item('frijol-1', 'Frijol', days: 2),
  ];

  testWidgets('opens with the tapped product chosen and in view', (
    tester,
  ) async {
    await openSheet(tester, pantry, focusedItemId: 'frijol-1');

    expect(find.text('Frijol').hitTestable(), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Frijol')),
      isSemantics(isSelected: true),
    );
    expect(
      tester.getSemantics(find.text('Producto 0')),
      isSemantics(isSelected: false),
    );
  });

  testWidgets('with two bags of the same product, the tapped one is chosen', (
    tester,
  ) async {
    await openSheet(tester, [
      item('frijol-1', 'Frijol', days: 2),
      item('frijol-2', 'Frijol', days: 9),
    ], focusedItemId: 'frijol-2');

    expect(
      tester.getSemantics(find.text('Frijol').at(0)),
      isSemantics(isSelected: false),
    );
    expect(
      tester.getSemantics(find.text('Frijol').at(1)),
      isSemantics(isSelected: true),
    );
  });

  testWidgets('from "Registrar consumo" nothing is chosen', (tester) async {
    await openSheet(tester, pantry);

    expect(
      tester.getSemantics(find.text('Producto 0')),
      isSemantics(isSelected: false),
    );
    expect(find.text('Frijol').hitTestable(), findsNothing);
  });
}
