import 'models/family_profile.dart';
import 'models/child_profile.dart';
import 'models/recipe.dart';
import 'firestore_codec.dart';

/// Recipes are authored for this many adult-equivalent servings.
const double kRecipeBaseServings = 4;

class PortionAdjuster {
  static const double adultWeightKg = 70;

  static double familyServingFactor(FamilyProfile family) {
    final adultServings = family.adults.toDouble();
    final childServings = family.children.fold<double>(
      0,
      (sum, child) => sum + childFactor(child),
    );
    return adultServings + childServings;
  }

  static double childFactor(ChildProfile child) {
    final ageFactor = _ageFactor(child.age);
    if (child.weight <= 0) return ageFactor;
    final weightFactor = (child.weight / adultWeightKg).clamp(0.2, 1.0);
    return (ageFactor * 0.7) + (weightFactor * 0.3);
  }

  static double _ageFactor(int age) {
    if (age <= 1) return 0.25;
    if (age <= 3) return 0.40;
    if (age <= 8) return 0.60;
    if (age <= 13) return 0.80;
    return 1.0;
  }

  static double scaleFor(FamilyProfile family, {double? baseServings}) {
    final target = familyServingFactor(family);
    final base = baseServings ?? kRecipeBaseServings;
    if (base == 0) return 1;
    return target / base;
  }

  static Recipe adjustPortions(Recipe recipe, FamilyProfile family) {
    final base =
        recipe.servings > 0 ? recipe.servings.toDouble() : kRecipeBaseServings;
    final scale = scaleFor(family, baseServings: base);
    return recipe.copyWith(
      ingredients: recipe.ingredients
          .map(
            (ingredient) => ingredient.copyWith(
              quantity: roundQuantity(ingredient.quantity * scale),
            ),
          )
          .toList(),
    );
  }
}
