import 'firestore_codec.dart';
import 'models/family_profile.dart';
import 'models/meal_plan.dart';
import 'models/pantry_item.dart';
import 'models/recipe.dart';
import 'fifo_scorer.dart';
import 'name_normalizer.dart';
import 'pantry_recipe_filter.dart';
import 'portion_adjuster.dart';
import 'unit_converter.dart';

class MealPlanGeneration {
  const MealPlanGeneration({
    required this.plan,
    required this.updatedPantry,
    required this.requestedDays,
    required this.filledDays,
  });

  final MealPlan plan;
  final List<PantryItem> updatedPantry;
  final int requestedDays;
  final int filledDays;

  Map<String, dynamic> toJson() => {
        'requestedDays': requestedDays,
        'filledDays': filledDays,
        'plan': plan.toJson(),
        'updatedPantry': updatedPantry.map((item) => item.toJson()).toList(),
      };
}

class MealPlanGenerator {
  static MealPlanGeneration generateMealPlan({
    required FamilyProfile family,
    required List<PantryItem> pantryItems,
    required List<Recipe> recipes,
    required int days,
    DateTime? startDate,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final start = startDate ?? DateTime(clock.year, clock.month, clock.day);
    final servings = roundQuantity(PortionAdjuster.familyServingFactor(family));
    var remaining = pantryItems.map((item) => item.copyWith()).toList();
    final meals = <MealPlanMeal>[];
    final approved = recipes
        .where((recipe) => recipe.status == RecipeStatus.approved)
        .toList();

    for (var offset = 0; offset < days; offset++) {
      final day = DateTime(start.year, start.month, start.day + offset);
      final adjusted = approved
          .map((recipe) => PortionAdjuster.adjustPortions(recipe, family))
          .toList();
      final feasible = PantryRecipeFilter.filterRecipesByPantry(
        pantryItems: remaining,
        recipes: adjusted,
        now: clock,
      );
      if (feasible.isEmpty) continue;

      final chosen = FifoScorer.pickBest(
        recipes: feasible,
        pantryItems: remaining,
        now: clock,
      );
      meals.add(
        MealPlanMeal(date: day, recipeId: chosen.id, servings: servings),
      );
      remaining = deductIngredients(
        pantry: remaining,
        ingredients: chosen.ingredients,
        now: clock,
      );
    }

    final end = DateTime(start.year, start.month, start.day + days);
    return MealPlanGeneration(
      plan: MealPlan(
        id: '',
        familyId: family.id,
        dateRangeStart: start,
        dateRangeEnd: end,
        meals: meals,
      ),
      updatedPantry: remaining,
      requestedDays: days,
      filledDays: meals.length,
    );
  }

  static List<PantryItem> deductIngredients({
    required List<PantryItem> pantry,
    required List<RecipeIngredient> ingredients,
    required DateTime now,
  }) {
    final result = pantry.map((item) => item.copyWith()).toList();
    for (final ingredient in ingredients) {
      var needed = UnitConverter.toBase(ingredient.quantity, ingredient.unit);
      final candidates = <int>[];
      for (var i = 0; i < result.length; i++) {
        final item = result[i];
        if (!item.isUsable(now)) continue;
        final nameMatch =
            NameNormalizer.matches(item.name, ingredient.productName) ||
                NameNormalizer.matches(item.productId, ingredient.productName);
        if (!nameMatch) continue;
        if (!UnitConverter.compatible(item.unit, ingredient.unit)) continue;
        candidates.add(i);
      }
      candidates.sort(
        (a, b) => result[a].expirationDate.compareTo(result[b].expirationDate),
      );

      for (final index in candidates) {
        if (needed <= 0) break;
        final item = result[index];
        final available = UnitConverter.toBase(item.quantity, item.unit);
        final take = needed < available ? needed : available;
        final leftover = available - take;
        final leftoverInUnit = roundQuantity(
          UnitConverter.fromBase(leftover, item.unit),
        );
        final takenInUnit = roundQuantity(
          UnitConverter.fromBase(take, item.unit),
        );
        result[index] = item.copyWith(
          quantity: leftoverInUnit,
          consumedQuantity: roundQuantity(item.consumedQuantity + takenInUnit),
          consumedAt: now,
          status: leftoverInUnit <= 0.0001
              ? PantryItemStatus.consumed
              : item.status,
        );
        needed -= take;
      }
    }
    return result;
  }
}
