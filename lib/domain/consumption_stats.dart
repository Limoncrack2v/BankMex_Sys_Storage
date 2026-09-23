import 'models/consumption_waste_stats.dart';
import 'models/pantry_item.dart';
import 'firestore_codec.dart';

class ConsumptionStatsCalculator {
  static ConsumptionWasteStats getConsumptionWasteStats({
    required List<PantryItem> pantryItems,
    String? category,
    DateRange? dateRange,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final consumed = <PantryItem>[];
    final wasted = <PantryItem>[];

    for (final item in pantryItems) {
      if (category != null &&
          category.isNotEmpty &&
          item.category.toLowerCase() != category.toLowerCase()) {
        continue;
      }

      if (item.consumedQuantity > 0 &&
          _inRange(item.consumedAt ?? item.expirationDate, dateRange)) {
        consumed.add(item);
      }

      final leftoverExpired = item.quantity > 0 && item.isExpired(clock);
      if (leftoverExpired && _inRange(item.expirationDate, dateRange)) {
        wasted.add(item);
      }
    }

    return ConsumptionWasteStats(
      consumedQuantity: roundQuantity(
        consumed.fold<double>(0, (sum, item) => sum + item.consumedQuantity),
      ),
      wastedQuantity: roundQuantity(
        wasted.fold<double>(0, (sum, item) => sum + item.quantity),
      ),
      consumedItemCount: consumed.length,
      wastedItemCount: wasted.length,
      consumedByCategory: _byCategory(consumed, (item) => item.consumedQuantity),
      wastedByCategory: _byCategory(wasted, (item) => item.quantity),
      consumedItems: consumed.map((item) => item.toJson()).toList(),
      wastedItems: wasted.map((item) => item.toJson()).toList(),
    );
  }

  static bool _inRange(DateTime value, DateRange? range) {
    if (range == null) return true;
    return range.contains(value);
  }

  static Map<String, double> _byCategory(
    List<PantryItem> items,
    double Function(PantryItem item) quantityOf,
  ) {
    final totals = <String, double>{};
    for (final item in items) {
      totals[item.category] =
          roundQuantity((totals[item.category] ?? 0) + quantityOf(item));
    }
    return totals;
  }
}
