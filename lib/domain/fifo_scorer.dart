import 'models/pantry_item.dart';
import 'models/recipe.dart';
import 'name_normalizer.dart';
import 'pantry_recipe_filter.dart';
import 'unit_converter.dart';

typedef _Rank = ({DateTime? soonest, int missing});

/// Elige la receta que usa lo que caduca antes en la despensa (lo caducado o
/// ya consumido no cuenta). Si el producto más urgente de dos recetas caduca
/// el mismo día, va primero la que tiene menos ingredientes faltantes, y
/// después la que venía antes en la lista. Las que no usan nada de la
/// despensa van al final. Es el mismo orden que el plan de la UI
/// (_compareRanked).
class FifoScorer {
  static Recipe pickBest({
    required List<Recipe> recipes,
    required List<PantryItem> pantryItems,
    required DateTime now,
  }) {
    Recipe? best;
    _Rank? bestRank;
    for (final recipe in recipes) {
      final rank = _rank(recipe, pantryItems, now);
      if (bestRank == null || _compare(rank, bestRank) < 0) {
        best = recipe;
        bestRank = rank;
      }
    }
    return best!;
  }

  static _Rank _rank(
    Recipe recipe,
    List<PantryItem> pantryItems,
    DateTime now,
  ) {
    DateTime? soonest;
    for (final item in pantryItems) {
      if (!item.isUsable(now) || !_usesItem(recipe, item)) continue;
      final expiration = item.expirationDate;
      final day = DateTime(expiration.year, expiration.month, expiration.day);
      if (soonest == null || day.isBefore(soonest)) soonest = day;
    }
    final missing = PantryRecipeFilter.coverage(
      pantryItems: pantryItems,
      recipe: recipe,
      now: now,
    ).missing.length;
    return (soonest: soonest, missing: missing);
  }

  static int _compare(_Rank a, _Rank b) {
    final (aDay, bDay) = (a.soonest, b.soonest);
    if (aDay != bDay) {
      if (aDay == null) return 1;
      if (bDay == null) return -1;
      return aDay.compareTo(bDay);
    }
    return a.missing.compareTo(b.missing);
  }

  static bool _usesItem(Recipe recipe, PantryItem item) {
    return recipe.ingredients.any((ingredient) {
      final nameMatch = NameNormalizer.matches(item.name, ingredient.productName) ||
          NameNormalizer.matches(item.productId, ingredient.productName);
      return nameMatch && UnitConverter.compatible(item.unit, ingredient.unit);
    });
  }
}
