import 'models/recipe.dart';

/// Catalog rules only. Persistence lives in [RecipeRepository].
class RecipeCatalog {
  /// Los máximos de firestore.rules (validRecipe): las reglas revisan cada
  /// ingrediente y cada paso por su índice y tienen un tope de expresiones,
  /// así que pasarlos rechaza la receta.
  static const int maxIngredients = 10;
  static const int maxSteps = 12;
  static const int maxDietaryTags = 10;

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
    RecipeStatus status = RecipeStatus.pending,
  }) {
    if (status == RecipeStatus.approved) {
      throw ArgumentError('Solo el nutriólogo aprueba una receta');
    }
    validateLimits(
      ingredients: ingredients,
      steps: steps,
      dietaryTags: dietaryTags,
    );
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
      status: status,
      dietaryTags: dietaryTags,
      nutritionalTags: nutritionalTags,
      requiredEquipment: requiredEquipment,
    );
  }

  /// Lanza [ArgumentError] si la receta pasa los máximos de las reglas.
  static void validateLimits({
    required List<RecipeIngredient> ingredients,
    required List<String> steps,
    List<String> dietaryTags = const [],
  }) {
    if (ingredients.length > maxIngredients) {
      throw ArgumentError(
        'Una receta lleva máximo $maxIngredients ingredientes',
      );
    }
    if (steps.length > maxSteps) {
      throw ArgumentError('Una receta lleva máximo $maxSteps pasos');
    }
    if (dietaryTags.length > maxDietaryTags) {
      throw ArgumentError('Una receta lleva máximo $maxDietaryTags etiquetas');
    }
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

  /// La receta ya aprobada por [approvedBy] (uid del nutriólogo). Solo una
  /// pending se aprueba.
  static Recipe approveRecipe(
    Recipe recipe, {
    required String approvedBy,
    required DateTime at,
  }) {
    if (recipe.status != RecipeStatus.pending) {
      throw StateError('Solo se aprueba una receta pendiente');
    }
    return Recipe(
      id: recipe.id,
      name: recipe.name,
      ingredients: recipe.ingredients,
      steps: recipe.steps,
      prepTimeMinutes: recipe.prepTimeMinutes,
      caloriesPerServing: recipe.caloriesPerServing,
      status: RecipeStatus.approved,
      dietaryTags: recipe.dietaryTags,
      nutritionalTags: recipe.nutritionalTags,
      requiredEquipment: recipe.requiredEquipment,
      image: recipe.image,
      servings: recipe.servings,
      approvedBy: approvedBy,
      approvedAt: at,
    );
  }

  /// La receta que regresa a draft con el motivo de [rejectedBy]. Solo una
  /// pending se rechaza, y el motivo es obligatorio.
  static Recipe rejectRecipe(
    Recipe recipe, {
    required String rejectedBy,
    required String note,
    required DateTime at,
  }) {
    if (recipe.status != RecipeStatus.pending) {
      throw StateError('Solo se rechaza una receta pendiente');
    }
    final error = validateReviewNote(note);
    if (error != null) throw ArgumentError(error);
    return Recipe(
      id: recipe.id,
      name: recipe.name,
      ingredients: recipe.ingredients,
      steps: recipe.steps,
      prepTimeMinutes: recipe.prepTimeMinutes,
      caloriesPerServing: recipe.caloriesPerServing,
      status: RecipeStatus.draft,
      dietaryTags: recipe.dietaryTags,
      nutritionalTags: recipe.nutritionalTags,
      requiredEquipment: recipe.requiredEquipment,
      image: recipe.image,
      servings: recipe.servings,
      reviewNote: note.trim(),
      rejectedBy: rejectedBy,
      rejectedAt: at,
    );
  }

  /// null si [note] sirve como motivo de un rechazo.
  static String? validateReviewNote(String note) {
    final trimmed = note.trim();
    if (trimmed.isEmpty) return 'Escribe el motivo del rechazo';
    if (trimmed.length > Recipe.maxReviewNoteLength) {
      return 'El motivo lleva máximo ${Recipe.maxReviewNoteLength} caracteres';
    }
    return null;
  }
}
