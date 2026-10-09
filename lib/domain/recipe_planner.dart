import 'meal_plan_generator.dart';
import 'models/family_profile.dart';
import 'models/pantry_item.dart';
import 'models/recipe.dart';
import 'recipe_on_demand.dart';

/// Elige recetas para una familia con lo que hay en su despensa.
///
/// Hoy lo implementa [RuleBasedRecipePlanner]. Una versión con IA (detrás de
/// una Cloud Function) podrá implementarlo después sin cambiar a quien lo
/// usa; por eso los métodos regresan Future aunque las reglas no esperen nada.
abstract interface class RecipePlanner {
  /// Una receta para cocinar ahora, o null si ninguna alcanza.
  Future<Recipe?> suggestRecipe({
    required FamilyProfile family,
    required List<PantryItem> pantryItems,
    required List<Recipe> recipes,
    DateTime? now,
  });

  /// Una receta por día durante [days] días desde [startDate] (hoy si no se
  /// da).
  Future<MealPlanGeneration> planDays({
    required FamilyProfile family,
    required List<PantryItem> pantryItems,
    required List<Recipe> recipes,
    required int days,
    DateTime? startDate,
    DateTime? now,
  });
}

/// Solo reglas, sin servicios externos: delega en [RecipeOnDemand] y
/// [MealPlanGenerator], así que los cambios al filtro, a las porciones o a
/// FIFO le llegan sin tocar esta clase.
class RuleBasedRecipePlanner implements RecipePlanner {
  const RuleBasedRecipePlanner();

  @override
  Future<Recipe?> suggestRecipe({
    required FamilyProfile family,
    required List<PantryItem> pantryItems,
    required List<Recipe> recipes,
    DateTime? now,
  }) async {
    return RecipeOnDemand.getSingleRecipeOnDemand(
      family: family,
      pantryItems: pantryItems,
      recipes: recipes,
      now: now,
    );
  }

  @override
  Future<MealPlanGeneration> planDays({
    required FamilyProfile family,
    required List<PantryItem> pantryItems,
    required List<Recipe> recipes,
    required int days,
    DateTime? startDate,
    DateTime? now,
  }) async {
    return MealPlanGenerator.generateMealPlan(
      family: family,
      pantryItems: pantryItems,
      recipes: recipes,
      days: days,
      startDate: startDate,
      now: now,
    );
  }
}
