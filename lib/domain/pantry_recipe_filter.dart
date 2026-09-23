import 'models/pantry_item.dart';
import 'models/recipe.dart';
import 'name_normalizer.dart';
import 'unit_converter.dart';

class PantryCoverage {
  const PantryCoverage({required this.covered, required this.missing});

  final bool covered;
  final List<RecipeIngredient> missing;
}

class PantryRecipeFilter {
  static List<Recipe> filterRecipesByPantry({
    required List<PantryItem> pantryItems,
    required List<Recipe> recipes,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    return recipes
        .where((recipe) =>
            coverage(pantryItems: pantryItems, recipe: recipe, now: clock).covered)
        .toList();
  }

  static PantryCoverage coverage({
    required List<PantryItem> pantryItems,
    required Recipe recipe,
    required DateTime now,
  }) {
    final missing = <RecipeIngredient>[];
    for (final ingredient in recipe.ingredients) {
      final available = _availableBase(pantryItems, ingredient, now);
      final needed = UnitConverter.toBase(ingredient.quantity, ingredient.unit);
      if (available + 0.0001 < needed) {
        missing.add(ingredient);
      }
    }
    return PantryCoverage(covered: missing.isEmpty, missing: missing);
  }

  static double _availableBase(
    List<PantryItem> pantryItems,
    RecipeIngredient ingredient,
    DateTime now,
  ) {
    var total = 0.0;
    for (final item in pantryItems) {
      if (!item.isUsable(now)) continue;
      final nameMatch = NameNormalizer.matches(item.name, ingredient.productName) ||
          NameNormalizer.matches(item.productId, ingredient.productName);
      if (!nameMatch) continue;
      if (!UnitConverter.compatible(item.unit, ingredient.unit)) continue;
      total += UnitConverter.toBase(item.quantity, item.unit);
    }
    return total;
  }
}
