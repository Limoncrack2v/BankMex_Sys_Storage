class DateRange {
  const DateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  bool contains(DateTime value) {
    return !value.isBefore(start) && !value.isAfter(end);
  }
}

class ConsumptionWasteStats {
  const ConsumptionWasteStats({
    required this.consumedQuantity,
    required this.wastedQuantity,
    required this.consumedItemCount,
    required this.wastedItemCount,
    required this.consumedByCategory,
    required this.wastedByCategory,
    required this.consumedItems,
    required this.wastedItems,
  });

  final double consumedQuantity;
  final double wastedQuantity;
  final int consumedItemCount;
  final int wastedItemCount;
  final Map<String, double> consumedByCategory;
  final Map<String, double> wastedByCategory;
  final List<Map<String, dynamic>> consumedItems;
  final List<Map<String, dynamic>> wastedItems;

  Map<String, dynamic> toJson() => {
        'consumedQuantity': consumedQuantity,
        'wastedQuantity': wastedQuantity,
        'consumedItemCount': consumedItemCount,
        'wastedItemCount': wastedItemCount,
        'consumedByCategory': consumedByCategory,
        'wastedByCategory': wastedByCategory,
        'consumedItems': consumedItems,
        'wastedItems': wastedItems,
      };
}
