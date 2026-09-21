import 'expiration_urgency.dart';

// Modelos solo de UI: todavía no hay colección de recetas ni de plan de
// comidas en Firestore.

class RecipeIngredient {
  const RecipeIngredient(this.name, this.amount, {this.available = true});

  final String name;
  final String amount;

  /// Si la familia lo tiene en su despensa.
  final bool available;
}

class Recipe {
  const Recipe({
    required this.name,
    required this.image,
    required this.minutes,
    required this.servings,
    required this.kcalPerServing,
    required this.ingredients,
    required this.steps,
  });

  final String name;
  final String image;
  final int minutes;
  final int servings;
  final int kcalPerServing;
  final List<RecipeIngredient> ingredients;
  final List<String> steps;

  int get availableIngredients => ingredients.where((i) => i.available).length;

  bool get hasAllIngredients => availableIngredients == ingredients.length;

  bool get isQuick => minutes <= 30;
}

class MealPlanEntry {
  const MealPlanEntry({
    required this.day,
    required this.recipe,
    required this.reason,
    required this.urgency,
  });

  /// Abreviatura del día, p. ej. "Lun".
  final String day;
  final Recipe recipe;

  /// Por qué se eligió la receta, p. ej. "Jamón caduca en 3 días".
  final String reason;
  final ExpirationUrgency urgency;
}
