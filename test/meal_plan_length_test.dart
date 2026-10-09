import 'package:bank_storage_app/domain/meal_plan_length.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 8, 9);

  int daysFor(DateTime? nextDelivery) =>
      MealPlanLength.daysFor(nextDelivery: nextDelivery, now: now);

  test('is weekly when the next delivery is at most 7 days away', () {
    expect(daysFor(DateTime(2026, 10, 8)), 7);
    expect(daysFor(DateTime(2026, 10, 9)), 7);
    expect(daysFor(DateTime(2026, 10, 13)), 7);
    expect(daysFor(DateTime(2026, 10, 15)), 7);
  });

  test('is biweekly when the next delivery is more than 7 days away', () {
    expect(daysFor(DateTime(2026, 10, 16)), 14);
    expect(daysFor(DateTime(2026, 10, 22)), 14);
    expect(daysFor(DateTime(2026, 12, 1)), 14);
  });

  test('is weekly without a scheduled delivery', () {
    expect(daysFor(null), 7);
  });

  test('is weekly when the delivery date has already passed', () {
    expect(daysFor(DateTime(2026, 10, 7)), 7);
    expect(daysFor(DateTime(2026, 9, 1)), 7);
  });

  test('counts calendar days, not hours', () {
    // 7 días de calendario, aunque falten más de 7 × 24 horas.
    expect(daysFor(DateTime(2026, 10, 15, 23, 59)), 7);
    // 8 días de calendario, aunque falten menos de 8 × 24 horas.
    expect(daysFor(DateTime(2026, 10, 16, 0, 1)), 14);
    expect(
      MealPlanLength.daysFor(
        nextDelivery: DateTime(2026, 10, 16),
        now: DateTime(2026, 10, 8, 23, 59),
      ),
      14,
    );
  });
}
