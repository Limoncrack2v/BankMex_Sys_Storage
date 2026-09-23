import 'package:bank_storage_app/domain/consumption_stats.dart';
import 'package:bank_storage_app/domain/models/consumption_waste_stats.dart';
import 'package:bank_storage_app/domain/models/pantry_item.dart';
import 'package:flutter_test/flutter_test.dart';

PantryItem item({
  required String id,
  required double quantity,
  required DateTime expiration,
  double consumedQuantity = 0,
  DateTime? consumedAt,
  String category = 'verduras',
}) {
  return PantryItem(
    id: id,
    familyId: 'fam',
    productId: id,
    name: id,
    quantity: quantity,
    unit: 'g',
    expirationDate: expiration,
    category: category,
    originalQuantity: quantity + consumedQuantity,
    consumedQuantity: consumedQuantity,
    status: quantity <= 0
        ? PantryItemStatus.consumed
        : PantryItemStatus.available,
    consumedAt: consumedAt,
  );
}

void main() {
  final now = DateTime(2026, 9, 20);

  test('splits consumed vs expired leftover and honors filters', () {
    final items = [
      item(
        id: 'avena',
        quantity: 400,
        expiration: DateTime(2026, 10, 1),
        consumedQuantity: 200,
        consumedAt: DateTime(2026, 9, 18),
        category: 'granos',
      ),
      item(
        id: 'tomate',
        quantity: 250,
        expiration: DateTime(2026, 9, 10),
        category: 'verduras',
      ),
      item(
        id: 'leche',
        quantity: 0,
        expiration: DateTime(2026, 9, 25),
        consumedQuantity: 1,
        consumedAt: DateTime(2026, 8, 1),
        category: 'lacteos',
      ),
    ];

    final all = ConsumptionStatsCalculator.getConsumptionWasteStats(
      pantryItems: items,
      now: now,
    );
    expect(all.consumedItemCount, 2);
    expect(all.wastedItemCount, 1);
    expect(all.wastedByCategory['verduras'], 250);

    final verduras = ConsumptionStatsCalculator.getConsumptionWasteStats(
      pantryItems: items,
      category: 'verduras',
      now: now,
    );
    expect(verduras.consumedItemCount, 0);
    expect(verduras.wastedItemCount, 1);

    final september = ConsumptionStatsCalculator.getConsumptionWasteStats(
      pantryItems: items,
      dateRange: DateRange(
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 30),
      ),
      now: now,
    );
    expect(september.consumedItemCount, 1);
    expect(september.consumedItems.single['id'], 'avena');
  });
}
