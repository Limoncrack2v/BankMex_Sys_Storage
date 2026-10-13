import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/models/pantry_item.dart';
import 'package:bank_storage_app/ui/theme/app_theme.dart';
import 'package:bank_storage_app/ui/widgets/option_button.dart';
import 'package:bank_storage_app/ui/widgets/pantry_category_filter.dart';

PantryItem item(String productId, FoodType type) => PantryItem(
  pantryItemId: productId,
  productId: productId,
  deliveryId: 'entrega-1',
  type: type,
  quantity: 1,
  unit: FoodUnit.kg,
  daysUntilExpiration: 10,
  deviceId: 'device-test',
  localTimestamp: DateTime(2026, 10, 1),
);

Future<void> _pumpFilter(
  WidgetTester tester, {
  required List<FoodType> categories,
  FoodType? selected,
  ValueChanged<FoodType?>? onSelected,
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: PantryCategoryFilter(
        categories: categories,
        selected: selected,
        onSelected: onSelected ?? (_) {},
      ),
    ),
  ),
);

bool _isSelected(WidgetTester tester, String label) => tester
    .widget<OptionButton>(find.widgetWithText(OptionButton, label))
    .selected;

void main() {
  group('pantryCategories', () {
    test('lists each category once, in the order of FoodType', () {
      final categories = pantryCategories([
        item('Leche entera', FoodType.dairy),
        item('Arroz', FoodType.grain),
        item('Yogurt natural', FoodType.dairy),
        item('Frijol', FoodType.legume),
      ]);

      expect(categories, [FoodType.grain, FoodType.legume, FoodType.dairy]);
    });

    test('an empty pantry has no categories', () {
      expect(pantryCategories(const []), isEmpty);
    });
  });

  group('PantryCategoryFilter', () {
    testWidgets('shows «Todas» and one pill per category', (tester) async {
      await _pumpFilter(
        tester,
        categories: const [FoodType.grain, FoodType.dairy],
      );

      expect(find.byType(OptionButton), findsNWidgets(3));
      expect(find.text('Todas'), findsOneWidget);
      expect(find.text('Granos y cereales'), findsOneWidget);
      expect(find.text('Lácteos'), findsOneWidget);
      expect(_isSelected(tester, 'Todas'), isTrue);
    });

    testWidgets('marks the selected category', (tester) async {
      await _pumpFilter(
        tester,
        categories: const [FoodType.grain, FoodType.dairy],
        selected: FoodType.dairy,
      );

      expect(_isSelected(tester, 'Lácteos'), isTrue);
      expect(_isSelected(tester, 'Todas'), isFalse);
      expect(_isSelected(tester, 'Granos y cereales'), isFalse);
    });

    testWidgets('reports the tapped category, and null for «Todas»', (
      tester,
    ) async {
      final taps = <FoodType?>[];
      await _pumpFilter(
        tester,
        categories: const [FoodType.grain, FoodType.dairy],
        selected: FoodType.grain,
        onSelected: taps.add,
      );

      await tester.tap(find.text('Lácteos'));
      await tester.tap(find.text('Todas'));

      expect(taps, [FoodType.dairy, null]);
    });
  });
}
