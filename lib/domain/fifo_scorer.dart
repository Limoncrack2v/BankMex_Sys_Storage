import 'models/pantry_item.dart';
import 'models/recipe.dart';
import 'name_normalizer.dart';
import 'unit_converter.dart';

class FifoScorer {
  static Recipe pickBest({
    required List<Recipe> recipes,
    required List<PantryItem> pantryItems,
    required DateTime now,
  }) {
    Recipe? best;
    var bestScore = double.negativeInfinity;
    for (final recipe in recipes) {
      final score = scoreRecipe(recipe, pantryItems, now);
      if (score > bestScore) {
        bestScore = score;
        best = recipe;
      }
    }
    return best!;
  }

  static double scoreRecipe(
    Recipe recipe,
    List<PantryItem> pantryItems,
    DateTime now,
  ) {
    final usable = pantryItems.where((item) => item.isUsable(now)).toList()
      ..sort((a, b) => a.expirationDate.compareTo(b.expirationDate));
    if (usable.isEmpty) return 0;

    var score = 0.0;
    for (var index = 0; index < usable.length; index++) {
      final item = usable[index];
      final urgency = usable.length - index;
      if (!_usesItem(recipe, item)) continue;
      final hoursLeft =
          item.expirationDate.difference(now).inHours.clamp(0, 100000);
      score += urgency * 10 + (100000 - hoursLeft) / 1000;
    }
    return score;
  }

  static bool _usesItem(Recipe recipe, PantryItem item) {
    return recipe.ingredients.any((ingredient) {
      final nameMatch = NameNormalizer.matches(item.name, ingredient.productName) ||
          NameNormalizer.matches(item.productId, ingredient.productName);
      return nameMatch && UnitConverter.compatible(item.unit, ingredient.unit);
    });
  }
}
