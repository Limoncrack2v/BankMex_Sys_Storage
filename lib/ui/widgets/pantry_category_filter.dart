import 'package:flutter/material.dart';

import '../../data/models/pantry_item.dart';
import '../formatting.dart';
import 'option_button.dart';

/// Categorías de [items] en el orden de [FoodType], sin repetir.
List<FoodType> pantryCategories(Iterable<PantryItem> items) {
  final present = {for (final item in items) item.type};
  return FoodType.values.where(present.contains).toList();
}

/// Píldoras «Todas» y una por categoría para filtrar la despensa. Se desplaza
/// de lado si no caben. [selected] null = «Todas».
class PantryCategoryFilter extends StatelessWidget {
  const PantryCategoryFilter({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<FoodType> categories;
  final FoodType? selected;
  final ValueChanged<FoodType?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          OptionButton(
            label: 'Todas',
            selected: selected == null,
            pill: true,
            onTap: () => onSelected(null),
          ),
          for (final category in categories) ...[
            const SizedBox(width: 8),
            OptionButton(
              label: foodTypeLabel(category),
              selected: selected == category,
              pill: true,
              onTap: () => onSelected(category),
            ),
          ],
        ],
      ),
    );
  }
}
