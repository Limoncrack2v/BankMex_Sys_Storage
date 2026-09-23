import 'models/family_profile.dart';
import 'models/pantry_item.dart';
import 'models/recipe.dart';
import 'pantry_recipe_filter.dart';
import 'portion_adjuster.dart';
import 'fifo_scorer.dart';

class RecipeOnDemand {
  static Recipe? getSingleRecipeOnDemand({
    required FamilyProfile family,
    required List<PantryItem> pantryItems,
    required List<Recipe> recipes,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final approved = recipes.where((recipe) => recipe.status == RecipeStatus.approved);
    final adjusted = approved
        .map((recipe) => PortionAdjuster.adjustPortions(recipe, family))
        .toList();
    final covered = PantryRecipeFilter.filterRecipesByPantry(
      pantryItems: pantryItems,
      recipes: adjusted,
      now: clock,
    );
    if (covered.isEmpty) return null;
    return FifoScorer.pickBest(recipes: covered, pantryItems: pantryItems, now: clock);
  }
}
