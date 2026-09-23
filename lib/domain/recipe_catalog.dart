import 'models/recipe.dart';

/// Catalog rules only. Persistence lives in [RecipeRepository].
class RecipeCatalog {
  static Recipe submitRecipe({
    String id = '',
    required String name,
    required List<RecipeIngredient> ingredients,
    required List<String> steps,
    required int prepTimeMinutes,
    required int caloriesPerServing,
    List<String> dietaryTags = const [],
  }) {
    return Recipe(
      id: id,
      name: name,
      ingredients: ingredients,
      steps: steps,
      prepTimeMinutes: prepTimeMinutes,
      caloriesPerServing: caloriesPerServing,
      status: RecipeStatus.pending,
      dietaryTags: dietaryTags,
    );
  }

  static Recipe approveRecipe(Recipe recipe) {
    return recipe.copyWith(status: RecipeStatus.approved);
  }

  /// Alta directa del staff: la familia ya puede verla.
  static Recipe publishRecipe({
    String id = '',
    required String name,
    required List<RecipeIngredient> ingredients,
    required List<String> steps,
    required int prepTimeMinutes,
    required int caloriesPerServing,
    List<String> dietaryTags = const [],
  }) {
    return approveRecipe(
      submitRecipe(
        id: id,
        name: name,
        ingredients: ingredients,
        steps: steps,
        prepTimeMinutes: prepTimeMinutes,
        caloriesPerServing: caloriesPerServing,
        dietaryTags: dietaryTags,
      ),
    );
  }
}
