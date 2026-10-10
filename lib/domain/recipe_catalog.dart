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
    List<String> nutritionalTags = const [],
    List<String> requiredEquipment = const [],
  }) {
    validateTags(
      nutritionalTags: nutritionalTags,
      requiredEquipment: requiredEquipment,
    );
    return Recipe(
      id: id,
      name: name,
      ingredients: ingredients,
      steps: steps,
      prepTimeMinutes: prepTimeMinutes,
      caloriesPerServing: caloriesPerServing,
      status: RecipeStatus.pending,
      dietaryTags: dietaryTags,
      nutritionalTags: nutritionalTags,
      requiredEquipment: requiredEquipment,
    );
  }

  /// Lanza [ArgumentError] con un mensaje para mostrar si alguna etiqueta o
  /// electrodoméstico no se reconoce o se repite. Al editar, [previous] es la
  /// receta guardada: los ids que ya tenía se aceptan aunque esta versión de
  /// la app no los conozca, para no borrarlos.
  static void validateTags({
    required List<String> nutritionalTags,
    required List<String> requiredEquipment,
    Recipe? previous,
  }) {
    final error =
        Recipe.validateNutritionalTags(
          nutritionalTags,
          keep: {...?previous?.nutritionalTags},
        ) ??
        Recipe.validateRequiredEquipment(
          requiredEquipment,
          keep: {...?previous?.requiredEquipment},
        );
    if (error != null) throw ArgumentError(error);
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
    List<String> nutritionalTags = const [],
    List<String> requiredEquipment = const [],
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
        nutritionalTags: nutritionalTags,
        requiredEquipment: requiredEquipment,
      ),
    );
  }
}
